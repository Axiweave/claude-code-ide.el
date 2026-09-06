# Implementation Plan: Attach Remote Agents

**Branch**: `main` | **Date**: 2026-09-05 | **Spec**: [spec.md](spec.md)

**Input**: `specs/003-attach-remote-agents/spec.md`

**Status**: Implemented on stock zmx. The repository gate and the live `ramhorn` lifecycle walkthrough pass.

The setup script reports `003-attach-remote-agents` as its feature identifier. The actual Git branch remains `main`.

## Summary

Extend existing zmx attachment to configured personal SSH hosts. Reuse shared terminal interaction and output-idle tracking. Keep remote Sessions beside local Sessions in the existing manager.

Preserve disconnected remote targets in manager items rather than the live Session registry. Reattach recreates only the local client under the same Session ID. Remote paths remain metadata and never trigger local project operations.

Remote creation of a persistent session must remain impossible. The user rejected a patched zmx on 2026-09-05 because zmx runs on many hosts. Attachment uses stock `zmx attach NAME false`: an existing target is adopted, and a vanished target yields one short-lived session that runs `false` and exits. See [the attach guard contract](contracts/zmx-attach-guard.md).

**Execution gate**: None external. Stock zmx 0.7.1 and 0.8.0 are verified.

## Technical Context

**Language/Version**: Emacs Lisp, Emacs 28.1 or later.

**Primary Dependencies**: Existing `persist` integration, the system OpenSSH client, a supported terminal backend, and stock zmx on each remote host. No new Emacs package dependency.

**Storage**: Existing manager persistence, upgraded to state version 3. History remains local to each Emacs. Remote zmx continues to own Agent processes.

**Testing**: Existing ERT tests in `claude-code-ide-tests.el`, byte compilation through `scripts/compile-and-test.sh`, upstream zmx regression checks, and disposable-host terminal validation.

**Target Platform**: Local Emacs on macOS or GNU/Linux. Personal SSH destinations with a POSIX-compatible command shell, a usable zmx installation, and existing Agents.

**Project Type**: Emacs package with interactive user commands and external terminal-client integration.

**Performance Goals**: Discovery through usable attachment within 60 seconds under the specification's prerequisites. All five primary workflows complete through editor controls after setup.

**Constraints**: Explicit `ssh -t`, no remote launch, no automatic reconnect, no remote editor endpoints, no implicit host scans, and no network requests during restoration.

**Control Request Limits**: Asynchronous pipe processes, a ten-second SSH connection timeout, and a thirty-second total deadline. One attempt per explicit action, with no automatic retry.

**Scale/Scope**: One user with several personal machines. Acceptance covers one local and two remote hosts with colliding project and session names.

**Inspected Environment**: Local zmx reports `0.7.1`, `ramhorn` reports `0.8.0`, OpenSSH reports `9.9p2`. Both zmx versions were verified against the attach guard.

**Research Closure**: [research.md](research.md) resolves command semantics, process ownership, persistence, local integration exclusion, and remote project handling. No design clarification remains open.

## Constitution Check

Initial review passed before design consolidation. The post-design review also passes. No external prerequisite exists; stock zmx is the only dependency.

| Principle | Initial review | Post-design evidence |
|-----------|----------------|----------------------|
| I. Shared session core | Reuse the zmx and shared terminal modules | One host-bearing attach route uses existing terminal creation, setup, input, idle tracking, and manager functions |
| I. User-owned Agent configuration | Do not add an Agent list or launcher policy | Existing Agent identification remains authoritative. Remote metadata never becomes an Agent launch command |
| II. Batch-verifiable quality | Preserve the existing ERT and compile gate | Regression plan covers lifecycle races, host collisions, discovery failures, and unintended local integration |
| III. Optional dependencies | Validate prerequisites at the remote feature entry point | Local package load and workflows do not require SSH or a remote host |
| IV. Terminal-backend neutrality | Use the common terminal factory | Remote attachment targets Ghostel only; vterm and Eat are scheduled for deprecation and must report the limitation explicitly |
| V. Simplicity and compatibility | Keep Emacs 28.1 and existing local behavior | Reuse existing records and persistence. Add no transport framework, history service, or second connection-state registry |
| Workflow and domain language | Keep the current branch and domain glossary | `main` remains unchanged. The glossary includes Configured host. No commits or runtime edits form part of planning |

### Gate Conditions for Implementation

- Use stock zmx only. Never send an option the installed zmx may not understand.
- Keep the no-creation requirement intact on missing targets and discovery races.
- Update every lifecycle path that can erase a disconnected item or misroute a remote target.
- Preserve local Agent behavior, optional dependency loading, and backend-specific dispatch through existing shared seams.
- Pass the complete repository verification script and the live acceptance guide before feature delivery.

No constitution exception requires approval. The plan adds no new runtime package dependency and needs no zmx change.

## Project Structure

### Documentation (this feature)

```text
specs/003-attach-remote-agents/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── remote-sessions.md
│   └── zmx-attach-guard.md
└── checklists/
    └── requirements.md
```

`tasks.md` belongs to the later `/speckit.tasks` phase. This command does not create it.

### Source Code (repository root)

```text
claude-code-ide-zmx.el          # Remote control requests, quoting, attach guard, attach command
claude-code-ide.el              # Host-bearing Sessions, shared creation, cleanup, exact target actions
claude-code-ide-manager.el      # Remembered remote items, state migration, refresh, selection, display
claude-code-ide-transient.el    # Existing menu entries and explicit reattach/Stop actions
claude-code-ide-session.el      # Reuse existing terminal setup and interaction
claude-code-ide-session-idle.el # Reuse existing output-idle behavior
claude-code-ide-tests.el        # Existing ERT suite with focused behavioral regressions
README.org                     # Remote configuration and command documentation
CONTEXT.md                     # Canonical domain terms
```

No external source is part of this feature.

**Structure Decision**: Extend existing modules. Do not add a parallel remote terminal implementation or a new session manager. Shared input and idle modules need no new remote algorithm.

## Phase 0: Research Decisions

| Question | Decision | Evidence |
|----------|----------|----------|
| Can ordinary attach guarantee no creation? | No. Use stock attach with the `false` exit guard, accepted by the user | Research R1 |
| How should remote requests avoid editor blocking? | Asynchronous pipe control requests and an existing terminal-backed attach client | Research R2 |
| How should names cross SSH safely? | Direct local argv, per-argument remote shell quoting, and zmx-specific name validation | Research R3 |
| What proves Stop succeeded? | Exact success response plus one explicit absence verification | Research R4 |
| Where should disconnected targets live? | Existing persisted manager items, outside the live Session registry | Research R5 |
| How should remote directories behave? | Host-qualified metadata without TRAMP or local filesystem inspection | Research R6 |
| Where should remote integration diverge? | Before Agent builders and MCP startup, while retaining shared terminal creation | Research R7 |
| How should remote activity appear? | Existing output-idle behavior while the local attach client is live | Research R8 |

Research records each decision, rationale, alternatives, and primary sources. Proposed zmx behavior is clearly separate from verified current behavior.

## Phase 1: Design

### 1. Stock zmx attach guard

Implement [the attach guard contract](contracts/zmx-attach-guard.md). `claude-code-ide-zmx--attach-args` builds `attach NAME false` for both the shared local wrapper and the remote SSH command.

Preserve ordinary local creation when a creation command is present. Do not leave plain `attach NAME` anywhere, because a missing target would start a persistent shell session.

No capability probe exists. Do not gate on zmx version or help output.

### 2. Remote control and terminal command seam

Add `claude-code-ide-remote-hosts` as an empty-by-default destination list. Extend existing attachment commands with optional host selection through `C-u`.

Keep remote process handling inside `claude-code-ide-zmx.el`. One private control runner owns the process, deadline, stdout, stderr, and completion callback. It completes once and never blocks the editor event loop.

Use `-T -n` for control requests and explicit `-t` for interactive attachment. Validate configured-host membership at dispatch time.

Unset `ZMX_SESSION` and `ZMX_SESSION_PREFIX` in remote zmx commands. Keep the remote socket namespace environment unchanged. Do not forward a local absolute zmx executable path.

Parse detailed discovery rows, including the zmx 0.8 `cwd=file://HOST/PATH` shape, and distinguish malformed output, empty results, and transport failure.

### 3. Shared Session creation and integration exclusion

Extend `claude-code-ide--create-session` with remote host and reusable Session ID inputs. A remote host is valid only with an existing zmx target and without continue or resume.

For remote attachment, call `claude-code-ide--create-terminal-with-command` directly with the SSH command and a valid local working directory. Skip these local-only operations:

- Agent executable checks and Agent command builders.
- Claude MCP startup and tools-session registration.
- omp SSE startup and local editor endpoint injection.
- `with-editor` launcher configuration.
- Local zmx wrapping of an already constructed SSH command.

Keep the common Session registration, terminal setup, resize handling, and cleanup orchestration. Set the remote host marker before hooks can inspect the new terminal.

Update `claude-code-ide-session-agent-pid` to return nil for remote Agents. Update both zmx-name and buffer-name association in `--session-buffer-for-agent` to reject remote Sessions.

Keep Ghostel title changes as local presentation for remote targets. Do not invoke `claude-code-ide-zmx-set-title` for them.

### 4. Remembered identity and disconnected lifecycle

Use the [data model](data-model.md). Add `host` to Session and `host`, `zmx-name`, and `cli-type` to manager items. Reuse current Session IDs and presentation fields.

Materialize a remembered item when the user selects a remote target. On disconnect, preserve that item before removing the live Session record.

Extend exit cleanup with expected process ownership. Both process sentinels and buffer kill hooks must ignore stale callbacks after a later reattach.

Do not add a global generation table or serialize process objects. A current process handle supplies the ownership token.

### 5. Manager refresh, persistence, and selection

These changes form one lifecycle change and must not ship separately:

| Existing symbol or area | Required change |
|-------------------------|-----------------|
| `claude-code-ide-manager--serialize-item` and `--deserialize-item` | Store remote target metadata and reset restored remote `live-p` |
| `claude-code-ide-manager--load-state` and `--restore-state` | Accept state version 3 while retaining local version 1 and 2 migrations |
| `claude-code-ide-manager-refresh-items` | Merge remembered remote items with current live items before replacing scope contents |
| `claude-code-ide-manager-session-ended` | Preserve remote item and layout choices on disconnect rather than unconditionally delete |
| `claude-code-ide-manager--ensure-live-target` and `switch-to-session` | Distinguish disconnected selection from missing local sessions without implicit reattach |
| New `claude-code-ide-manager-reattach-at-point` | Recreate only the local attach client under the same Session ID |
| Existing active and selected scope state | Clear dead active-terminal references without losing selected-row identity |

Save changed in-memory state before a refresh path reloads persistence. Live records override saved disconnected snapshots. With persistence disabled, current in-memory disconnected items still survive refresh.

Expose reattach on `c` and confirmed Stop on `K`. Keep the existing `R` layout-reset key and existing attach, detach, rename, and pin actions.

### 6. Project and presentation isolation

Keep remote absolute directories as metadata. Add host-aware project comparison to ordering and target lookup while preserving local directory-key behavior.

Audit `--sessions-for-directory`, related-directory matching, and `--zmx-live-names` so local callers exclude remote Sessions unless they supply a host. Exact current-buffer identity takes precedence for terminal actions.

Remote items appear in the global manager. Local Git scopes must not include them through matching directory strings.

Guard manager Git-root, branch, status-buffer, active-file, and Treemacs helpers before they perform filesystem work. Remote first-switch and reset paths display the terminal without opening project status.

Use host-qualified display names and help text. Preserve host labels when custom names change. Restore valid local layout choices while rebinding the terminal window to the current buffer.

Reject remote project-open and start-session actions explicitly. This prevents accidental work in a local directory whose name matches remote metadata.

### 7. Exact Stop and failure behavior

Reuse one Stop implementation for exact terminal and manager targets. Confirmation must name both host and zmx session before any remote kill request.

Issue one kill without force or prefix matching. Require the exact success response, then perform one short-list absence check as part of that action.

Only verified success removes the remembered target. Failure, timeout, or a lost reply retains it with an unconfirmed result.

Verified completion must first invalidate the captured live Session, then release its client with a disposition that cannot preserve disconnected metadata. Remove rows and layouts afterward and save before refresh.

Until verification completes, ordinary client death may preserve a disconnected row. After verified cleanup, missing-owner callbacks must do nothing. Reject reattach while Stop owns the target.

Follow the [verified Stop ordering](data-model.md#verified-stop-ordering) for both sentinel-first and control-callback-first execution.

### 8. Output-idle behavior

Keep the existing output observer and idle interval. Ensure remote Sessions have no package-managed structured Agent state.

On disconnect, cancel the old buffer's idle timer and clear activity before refreshing the row. Never treat terminal silence as proof of Agent completion or immediate network failure.

## Verification Strategy

### Behavioral regressions

Use the existing ERT suite and mock only external process or terminal seams where needed. Assert user-visible state and prevented side effects, not field forwarding or source text.

Required uncertain cases include:

- Disconnect, refresh, restart, and explicit reattach preserve one target and its presentation.
- Late sentinels and old buffer hooks cannot remove a newer attachment.
- Verified Stop removes the target under either callback order, and late sentinels or refresh cannot restore it.
- Host/name collisions cannot redirect selection, Stop, project lookup, or local MCP state.
- A remote target never starts local MCP, probes a local Agent PID, or opens a local directory as its project.
- The attach guard is present in every existing-session attach command, local and remote.
- Stop cancellation, misleading exit-zero output, timeout, and lost verification never claim success or repeat a kill.
- Persistence-disabled rows survive the current Emacs lifetime but do not restore later.
- Existing local attachment, cleanup, state migration, and terminal behavior remain intact.

Run `scripts/compile-and-test.sh` once after the integrated implementation.

### End-to-end proof

Follow [quickstart.md](quickstart.md) using disposable Agents. Exercise one local and two remote hosts with the Ghostel backend.

Record all five workflow results and the 60-second discovery-to-attachment measurement. Verify zero remote requests during restoration and ordinary manager refresh.

The current planning command validates documentation and existing repository checks only. It does not claim that these future remote workflows already pass.

## Implementation Order

1. Implement the shared attach guard.
2. Implement the remote control seam.
3. Implement shared remote Session creation with local integration exclusion.
4. Integrate remembered-item lifecycle, migration, refresh, selection, and reattach together.
5. Add exact Stop routing, host labels, and existing-menu actions.
6. Run behavioral regressions and the live acceptance guide.
7. Update `README.org` with configuration, stock zmx behavior, and deferred scope.

The later tasks phase can split independent work after these interfaces are fixed. It must keep the shared lifecycle changes under one integration owner.

## Complexity Tracking

No constitution violations or new runtime package dependencies require justification.

No external prerequisite exists. The `attach NAME false` guard on stock zmx accepts one short-lived exited session in the race window; the user chose this over a patched zmx on every host.

No TRAMP integration, remote Agent launcher, transport framework, automatic reconnect loop, history synchronization, or text-transfer feature belongs in this plan.
