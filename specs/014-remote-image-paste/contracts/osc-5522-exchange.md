# Contract: OSC 5522 Paste Exchange

The wire contract between Ghostel, which serves the local clipboard, and the Agent CLI.
Each packet ends with ST (`ESC \`) or BEL. Payloads are base64.
A reply contains several packets. The Agent's host never supplies clipboard data.

The base exchange matches OMP's `packages/coding-agent/src/utils/enhanced-paste.ts`
and the direct Zig API at Ghostty commit `e4240606752e5e4eb480b69104d75db0054f71c8`.
The verified-transfer profile below is a receiver design, not implemented support.
T005 remains open. No partial-attachment guarantee may depend on local write completion.

## 1. Mode enable (application to terminal)

```text
CSI ? 5 5 2 2 h
```

The application enables paste events once, usually at startup. While the mode is on,
the terminal reports pastes as events instead of writing pasted text, and the event
takes precedence over bracketed paste.

The terminal must track the mode per terminal, not globally.
Reattachment must restore this mode before the remote image route can work.
Live output forwarding alone does not prove mode restoration. T005 must verify the actual replay behavior.

## 2. Paste event (terminal to application)

The terminal sends a MIME listing when the user pastes with the mode enabled.
The listing contains no clipboard payload bytes.
The pinned native producer sends an `OK`, `DATA`, `DONE` sequence:

```text
ESC ] 5522 ; type=read:status=OK:pw=<grant> BEL
ESC ] 5522 ; type=read:status=DATA:mime=Lg==:pw=<grant>;<base64 whitespace-separated MIME list> BEL
ESC ] 5522 ; type=read:status=DONE:pw=<grant> BEL
```

The single `DATA` packet uses `.` as the MIME-listing sentinel.
The current OMP client also accepts the older per-MIME listing form.
Mint the grant through the native terminal's secure random source.
The client selects its preferred MIME after `DONE` and sends the grant back in the read request.
It supplies the base64 `Paste event` name in that request, not as a required event-matching field.

Sources: OMP `enhanced-paste.ts:130-228` and native `kitty/clipboard_response.zig:150-215`.
The T005 native wire check exercised paired MIME reads, request-ID echo, and both terminators.

## 3. Clipboard read (application to terminal)

```text
ESC ] 5522 ; type=read:pw=<grant>:name=<base64 "Paste event">:id=<request-id>;<base64 whitespace-separated requested MIME list> BEL
```

Rules:

- `pw` must match a live grant. A missing, unknown, or already-used password is
  answered with a refusal, never with data.
- The MIME must be one the event advertised. Any other MIME is refused.
- The standard `id` correlates every reply packet with its request. It does not replace the grant.
- The terminal answers this request from the local machine's clipboard. The
  multiplexer forwards the request to the local terminal unchanged, and the local
  terminal writes the answer back as input (research R5).

## 4. Reply (terminal to application)

The terminal sends `OK`, complete `DATA` packets, then `DONE`:

```text
ESC ] 5522 ; type=read:status=OK:id=<request-id> BEL
ESC ] 5522 ; type=read:status=DATA:id=<request-id>:mime=<base64 mime>;<base64 chunk> BEL
ESC ] 5522 ; type=read:status=DONE:id=<request-id> BEL
```

OMP attaches the image only after `DONE`. The client sends no attachment acknowledgement back to the terminal.
T005 must establish failure observation without treating transmitted `DONE` as proof of attachment.

| Rule | Value |
|---|---|
| Chunk size | At most 4096 bytes of binary per packet, per the kitty limit |
| Chunking | The native encoder preserves representation order. The verified receiver must check identity, byte count, and digest before attachment. |
| Empty selection | Refusal packet, no DATA packet |
| Unknown or unavailable MIME | Refusal packet, no DATA packet |
| Partial transfer | A disconnect can interrupt a packet. Receiver validation must prevent incomplete or mixed image data from becoming an attachment. |

Refusal:

```text
ESC ] 5 5 2 2 ; type=read:status=<error> BEL
```

## 5. Pasting text (terminal to application)

The package's existing text route remains unchanged.
When a caller explicitly uses the new Ghostel paste API for text, the terminal chooses the following behavior:

1. Mode 5522 on and a clipboard-read callback installed: send a paste event, and
   include `text/plain` among the advertised MIME types.
2. Otherwise: bracketed paste when the application enabled it, then a plain paste.

A payload that would break the frame (an unbracketed newline, or the bracketed-paste
terminator) must be rejected by the pasting layer and written nowhere. The caller
reports the rejection; it never writes a partial paste.

## 6. Multiplexer passthrough requirements

The path must satisfy the following conditions for the exchange to complete.
T005 must verify leadership observation and late-attachment mode restoration. Do not assume stock zmx satisfies those conditions.

1. Application output reaches the local terminal with OSC sequences intact, so the
   read request arrives.
2. The local terminal client is the input leader, so its answer reaches the Agent's
   process. A non-leading client's answer is dropped, and the Session explains that
   condition.
3. Terminal state, including the mode enable, is reproduced for a client that
   attaches later.
4. Input pressure must not discard accepted bytes. The transport must stop accepting input until queued bytes can advance.

Live acceptance confirmed that stock zmx 0.8.1 violates the fourth condition.
Its PTY input queue discards new bytes when the queue exceeds 256 KiB.
The user approved a backpressure correction and private candidate checks.
The correction must preserve the existing IPC format, leadership rules, OSC framing, and clipboard grants.
Installation needs separate approval.

## 7. What must not happen

- No clipboard data in an event packet. Data flows only in the reply to a granted
  read.
- No second read on one grant.
- No file path, temporary file, or textual placeholder in place of image data.
- No clipboard read without a local paste gesture in the serving Session.
- No modification, downscaling, or re-encoding of the image bytes.

## 8. Verified-transfer receiver design

**Status: implemented and checked in the private Ghostel and OMP candidates.**
The receiver validates integrity and expiry before its final editor commit.
The remaining zmx input-loss prerequisite and live acceptance results appear in [quickstart.md](../quickstart.md).

### Negotiation and one authorized read

Ghostel advertises `application/vnd.ghostel.paste-v1+json` with the real clipboard image MIME types.
This extra representation contains transfer metadata, not another image or a file path.
OMP requests that MIME first and its preferred image MIME second, using one fresh request ID and one grant.
Request IDs use `ghostel-v1-` followed by a random UUID.
This form fits the upstream ID alphabet and length limit without sanitization.
Ghostel refuses an image-only read on this profile and explains that the receiver needs verified-transfer support.
It must not downgrade to unverified bytes or raw `C-v`.
OMP's existing routes for terminals without this profile remain unchanged.

The host reads the image once, after the authorized request.
It sends the metadata representation before the unchanged image through the upstream encoder.
The upstream handler remains the sole protocol encoder and grant owner.
No second metadata parser or grant table is necessary.

### Metadata representation

```json
{
  "version": 1,
  "mime": "image/png",
  "bytes": 5242880,
  "sha256": "<64 lowercase hexadecimal characters>",
  "remaining_ms": 9000
}
```

The receiver requires valid field types and a supported version.
On the wire, the object uses compact canonical JSON with exactly these five fields.
After parsing, `JSON.stringify` must reproduce the decoded text exactly.
This rejects duplicate keys and ambiguous encodings without another JSON parser.
The image MIME must equal its selected MIME.
The byte count must be a positive safe integer.
The metadata representation must fit in one DATA packet and contain at most 1024 decoded bytes.
This metadata limit does not cap image bytes.
`remaining_ms` must be an integer from 1 through 10000.
The digest must contain exactly 64 lowercase hexadecimal characters.
The request ID stays in standard packet metadata, where the upstream encoder echoes it on every packet.

### Expiry and attachment boundary

The receiver records its monotonic request-start time before writing the read request.
It starts a ten-second watchdog at that point, before metadata can arrive.
The host samples its remaining gesture budget when it creates the metadata.
The receiver adds that remaining budget to request-start time, not metadata-arrival time.
The new deadline may shorten the initial watchdog, but must never extend it.
An already-expired metadata record must cause immediate refusal.
The receiver uses `performance.now()`. The host uses Zig's monotonic `std.Io.Clock.awake`.
The deadline governs admission at the final synchronous receiver commit gate.
The supported timing model assumes normal clock progress while both machines remain awake.
Different clock origins do not matter. Arbitrary clock-rate changes and machine suspension are not a shared physical-time guarantee.
Known TUI stop or suspension cancels pending receiver work before terminal handoff.
The ten-second visible result remains a measured acceptance target, not an unconditional display deadline.

A timer alone cannot prevent a late attachment.
The receiver must check expiry after asynchronous preparation and immediately before the editor commit.
It must not await more work between that check and the editor mutations.
Cancellation, receiver disable, and Session identity changes must invalidate the pending commit.
An overlapping gesture must receive a busy explanation without replacing the active attempt.

### Integrity and isolation

Before attachment, the receiver must require:

- The active request ID on every response packet.
  Failure statuses must also match that ID.
- One valid metadata representation and one selected image representation.
- Strict base64 validation for each complete DATA packet.
- A final `DONE` for that same request.
- Exact agreement with the declared byte count and SHA-256.
- An active, unexpired attempt at the final editor commit.

A partial packet, absent metadata, wrong ID, incomplete payload, or digest mismatch must never produce an attachment.
The receiver must discard canceled state before another verified transfer starts.
It must not merge replies from different attempts.
Packets with a verified-transfer ID must never enter the legacy receive route, even after cancellation or expiry.
Unknown or inactive verified-transfer IDs must not change another attempt's state.
The host must serialize verified exchanges in each terminal.

### Outcome reporting gate

Local write completion still does not prove receiver attachment.
Receiver validation prevents incomplete images from committing and enforces its local commit deadline.
If connection loss leaves the receiver outcome unavailable, the host reports delivery unconfirmed.
It does not retry automatically or claim that sent bytes were canceled.
No implementation may label an unknown outcome as confirmed failure or confirmed attachment.

### Receiver implementation prerequisite

Keep the verified attempt active through normalization, persistence, link preparation, and dimension probing.
Complete every awaited preparation step before changing pending editor image state.
A one-shot `tryCommit(apply)` gate must check identity, cancellation, and expiry before calling synchronous `apply`.
The adapter must also preserve the original Session and editor and recheck modal focus.
The timer must stay active until commit, refusal, or cancellation.
Late preparation results must not change editor state or another attempt.

Use the existing image-preparation path for both verified and legacy images.
Legacy callers do not need the new gate.
Ordinary Agent artifacts can remain after a canceled preparation, as the Agent-storage exclusion permits.
Do not delete shared content-named files to simulate cancellation.

T005 and T005R passed the focused checks and receiver-to-editor smoke check.
T015 retains the live transport acceptance gate. See [tasks.md](../tasks.md) for the current task status.
