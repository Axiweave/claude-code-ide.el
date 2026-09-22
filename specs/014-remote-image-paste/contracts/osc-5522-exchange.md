# Contract: OSC 5522 Paste Exchange

The wire contract between the terminal (Ghostel, serving the local clipboard) and the
application (the Agent CLI). Both directions are single packets terminated by ST
(`ESC \`) or BEL. Payloads are base64. The Agent's host never supplies clipboard data.

Written against the client implementation in `oh-my-pi`
(`packages/coding-agent/src/utils/enhanced-paste.ts`) and the upstream ghostty API from
PR `#13978` (`include/ghostty/vt/paste.h`, `include/ghostty/vt/terminal.h`).

## 1. Mode enable (application to terminal)

```text
CSI ? 5 5 2 2 h
```

The application enables paste events once, usually at startup. While the mode is on,
the terminal reports pastes as events instead of writing pasted text, and the event
takes precedence over bracketed paste.

The terminal must track the mode per terminal, not per Session and not globally. A
Session that reattaches to a running Agent receives the mode through normal terminal
state, because the multiplexer forwards application output verbatim (research R5).

## 2. Paste event (terminal to application)

Sent when the user pastes and the mode is on. Carries no clipboard data.

```text
ESC ] 5 5 2 2 ; <metadata> BEL
```

Metadata fields the terminal must supply:

| Field | Value | Rule |
|---|---|---|
| `type` | `read` | Required. |
| `status` | `OK` | Required for an event. |
| `name` | base64 of the literal `Paste event` | Required. The client matches on this value. |
| `mime` | base64 MIME name, repeated per available type | At least one. Images first when an image is available. The client falls back to the kitty dot-payload form when the terminal packs all types into one packet with a `.` target. |
| `pw` | base64 grant password | Required. Minted per event from a secure random source. |

## 3. Clipboard read (application to terminal)

```text
ESC ] 5 5 2 2 ; type=read:pw=<grant>:name=<base64 "Paste event">:mime=<base64 mime> BEL
```

Rules:

- `pw` must match a live grant. A missing, unknown, or already-used password is
  answered with a refusal, never with data.
- The MIME must be one the event advertised. Any other MIME is refused.
- The terminal answers this request from the local machine's clipboard. The
  multiplexer forwards the request to the local terminal unchanged, and the local
  terminal writes the answer back as input (research R5).

## 4. Reply (terminal to application)

Success, then data:

```text
ESC ] 5 5 2 2 ; type=read:status=OK BEL
ESC ] 5 5 2 2 ; type=read:status=DATA:mime=<base64 mime>;<base64 chunk> BEL
```

| Rule | Value |
|---|---|
| Chunk size | At most 4096 bytes of binary per packet, per the kitty limit |
| Chunking | Concatenated by the client in arrival order. Order and completeness are the terminal's responsibility. |
| Empty selection | Refusal packet, no DATA packet |
| Unknown or unavailable MIME | Refusal packet, no DATA packet |
| Partial transfer | The terminal must not send a DATA packet it cannot complete |

Refusal:

```text
ESC ] 5 5 2 2 ; type=read:status=<error> BEL
```

## 5. Pasting text (terminal to application)

A paste that is not image-bearing still passes through the paste API. The terminal
decides:

1. Mode 5522 on and a clipboard-read callback installed: send a paste event, and
   include `text/plain` among the advertised MIME types.
2. Otherwise: bracketed paste when the application enabled it, then a plain paste.

A payload that would break the frame (an unbracketed newline, or the bracketed-paste
terminator) must be rejected by the pasting layer and written nowhere. The caller
reports the rejection; it never writes a partial paste.

## 6. Multiplexer passthrough requirements

The path must satisfy these conditions for the exchange to complete. Each is already
true of stock zmx; the plan verifies rather than changes them.

1. Application output reaches the local terminal with OSC sequences intact, so the
   read request arrives.
2. The local terminal client is the input leader, so its answer reaches the Agent's
   process. A non-leading client's answer is dropped, and the Session explains that
   condition.
3. Terminal state, including the mode enable, is reproduced for a client that
   attaches later.

## 7. What must not happen

- No clipboard data in an event packet. Data flows only in the reply to a granted
  read.
- No second read on one grant.
- No file path, temporary file, or textual placeholder in place of image data.
- No clipboard read without a local paste gesture in the serving Session.
- No modification, downscaling, or re-encoding of the image bytes.
