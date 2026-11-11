# Contract: follow-up packet `pi:send`

## Bytes

```text
ESC _ pi:send;<mode>.<payload> ESC \
```

- `<mode>` is `queue`, `guide`, `stop`, or `notice`.
- `<payload>` is the follow-up text in UTF-8, encoded as base64url with no padding. The composer regex refuses `/`, so standard base64 does not work.
- The text is at most 64 KiB before encoding. The text must not be empty.
- The packet can arrive in pieces. Without the kitty keyboard protocol, the stdin buffer holds a head that starts with `ESC _ p`, `ESC _ pi`, or `ESC _ pi:` as a string sequence, so a pause in the packet does not make it typed text. A pause right after `ESC _` is the exception: those two bytes are also Alt+_, the same as for every other APC reply.

## Sending

The Intake sends one packet per follow-up with `zmx send NAME <packet>`, locally or through `ssh HOST -- zmx send NAME '<packet>'`. The spike in research proves that both paths carry the bytes unchanged. The Intake does not add a CR.

## omp handling

The composer regex at `tui/src/prompt/composer.ts:365` adds `send` to its kinds. A new `onSend(mode, text)` callback sits beside `onAction`, and `interactive-mode.ts` connects it to a handler:

| Mode | Call | Effect while a turn runs | Effect when idle |
|---|---|---|---|
| `queue` | `session.prompt(text, {streamingBehavior: "followUp"})` | Waits until the turn ends. | Starts a turn. |
| `guide` | `session.prompt(text, {streamingBehavior: "steer"})` | Joins the running turn. | Starts a turn. |
| `stop` | `await session.abort({reason: USER_INTERRUPT_LABEL}); await session.waitForIdle(); session.prompt(text)` | Stops the turn, then starts a new one. | Starts a turn. |
| `notice` | `await session.waitForIdle(); session.sendCustomMessage({customType: "intake-notice", content: text, display: true, attribution: "agent"})` | Waits until the turn ends, then adds the card. | Adds the card and starts no turn. |

- The handler does not need the editor, so an open dialog does not block it. The draft in the editor does not change.
- Each handler call passes `runCommands: false`, the same as the start prompt. Thus a follow-up never runs an extension command or a custom command, and its text reaches the agent as written. A file command, for example `/speckit.specify`, expands the same as in the start prompt (FR-030).
- omp runs the handler calls of one Session in one promise chain. A packet that arrives while a `stop` packet waits on `abort` or `waitForIdle` runs after it, so the arrival order stays the same (FR-031).
- Before its abort, a `stop` packet takes the earlier `queue` and `guide` follow-ups that still wait in omp's queues out of them. Otherwise the abort can start a turn for a queued `guide` before an earlier follow-up. After the abort, the `stop` packet sends them again, in arrival order, and waits for each turn to end. Then it sends the stop text (FR-031).
- A packet with a bad mode, a bad payload, or empty text does nothing and shows one status line.
- A valid packet that arrives before `interactive-mode.ts` sets `onSend` waits in the composer. When `onSend` is set, the composer gives it each waiting packet once, in arrival order (FR-031).
- In a Session with a start prompt, the handler waits until omp admits the start prompt. Thus the start prompt is the first turn, and a follow-up turn publishes `cci-state` (FR-031).
- `session.prompt` can drop a follow-up before its turn starts, for example when the next packet is `stop`. A drop with no reason (an abort or a session change) is not final. The handler waits until the session is idle and sends the same text again, up to three tries in total. A `stop` packet waits for these tries before its own text, so each follow-up runs once, in arrival order (FR-031). After the last try, or for a drop with a reason (for example the cost cap), the handler shows one error line, `Follow-up dropped before it started.` or `Follow-up dropped before it started: <reason>`. The text does not go into the editor, so the draft does not change.
- The Session shows a follow-up like a typed message, so the user sees it on attach.
