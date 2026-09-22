# Contract: Ghostel to Package Interface

The Elisp interface that Ghostel provides and `claude-code-ide.el` consumes. The
package must remain correct when Ghostel is absent, older, or built without native
paste-event support (constitution Principle III).

## Provider obligations (Ghostel)

### C1. Capability predicate

```elisp
(ghostel-paste-events-supported-p &optional buffer)
```

- Returns non-nil when the loaded native module supports paste events (mode 5522) and
  can answer a granted clipboard read with MIME data for the terminal of `buffer`.
- Returns nil when the module is absent, older than the required version, or built
  without native clipboard support.
- Never signals. It is safe to call in a Session buffer at any time.

### C2. Terminal paste command

```elisp
(ghostel-paste-clipboard &optional buffer)
```

- Performs one terminal paste for the terminal of `buffer`, using the local GUI
  clipboard. Text comes from the standard clipboard. Image data is offered as the MIME
  types the clipboard advertises.
- When the application enabled paste events, the terminal sends a paste event and
  answers the granted read from the local clipboard. Otherwise the call behaves as the
  existing paste commands do.
- Signals an actionable `user-error` when the module cannot perform the paste. The
  message names the missing capability. The function never falls back to sending
  clipboard text as keystrokes.
- Returns non-nil on a completed paste attempt.

### C3. Unchanged behavior

`ghostel-yank`, `ghostel-paste`, `ghostel-paste-string`, `ghostel-send-string`, the
OSC 52 handlers, and their keybindings keep their current behavior and their current
code paths. The new entry points are additive.

## Consumer obligations (claude-code-ide.el)

### C4. Capability load

- Reach Ghostel through the existing optional-dependency pattern
  (`(require 'ghostel nil t)`), never a hard require.
- Ask C1 before choosing the terminal paste route. Do not compare version numbers.
- When C1 is unavailable because Ghostel is absent or older, explain and send nothing.

### C5. Route decision

`claude-code-ide-session-paste-clipboard` applies the rules in
[data-model.md](../data-model.md), in order:

1. Local Session: unchanged (send `C-v` for images, `ghostel-yank` for text).
2. Remote Session, CLI without a client-side implementation: unchanged.
3. Remote Session, CLI with a client-side implementation, capability present: call C2.
4. Remote Session, CLI with a client-side implementation, capability absent: explain
   and send nothing.

The command must not send `C-v` on the terminal-mediated route, because the Agent
cannot read the local clipboard from its host.

### C6. Explanations

Each refusal is one message in the Session buffer, naming the condition and the single
action that restores delivery:

| Condition | Message content |
|---|---|
| Terminal lacks native support | The installed Ghostel build cannot deliver clipboard images; the supported alternative is a local Session or a Ghostel build with native paste support. |
| Local terminal client is not the input leader | Another client owns the input for this Session; the action is to type in this Session first (or detach the other client), then paste again. |
| CLI has no client-side implementation | This Agent cannot accept a terminal clipboard image; an Agent that supports OSC 5522 paste events can. |

Rules: no message is produced on a successful route, and no message replaces the
gesture with a different operation.

## Compatibility matrix

| Ghostel | CLI client side | Route | Sends |
|---|---|---|---|
| Any | none | unchanged | `C-v`, or text paste |
| Older, no predicate | `omp` | explained refusal | nothing |
| With native support | `omp` | terminal paste | paste event, then clipboard data |
| With native support, non-leading client | `omp` | explained refusal | nothing |

## Verification obligations

- Ghostel proves C1, C2, and C3 with its own Elisp and Zig tests
  (`make test`, `make test-zig`).
- The package proves C4, C5, and C6 with ERT cases that mock C1 and C2 at their
  interfaces, and by keeping the existing paste tests passing unchanged.
- The live walkthrough in [quickstart.md](../quickstart.md) proves the two together on
  a real remote Session.
