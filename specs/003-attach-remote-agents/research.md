# Research: Attach Remote Agents

**Date**: 2026-09-05
**Specification**: [spec.md](spec.md)
**Result**: Design questions resolved. Implementation uses stock zmx with an exit guard. No external prerequisite remains.

Two independent research reviews covered transport and manager lifecycle. This report records conclusions checked against repository code, installed command output, and upstream sources.

## R1. Attach to existing sessions with stock zmx

**Decision**: Use stock `zmx attach NAME false` for every existing-session attach, local and remote. Emacs never patches, replaces, or version-gates zmx.

**Evidence**: Stock `zmx attach NAME [COMMAND...]` ignores COMMAND when NAME exists and only runs it when creating a session. With `false` as the command, a missing target yields one session that exits at once and a nonzero client exit. Verified on stock 0.7.1 (local) and 0.8.0 (`ramhorn`) on 2026-09-05. See [the attach guard contract](contracts/zmx-attach-guard.md).

**Rationale**: The user rejected a patched zmx because zmx is deployed on many hosts. A discovery check plus ordinary attach still has a race window, but the `false` guard shrinks the race outcome to a short-lived empty session, with no shell, Agent, or replacement process.

**User decision**: On 2026-09-05 the user withdrew the earlier "require attach-only support" decision and chose stock zmx. The race window with the exit guard is accepted.

**Alternatives considered**:

- Add `zmx attach --existing` to zmx: implemented and verified in a private checkout, then rejected by the user because it needs deployment on every host.
- Plain `zmx attach NAME` without a guard: rejected because a missing target starts a persistent shell session.
- Supply the discovered Agent command: rejected because a missing target restarts the Agent.
- Implement the zmx terminal protocol in Emacs: rejected because this duplicates terminal restoration and client behavior.

**Sources**:

- Installed `zmx help`, `zmx version`, and isolated `ZMX_DIR` probes on the local machine and `ramhorn`.
- [Upstream attach parser and client](https://github.com/neurosnap/zmx/blob/5afa7bccb3ce7fd02dc80d075342a4fe3df6feae/src/main.zig#L1513-L1673).
- [Local attach wrapper](../../claude-code-ide-zmx.el), `claude-code-ide-zmx-wrap-command`.

**Task-design refinement**: The shared local wrapper's attach-only branch and the remote SSH command both use `claude-code-ide-zmx--attach-args`. Ordinary local creation with a command remains unchanged. Remote attachment does not need a local zmx installation.

Stock zmx 0.8 also changed detailed `zmx list` rows (`cwd=file://HOST/PATH` replaces `start_dir=`, rows are indented). The shared parser handles both shapes.

## R2. Separate terminal attachment from bounded control requests

**Decision**: Use the existing terminal factory for the long-lived SSH attach client. Use asynchronous pipe processes for discovery and confirmed Stop requests.

Interactive attach explicitly uses `-t`. Control requests use `-T` and close stdin. Both use batch authentication, strict existing host-key verification, and a ten-second connection timeout. Control requests have a thirty-second total deadline. No command retries automatically.

**Rationale**: Terminal attachment needs a PTY. Structured discovery must not mix terminal formatting with its response. An unavailable host must not freeze local editor work, including during Stop.

**Decision**: Use one private remote control runner in `claude-code-ide-zmx.el`. It captures stdout and stderr separately and reports completion once. Keep existing local synchronous behavior unchanged.

**Alternatives considered**:

- Synchronous remote prerequisite checks or Stop: rejected because explicit user intent does not make network blocking safe.
- A transport class or connection pool: rejected because the existing zmx module can own these operations directly.
- An SSH configuration scanner or connection monitor: rejected by the explicit-host and no-background-connection requirements.

**Sources**:

- [OpenSSH command and terminal behavior](https://man.openbsd.org/ssh.1), `-t`, `-T`, `-n`, and command argument handling.
- [OpenSSH configuration](https://man.openbsd.org/ssh_config.5), `BatchMode`, `StrictHostKeyChecking`, `ConnectTimeout`, and `ConnectionAttempts`.
- [Existing local zmx process seam](../../claude-code-ide-zmx.el), `claude-code-ide-zmx--call`.
- [Existing terminal factory](../../claude-code-ide.el), `claude-code-ide--create-terminal-with-command`.

## R3. Treat destinations, session names, and remote output as data

**Decision**: Add one user-owned `claude-code-ide-remote-hosts` list of SSH destination strings. Use the exact configured destination as identity and display label. Remote zmx must be available as `zmx` in that destination's command environment.

Build local process argument lists directly. Quote each remote argument for the POSIX remote shell before joining the remote command. Quote the complete SSH argument list separately when the terminal backend requires a command string.

Unset remote `ZMX_SESSION` and `ZMX_SESSION_PREFIX`. Preserve the remote socket-directory environment. Discovery returns full names, so a second prefix must not change the selected target.

Reject empty or control-character names and values that zmx treats as options, current-session shortcuts, paths, or prefix matchers. Ordinary spaces and shell punctuation in valid session names require correct quoting, not evaluation.

**Rationale**: OpenSSH joins remote command arguments with spaces. Local process argument separation alone does not protect the remote shell. Zmx also assigns special meaning to some otherwise quoted names.

**Alternatives considered**:

- `combine-and-quote-strings` as shell escaping: rejected because it does not provide the required POSIX shell guarantee.
- Forwarding the local absolute zmx program path: rejected because remote installations can differ.
- Per-host transport objects and configurable shell fragments: rejected as unnecessary scope and input risk.

**Sources**:

- [OpenSSH DESCRIPTION](https://man.openbsd.org/ssh.1#DESCRIPTION).
- [Zmx nested sessions and prefixes](https://github.com/neurosnap/zmx/blob/5afa7bccb3ce7fd02dc80d075342a4fe3df6feae/README.md).
- [Zmx command parsing](https://github.com/neurosnap/zmx/blob/5afa7bccb3ce7fd02dc80d075342a4fe3df6feae/src/main.zig#L301-L367).

## R4. Verify Stop beyond the process exit code

**Decision**: Stop requires the existing confirmation behavior, expanded to include host and exact zmx name. Issue one kill request without `--force` or prefix matching. Require a successful exit and the exact target-specific success response. Then issue one short-list verification within the same explicit Stop action.

Report success only when that verification succeeds and the exact target is absent. Otherwise report an unconfirmed stop, retain the row, and do not retry the kill.

**Rationale**: The inspected upstream kill loop can catch a per-session error and still set `killed_any`. Exit zero alone is insufficient. The normal kill function prints `killed session NAME` after the daemon connection closes.

The verification request is not background discovery. It completes the already confirmed Stop action. A lost reply can leave the true remote result unknown.

**Lifecycle ordering**: After verification, invalidate the captured live Session before closing its client or removing its manager item. Verified-stop cleanup must not preserve disconnected metadata.

Before verification, a client sentinel may preserve a disconnected row. After verified cleanup, callbacks without the current live owner do nothing. Test both callback orders.

**Alternatives considered**:

- Treat exit zero as success: rejected by the inspected error path.
- Force kill or repeated kill attempts: rejected because they can hide missing targets or affect a later replacement.
- Delete the row before confirmation: rejected because a failed request must not erase the user's target.

**Sources**:

- [Upstream kill dispatch](https://github.com/neurosnap/zmx/blob/5afa7bccb3ce7fd02dc80d075342a4fe3df6feae/src/main.zig#L301-L367).
- [Upstream kill response](https://github.com/neurosnap/zmx/blob/5afa7bccb3ce7fd02dc80d075342a4fe3df6feae/src/main.zig#L1087-L1134).
- [Existing Stop behavior](../../claude-code-ide.el), `claude-code-ide-stop`.

## R5. Keep disconnected targets in existing manager items

**Decision**: Keep `claude-code-ide--sessions` as the live registry. Extend manager items with `host`, `zmx-name`, and `cli-type`. Reuse the existing `directory`, `session-key`, presentation fields, and `live-p`.

A disconnected remote item remains in manager state without a live Session record. Reattach reconstructs that live record under the same Session ID. No second connection-state boolean or generation registry is required.

Update cleanup, manager refresh, selection, serialization, and restoration together. Refresh merges remembered remote items with live items by Session ID. Live items take precedence. Restoration always treats remote items as disconnected until a current live record proves otherwise.

**Rationale**: Current cleanup removes the live record. `manager-session-ended` removes rows and layouts. Refresh rebuilds only from live records, and switch rejects non-live keys. Saving host and name alone does not fix those paths.

**Race rule**: Exit handlers carry their expected process and buffer. Cleanup must ignore a handler whose process no longer owns that Session ID. Object identity supplies this guard without another counter table.

**Alternatives considered**:

- Retain dead records in the live registry: rejected because local directory selection and cleanup already assume live records.
- Persist a `connected-p` flag: rejected because a saved connection cannot survive an editor restart.
- Delete an unreachable target after failed reattach: rejected by the specification.
- Reattach from ordinary row selection: rejected because selection must not contact the host.

**Sources**:

- [Live registry cleanup](../../claude-code-ide.el), `claude-code-ide--cleanup-on-exit` and `claude-code-ide--cleanup-session-resources`.
- [Manager row lifecycle](../../claude-code-ide-manager.el), `claude-code-ide-manager-refresh-items`, `claude-code-ide-manager-session-ended`, and `claude-code-ide-manager-switch-to-session`.
- [Manager persistence](../../claude-code-ide-manager.el), `claude-code-ide-manager--serialize-item`, `claude-code-ide-manager--deserialize-item`, and `claude-code-ide-manager--load-state`.

## R6. Keep remote project metadata separate from local filesystem behavior

**Decision**: Keep the remote absolute directory as metadata in the existing directory field. Add host-aware project comparison for remote ordering and target selection. Do not construct TRAMP paths.

Remote items appear in the global manager, not local Git repository scopes. Remote selection must skip Git root lookup, branch lookup, Magit, Dired, and Treemacs synchronization. Remote terminal processes use a valid local working directory.

**Rationale**: Current manager display and layout helpers can run Git or open a directory. A remote path can also exist locally and silently identify the wrong checkout.

**Alternatives considered**:

- TRAMP directory identities: rejected because remote file access is deferred and ordinary manager operations must not initiate SSH.
- Use a local temporary directory as project identity: rejected because unrelated remote projects would collide.
- Add a remote Git/worktree manager: rejected as a UI and filesystem feature outside scope.

**Sources**:

- [Directory lookup and ordering](../../claude-code-ide.el), `claude-code-ide--sessions-for-directory` and `claude-code-ide--next-session-order`.
- [Manager filesystem helpers](../../claude-code-ide-manager.el), `claude-code-ide-manager--session-git-root`, `claude-code-ide-manager--session-branch-name`, and `claude-code-ide-manager--scope-sessions`.
- [Manager layouts](../../claude-code-ide-manager.el), `claude-code-ide-manager--build-default-layout` and `claude-code-ide-manager--sync-treemacs-to-session`.

## R7. Bypass local integration before terminal creation

**Decision**: Extend the existing session creation orchestration with an explicit remote target. For that target, skip Agent command builders, local CLI availability checks, MCP startup, editor environment injection, and MCP registration.

Pass the SSH attach command directly to `claude-code-ide--create-terminal-with-command`. Reuse its terminal setup, shared input behavior, registration, and lifecycle hooks. All supported Agent types follow this same route.

Remote Sessions must return no local Agent PID. Local MCP association must exclude remote Sessions, even if zmx names collide. Ghostel titles can update local presentation, but must not trigger remote title writes or local zmx operations.

**Rationale**: Current `--create-session` starts Claude MCP or omp SSE before terminal creation. The Claude terminal builder also formats local editor settings. Merely prepending SSH leaves those side effects intact.

**Alternatives considered**:

- Set MCP port to nil and reuse Agent builders: rejected because the Claude builder expects and injects a port.
- Duplicate a remote terminal implementation for each backend: rejected by the shared-session and backend-neutrality principles.
- Tunnel editor tools: deferred by the approved terminal-only scope.

**Sources**:

- [Session creation](../../claude-code-ide.el), `claude-code-ide--create-session` and `claude-code-ide--create-claude-terminal-session`.
- [Local PID and MCP association](../../claude-code-ide.el), `claude-code-ide-session-agent-pid` and `claude-code-ide--session-buffer-for-agent`.
- [Ghostel title mirroring](../../claude-code-ide.el), `claude-code-ide--record-ghostel-title`.

## R8. Reuse output-idle behavior without claiming Agent completion

**Decision**: Remote Sessions have no package-managed structured Agent state. Use existing terminal-output observation, including both Ghostel output paths and redraw-only filtering. Disable timers and clear activity state when the attach client ends.

**Rationale**: This is the simple remote mode the user approved. Silence cannot prove either completion or disconnection.

**Alternatives considered**: Remote state files, PID polling, completion protocols, and automatic reconnect are outside scope.

**Sources**:

- [Output-idle fallback](../../claude-code-ide-session-idle.el), `claude-code-ide-session-needs-attention-p`.
- [Output observation](../../claude-code-ide-session-idle.el), `claude-code-ide-session-idle--real-activity-p` and `claude-code-ide-session-idle--install-output-observers`.
- [Accepted ownership decision](../../docs/adr/0001-zmx-backed-agent-sessions.md).

## Research Closure

All design questions have decisions and evidence. Stock zmx with the exit guard replaced the earlier external prerequisite on 2026-09-05. Research changed no remote host, live Agent, or SSH configuration.
