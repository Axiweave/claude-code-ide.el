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
- Returns non-nil when Ghostel admits the paste attempt, not when the transfer or Agent attachment completes.
- The caller must not report attachment success from this return value.
- Empty or unreadable image data causes an explanation and no image data transmission.
- Valid text input keeps its current path. An unavailable image must not cause a text or path substitute.

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
| Terminal lacks native support | The installed Ghostel build cannot deliver clipboard images. Use a local Session or a Ghostel build with native paste support. |
| Local terminal client is not the input leader | Another client owns input for this Session. Type in this Session first, then paste again. |
| CLI has no client-side implementation | Preserve the current route with no new message. |
| No GUI selection or no usable clipboard data | Name the unavailable clipboard condition. Ask the user to copy an image in a graphical session before another paste. |
| OMP lacks the verified-transfer receiver profile | The receiver cannot validate this image transfer. Update OMP before another remote image paste. |
| A verified attempt is still active | An image paste is already active. Wait for its outcome before another paste. |
| Connection loss after possible delivery | Delivery is unconfirmed. Check the Agent's attachment before deciding whether to paste again. |

Successful routes and unchanged legacy routes produce no new package message.
A refusal must not replace the gesture with another operation.

## Compatibility matrix

| Ghostel | CLI client side | Route | Sends |
|---|---|---|---|
| Any | none | unchanged | `C-v`, or text paste |
| Older, no predicate | `omp` | explained refusal | nothing |
| With native support | verified `omp` receiver | verified terminal paste | paste event, then metadata and image |
| With native support | OSC 5522-only `omp` | explained receiver-upgrade refusal | no image bytes |
| With native support, non-leading client | `omp` | explained refusal | nothing |

## Verification obligations

- Ghostel proves C1, C2, and C3 with its own Elisp and Zig tests
  (`make test`, `make test-zig`).
- The package proves C4, C5, and C6 with ERT cases that mock C1 and C2 at their
  interfaces, and by keeping the existing paste tests passing unchanged.
- The live walkthrough in [quickstart.md](../quickstart.md) proves the two together on
  a real remote Session.

## Receiver obligations under the approved design

OMP owns the final attachment decision.
It validates the active request ID, metadata, MIME, byte count, digest, and deadline before committing an image.
Its initial watchdog starts before the read request and remains active through image preparation.
The final commit gate checks expiry even when the timer callback has not run.
All asynchronous preparation finishes before the gate permits synchronous editor mutations.

A busy receiver refuses the new gesture without replacing the active attempt.
Stop, disable, or Session identity changes cancel uncommitted receiver work.
Late packets and stale preparation results cannot attach to another Session or revive an expired attempt.

The wire contract defines the verified-transfer profile.
T005R now has focused checks and actual local CLI editor evidence. Remote delivery remains an original story acceptance check.
