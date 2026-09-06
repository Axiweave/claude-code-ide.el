# Contract: Remote Session Access

**Status**: Implemented with passing automated regressions. Live acceptance passed on 2026-09-06 as recorded in the [validation guide](../quickstart.md).
**Specification**: [spec.md](../spec.md)
**Model**: [data-model.md](../data-model.md)
**Attach guard**: [Stock zmx attach guard](zmx-attach-guard.md)

## User Configuration

Customization:

```elisp
(setq claude-code-ide-remote-hosts '("ramhorn" "other-personal-host"))
```

The default is an empty list. Destinations are exact SSH aliases or account-qualified host strings. SSH configuration owns keys, ports, jump hosts, and remote command environment.

The remote executable is `zmx` from that environment's PATH. The local `claude-code-ide-zmx-program` setting remains local and must not supply a remote absolute path.

## Existing Attachment Commands

Extend these commands with an optional programmatic `host` argument:

- `claude-code-ide-attach`
- `claude-code-ide-attach-all`
- `claude-code-ide-attach-select`

Without a prefix or host, keep current local behavior. With `C-u`, prompt for one configured host before discovery. A supplied host must pass the same validation.

Reuse the existing picker, bulk-skip behavior, and marked-selection buffer. Include the host in remote candidate labels and retain it in each candidate's data.

Programmatic remote invocation starts an asynchronous request and returns its process handle. Interactive completion presents the result when the request finishes. Local return behavior stays unchanged.

No remote entry point checks whether an Agent executable exists locally. Agent identification selects existing terminal behavior, not a command to execute remotely.

## Manager Commands

| Action | Interface | Behavior |
|--------|-------------------|----------|
| Local attach | Existing `a` and `A` | Unchanged |
| Remote attach | `C-u a` or `C-u A` | Prompt for configured host, then reuse existing selection |
| Reattach | `c`, `claude-code-ide-manager-reattach-at-point` | Explicitly reconnect the selected remembered remote target |
| Stop | `K`, `claude-code-ide-manager-stop-at-point` | Confirm host and exact target before a remote Stop request |
| Detach | Existing `D` and `X` | Close only the local attach client |
| Refresh | Existing `G` | Refresh local presentation without remote discovery |
| Select | Existing `RET`, `SPC`, and mouse selection | Open connected terminal or explain the disconnected state without connecting |
| Rename and pin | Existing actions | Preserve host-qualified local presentation |
| Reset layout | Existing `R` | Preserve its current key. Use terminal-only layout behavior for remote targets |

Add the two manager actions to the existing transient menu. Do not introduce another sidebar or replace current keys.

The terminal Stop command resolves the exact current Session before any directory fallback. A manager Stop action passes its selected Session ID to the shared Stop implementation.

Remote project-open and new-session actions report that remote file access and launch are outside this mode. They must not act on a same-named local directory.

## Display and Selection

A remote row includes `[HOST] PROJECT`, followed by existing Agent, title, order, or custom-name information as applicable. The host remains visible after rename.

A disconnected row explicitly says `disconnected`. It does not show output-idle, working, done, or failed as current Agent status.

Remote first-switch and layout-reset paths use the existing terminal display helper. They leave unrelated local windows available and do not open remote project status buffers.

Saved layouts may restore local window choices, but must bind the remote terminal window to the current attached buffer. Stale terminal buffer names must not count as a live target.

## Remote Command Interface

### Shared SSH Options

Use these options for package-owned remote requests:

```text
-o BatchMode=yes
-o StrictHostKeyChecking=yes
-o ConnectTimeout=10
-o ConnectionAttempts=1
-o RemoteCommand=none
```

Do not change SSH configuration files, accept new host keys, add forwarding, or enable automatic reconnect. Missing authentication or host trust produces an actionable failure.

A control request has a thirty-second total deadline. Its timeout cancels only the owned SSH process and reports an unconfirmed result. It does not retry remotely.

### Discovery

Use a pipe process with `ssh -T -n`. No capability inspection runs; stock zmx is assumed on every host.

Run detailed `zmx list` for discovery. Reuse the existing detailed-row parser, but validate the remote response before accepting it.

| Result | Contract |
|--------|----------|
| Exit zero with valid detailed rows | Return named candidates and metadata |
| Exit zero with no rows and the known no-sessions diagnostic | Return an empty result |
| Nonzero exit | Report host-specific failure, never an empty result |
| Malformed or unexpected nonempty output | Report an unsupported response |
| A row reports its own error | Skip that candidate and explain the error |

Discovery occurs only within the user's explicit action. Manager restoration and ordinary refresh perform no request.

### Interactive Attach

Run the attach inside the existing terminal backend:

```text
ssh -t [shared options] HOST REMOTE-COMMAND
```

The logical remote command is:

```text
exec env -u ZMX_SESSION -u ZMX_SESSION_PREFIX zmx attach NAME false
```

These examples describe argument structure. Implementation must quote each argument for the remote POSIX shell and separately encode the local terminal command.

Do not append an Agent command, login shell, MCP flags, local editor ports, or fallback command. The `false` guard is the only command word; see [the attach guard contract](zmx-attach-guard.md).

The terminal backend must supply a local PTY. `-t` remains explicit even if SSH configuration already requests a terminal.

### Stop

The confirmation must identify the host and exact zmx name and explain the effect on every attached client.

After confirmation:

1. Revalidate the configured host and exact target name.
2. Issue one asynchronous `zmx kill NAME` request without `--force`.
3. Require successful exit and the exact `killed session NAME` response.
4. Issue one `zmx list --short` verification as part of the same Stop action.
5. Report success only if verification succeeds and the exact target is absent.

A failed or ambiguous result retains the row and never repeats the kill. While verification is pending, an ended attach client may mark that row disconnected.

On verified success, invalidate the captured live Session before releasing its process or buffer. Use a verified-stop cleanup disposition that cannot remember a disconnected item.

Then remove manager rows and layouts and save state before refresh. Late sentinels must ignore missing or changed live owners rather than restore captured metadata.

Reject reattach while Stop owns the target. A stale Stop callback must not remove a later attachment. See [verified Stop ordering](../data-model.md#verified-stop-ordering).

## Internal Seams

These are the planned responsibilities, not a new public extension framework.

| Seam | Planned responsibility |
|------|------------------------|
| `claude-code-ide-zmx--call-remote` | Own one asynchronous control process, deadline, stdout, stderr, and completion callback |
| Shared `claude-code-ide-zmx-wrap-command` and remote command builder | Build guarded existing-session attachment for local and remote reattach through `claude-code-ide-zmx--attach-args` |
| Existing `claude-code-ide--create-session` orchestration | Accept remote host and reusable Session ID, bypass local integrations, and reuse terminal setup |
| Existing `claude-code-ide--attach-zmx-entry` | Route local or host-bearing entries without replaying remote command metadata |
| Existing `claude-code-ide--cleanup-on-exit` | Check expected process ownership and distinguish ordinary disconnect from verified-stop teardown |
| Manager disconnected-item helper | Preserve the row, presentation, and reconnect information before live-record cleanup |
| Existing manager refresh and switch functions | Merge remembered targets and separate selection from explicit reattach |

The control runner returns a process handle. Its callback receives an explicit outcome containing host, operation, exit status, stdout, stderr, and cancellation or timeout information.

Callbacks run once. They must not signal asynchronous errors into unrelated editor commands. Report errors through the requesting UI and preserve its target context.

Use the request process itself as the ownership token. A stable request name derived from the Session ID prevents duplicate pending attach operations. Do not add another persistent registry.

## Safety and Failure Boundaries

- Reject names with zmx option, current-session, path, or prefix-matcher meaning before any remote action.
- Keep the exact destination and session name through confirmation, dispatch, and completion handling.
- A dead callback or old terminal kill hook cannot clean up a later connection with the same Session ID.
- Return nil for remote local-PID queries and reject remote targets from local MCP state association.
- Keep remote OSC titles local. Automatic title mirroring must not contact either local or remote zmx for a remote target.
- No attach command ever omits the exit guard, so a vanished target never leaves a shell or Agent behind.
