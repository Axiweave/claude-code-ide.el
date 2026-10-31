# Contract: Emacs Lisp Surface

## Commands

| Symbol | Kind | Contract |
|---|---|---|
| `claude-code-ide-disconnect (&optional session-id)` | autoloaded interactive command | Disconnects SESSION-ID or, without it, the Session of the current buffer. No project or directory fallback. Result: Session buffer dead, Session unregistered, row kept as a Disconnected session row, Agent and zmx session still running. Guards in [research.md](../research.md) R2 signal `user-error` and change nothing. |
| `claude-code-ide-manager-disconnect-at-point ()` | interactive command | Calls `claude-code-ide-disconnect` with the key of the row at point, then keeps point on that row. |

## Keys and menus

| Place | Key | Command |
|---|---|---|
| `claude-code-ide-manager-mode-map` | `d` | `claude-code-ide-manager-disconnect-at-point` |
| `claude-code-ide-manager-dispatch` ("Sessions" column) | `d` | `claude-code-ide-manager-disconnect-at-point`, label "Disconnect (keep row)" |
| Main `claude-code-ide` menu | none | not added (clarification Q1) |

## Messages

| Case | Text |
|---|---|
| Success, local | `Disconnected zmx session NAME. Press c to reattach` |
| Success, remote | `Disconnected zmx session NAME on HOST. Press c to reattach` |
| No row at point | `No manager session at point` |
| No Session in buffer | `No Session in the current buffer` |
| Already disconnected | `Session is already disconnected. Press c to reattach` |
| Not zmx-backed | `Session is not zmx-backed` |
| Request in flight | `Cannot disconnect NAME on HOST. REASON is already in progress` |
| Kill refused | `Disconnect did not close the Session buffer` |

## Unchanged

`D`, `X` (`claude-code-ide-manager-detach-at-point`), `K`, `c`, `a`, `A`, `claude-code-ide-stop`, `claude-code-ide--cleanup-on-exit`, and `claude-code-ide-manager-session-ended` keep their interfaces and behavior.
