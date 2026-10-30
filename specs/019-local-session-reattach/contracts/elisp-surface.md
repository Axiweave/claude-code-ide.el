# Elisp Surface: Local Session Reattach

## User-facing

| Symbol | Kind | Change |
|---|---|---|
| `claude-code-ide-manager-auto-reattach` | defcustom, boolean, default t | Renamed from the uncommitted `claude-code-ide-manager-auto-reattach-remote`. No alias. It governs selection of any disconnected row, local or remote. |
| `c` → `claude-code-ide-manager-reattach-at-point` | command | Accepts local rows. Errors only for a row without a zmx name. |
| `a` → `claude-code-ide-attach`, `A` → `claude-code-ide-attach-select`, `claude-code-ide-attach-all` | commands | Unchanged interface. An adopted local zmx session with a remembered row reuses that Session ID. |
| `D`/`X` → `claude-code-ide-manager-detach-at-point` | command | Accepts a disconnected local row. Always removes the row. Never stops the Agent. |
| `K` → `claude-code-ide-manager-stop-at-point`, `claude-code-ide-stop` | commands | Accept a disconnected local row. A successful kill removes the row. A failed kill keeps it. |

## Messages

| Case | Text |
|---|---|
| Selection with auto-reattach off | `Session is disconnected. Press c to reattach` (the remote form keeps `on HOST`) |
| Reattach when the zmx session is gone | `zmx session NAME no longer exists. Removed its row` |
| Reattach when zmx is missing | the existing `claude-code-ide-zmx--ensure` error |
| Reattach when the directory is missing | the existing `Session directory is not accessible: DIR` |

## Internal (renamed, all callers migrated)

| Old | New | Change |
|---|---|---|
| `claude-code-ide--reattach-remote-target` | `claude-code-ide--reattach-target` | host optional |
| `claude-code-ide--reattach-remote-session` | `claude-code-ide--reattach-session` | host optional |
| `claude-code-ide--verify-remembered-remote-target` | `claude-code-ide--verify-remembered-target` | adds a synchronous local branch |
| `claude-code-ide-manager--remember-remote-session` | `claude-code-ide-manager--remember-session` | keys on `zmx-name`, not `host` |

## Internal (signature or behavior change)

- `claude-code-ide--create-session`: passes `reusable-session-id` to the local path.
- `claude-code-ide--create-local-session (working-dir continue resume &optional zmx-attach-name reusable-session-id)`: reuses the Session ID, the order, and the creation time from the remembered item.
- `claude-code-ide--live-session-for-target (host zmx-name)`: host nil matches only local Sessions.
- `claude-code-ide--next-session-order`: also takes the maximum order of remembered items for the same project key.
- `claude-code-ide-manager-session-ended`: retains a row when the item has a zmx name and FORGET is nil.
- `claude-code-ide-manager--build-items`: merges remembered items that have a zmx name, and runs the startup cleanup once (R6).

## Unchanged

- The remote control path, SSH deadlines, and the asynchronous remote verification.
- The persisted state format and its version.
- The pickers' candidate filter (`claude-code-ide--zmx-adoptable-sessions`).
