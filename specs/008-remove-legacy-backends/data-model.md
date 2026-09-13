# Data Model: Ghostel-Only Terminal Support

**Spec**: [spec.md](spec.md)
**Research**: [research.md](research.md)

This removal changes runtime implementation, not persistent data schemas.
The following entities describe existing data and required invariants.
They do not introduce new structs, lifecycle flags, or storage layers.

## Agent Session

**Source**: [core](../../claude-code-ide.el), `claude-code-ide-session` and `claude-code-ide--sessions`.

| Existing fields | Meaning and invariant |
| --- | --- |
| `id` | Generated Session identity and exact registry key. Directory equality does not establish identity. |
| `directory` | Project directory metadata on the Session host. Remote metadata is not a TRAMP name or a local path to validate. |
| `host` | Existing local/remote host identity. A failed remote operation cannot replace it with the local host. |
| `buffer`, `process` | Existing attachment buffer and lifecycle handle. Resolve the current live buffer before terminal actions. Preserve supported buffer/process handle representation. |
| `cli-type`, `cli-session-id` | Agent type and Agent conversation identity. Terminal removal does not change either. |
| `zmx-name`, `pid` | Existing persistent-session and process identity. Attachment does not authorize replacement or Stop. |
| `order`, `created-at`, `last-accessed-at` | Existing ordering and access metadata. |
| `custom-name`, `title`, `group-metadata` | Existing presentation and grouping metadata. |

There is no terminal-backend field in the Session struct.
Do not add a constant Ghostel field or migrate Session storage.
An owned Agent attachment uses Ghostel, but Ghostel mode alone does not prove Agent ownership.

### Validation rules

- Registration must not report a successful new Session without its actual live terminal process.
- Ownership-sensitive actions resolve the exact live Session buffer and process.
- Setup retains its existing timing and customizable Session predicates.
- Setup requires Ghostel mode without requiring a new pre-registration record.
- Multiple Sessions may share the same directory and host.
- A stale callback cannot operate on a replacement attachment or another Session.

## Terminal attachment

**Sources**: [core](../../claude-code-ide.el), shared terminal factory and process-to-buffer lookup.
[Session module](../../claude-code-ide-session.el), setup and input operations.

This is an existing buffer/process relationship, not a new stored entity.
The Agent factory returns `(buffer . process)` after `ghostel-exec` creates the process.
The runtime retains existing CLI buffer-local state and Session setup state.
It removes the terminal-backend cache and retired renderer state.

Ghostel library/native availability is a point-of-use condition, not a persisted capability flag.
A failed support check leaves package loading, non-terminal operations, and existing Sessions available.

## Companion shell

**Sources**: [Session module](../../claude-code-ide-session.el), companion creation and liveness.
[manager](../../claude-code-ide-manager.el), `claude-code-ide-manager--companion-shells`.

| Existing data | Invariant |
| --- | --- |
| Owner Session ID | Exact map key. Do not key by directory, buffer name, or host alone. |
| Buffer | Ordinary Ghostel shell, distinct from the Agent attachment. |
| Buffer-local `ghostel--process` | Must be an actual live process for reuse. A buffer name or major mode does not prove liveness. |
| Directory and host context | Must belong to the requested companion context. No silent fallback directory or host. |

A live companion survives layout switching, restoration, and resets that reuse it.
An exited companion is not a live reusable shell.
Existing explicit replacement behavior controls creation after exit.
A released or superseded live shell can remain an ordinary terminal without Agent ownership.

## Saved layout

**Source**: [manager](../../claude-code-ide-manager.el), preset definitions and `claude-code-ide-manager--persistable-layout`.

The six presets remain `magit-left`, `magit-right`, `shell-left`, `shell-right`, `dired-left`, and `dired-right`.
Existing window state and selected-window restoration retain precedence over the current default preset.
Changing the default does not rewrite saved layouts or restart a shell.

Runtime-only `:project-view-buffer`, `:project-view-name`, and `:shell-buffer` stay outside persisted layout data.
Existing missing-buffer recovery handles layouts restored after an editor restart.
Generic Agent popup side/width and manager sidebar state remain separate from preset companion placement.

## Pending companion request

**Source**: [manager](../../claude-code-ide-manager.el), asynchronous companion preparation and publication guards.

Preserve the existing captured Session, attachment, host, directory, frame, and request epoch.
Preserve the captured preset, companion kind/side, provider, and permission to create where the current request stores them.
Do not add a second request object for this removal.

Before publishing a prepared companion, validate the captured context against the current request.
A stale request cannot replace the current companion or change the current layout.
An optional remote project-view failure does not revoke an otherwise valid terminal attachment.

## Lifecycle transitions

These names describe existing behavior. They are not proposed enum values.

| Operation | Required transition | Failure or boundary behavior |
| --- | --- | --- |
| New local launch | Requested directory and command → live Ghostel attachment → registered Session | Missing support or failed startup creates no successful Session and preserves existing Sessions. |
| Local persistent adoption | Selected persistent identity → Ghostel attachment to that identity | Do not start a replacement Agent. |
| Approved remote attach | Approved host and selected identity → remote Ghostel attachment | Preserve admission and capability checks. Do not approve a host or substitute a local shell. |
| Detach | Managed attachment → detached persistent Agent under existing rules | Detach does not become Stop. |
| Attachment disconnect | Live attachment → disconnected attachment state | A disconnected attachment does not prove the remote Agent died. |
| Reconnect | Existing persistent identity → new attachment to that identity | Preserve ownership checks and host identity. |
| Explicit Stop | Confirmed owned target → existing Stop cleanup | Do not stop an unrelated Agent or companion. |
| Layout switch or restore | Existing layout → restored arrangement and selected window | Reuse a live companion and Agent process. |
| Companion exit | Live companion → non-live companion | Do not reuse a dead process or silently report it as live. |
| Superseded companion request | Pending result → rejected publication | Preserve a live created shell as an ordinary terminal. Clean only a dead partial buffer owned by the request. |
| Editor restart | Saved layout → existing missing-buffer recovery | Do not convert retired terminal buffers or revive removed selection policy. |

## Removed state

This section is an explicit removal record under FR-013.

Remove global and per-Agent terminal preferences, the buffer-local backend cache, and retired rendering queues/timers.
Remove EAT/vterm-specific cursor, copy-mode, hook, advice, and cleanup state.
Keep Ghostel copy/input state, Session activity state, resize-observer lifetime, and the generic reflow option.
Legacy user assignments may create inert Lisp variables, but the package must neither declare nor read them as preferences.

## Migration boundary

No storage migration or hot buffer conversion is required.
The supported upgrade may require an Emacs restart.
If code reload leaves an old terminal buffer alive, preserve that buffer and its process without adopting or reconfiguring it.
Package terminal operations must reject its non-Ghostel mode and explain the restart requirement.
New Sessions must not inherit its cached terminal preference.
Package loading must not destroy existing terminal buffers, modify external packages, or rewrite Git history.
The related Spacemacs consumer migrates with the removed private interfaces.
