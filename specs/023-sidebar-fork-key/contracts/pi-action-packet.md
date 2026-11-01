# Contract: `pi:action` input packet

## Bytes

```text
ESC _ pi:action;<name> ESC \
```

- `<name>` matches `[^\s/\x00-\x1f\x7f-\x9f]+`, the same value rule as `pi:prompt` and `pi:keyword`.
- The only defined name is `fork-spawn`.
- Emacs sends the packet with one terminal write: `(claude-code-ide-session-send-omp-packet "action" "fork-spawn")` gives `"\e_pi:action;fork-spawn\e\\"`. No Return follows.

## omp behavior

| Condition | Result |
|---|---|
| Any `pi:action` packet | The Composer listener consumes it. No byte reaches the editor, and the draft and cursor stay the same. |
| No `onAction` handler yet (startup, before InteractiveMode adopts the Composer) | Dropped. |
| Unknown `<name>` | Dropped. |
| `fork-spawn`, a dialog owns input | Warning "Fork request ignored: close the open dialog first." Nothing is created. |
| `fork-spawn`, otherwise | `handleForkSpawnCommand(false)`: the same refusals and the same B as `/fork spawn`, with no busy-turn question. |

An open `/spawn` window is not a dialog for this check.

## Emacs behavior (`S` in the manager sidebar)

| Row at point | Result |
|---|---|
| None | `user-error` "No manager session at point". Nothing is sent. |
| No live buffer, or its terminal process is dead | `user-error` "Session is disconnected. Press c to reconnect first". Nothing is sent. |
| Live, not omp | `user-error` "Only Oh My Pi sessions can fork". Nothing is sent. |
| Live omp, local or remote | Sends the packet in the row's buffer and shows "Fork request sent to <name>". |

Emacs attaches B through the spec 021 spawn announcement. It does not wait for omp's result.
