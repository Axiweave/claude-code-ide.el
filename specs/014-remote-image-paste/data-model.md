# Data Model: Remote Image Paste

This feature adds no stored data, no schema, and no persisted state. It adds one
routing decision, one capability probe, and one transient protocol exchange. The
entities below describe what must exist in memory during a paste, and what must never
be stored.

## Entity: Paste route

The decision the package makes when the user presses the paste gesture.

| Field | Source | Validation |
|---|---|---|
| `cli-type` | The Session's recorded CLI type, as today (`claude`, `codex`, `omp`, …) | Must be a known type. Unknown types take the existing text path. |
| `host` | The Session's host, or nil for a local Session | Nil means local. A non-nil value must already be an approved exact host. |
| `clipboard-has-image-p` | `gui-get-selection 'CLIPBOARD 'TARGETS` scan, as today (`claude-code-ide-session--clipboard-image-p`) | Existing rule: an `image/*` target or a known image target symbol. |
| `terminal-paste-events-p` | The Ghostel capability predicate | Absent predicate, or a nil result, means unsupported. |
| `agent-paste-events-p` | Static set of CLI types that implement the client side | `omp` today (research R2). |

Route rules, in order:

1. A local Session keeps the current behavior: send `C-v` when the clipboard holds an
   image and the CLI accepts images, otherwise `ghostel-yank` (spec FR-016).
2. A remote Session whose CLI does not implement the client side keeps the current
   behavior for that CLI. No image is sent, and no new message appears (spec FR-002).
3. A remote Session whose CLI implements the client side uses the terminal paste when
   the terminal reports the capability.
4. A remote Session whose CLI implements the client side and whose terminal reports no
   capability states the condition and the remedy, and sends nothing (spec FR-009).

Uniqueness: exactly one route applies per gesture, decided once, before any byte is
sent.

## Entity: Local clipboard content

The data the read reply may carry. Never persisted, never written to a file, never
copied to the Agent's host.

| Field | Source | Validation |
|---|---|---|
| `mime-types` | The GUI selection's `TARGETS`, mapped to protocol MIME names | At least one MIME type, or the reply is a refusal. |
| `payload` | Bytes read from the GUI selection at reply time | Nonempty. Base64-encoded into protocol chunks by the terminal layer. |
| `selection` | `CLIPBOARD` (standard) | Only the standard clipboard is served. |

Rules:

- Read on request, at the moment the application asks, matching today's local timing
  (spec EC-03, clarification session).
- Bytes are sent unchanged. No resizing, recompressing, transcoding, or size cap
  (spec FR-017).
- A read happens only for a gesture in the serving Session (spec FR-006, FR-007).

## Entity: Paste event grant

The one-time authorization the terminal mints for a paste event.

| Field | Owner | Validation |
|---|---|---|
| `password` | Minted by the terminal layer from a secure random source | Nonempty; single use. |
| `mime-types` | The available types at gesture time | Nonempty. |
| `lifecycle` | Terminal | Consumed by the matching read request, or discarded when the gesture ends. |

Rules:

- The grant is created by a paste gesture and by nothing else.
- A request without the grant is answered with a refusal, not with data.
- The grant never authorizes a second read, a different MIME set, or a read from
  another Session (spec FR-007).

## Entity: Capability report

What the package needs in order to choose a route, and what the user sees when the
route is unavailable.

| Field | Source | Validation |
|---|---|---|
| `paste-events-supported-p` | Ghostel predicate | Boolean. Absent predicate means unsupported. |
| `input-leader-p` | zmx leadership, when a multiplexer sits in the path | When false, the route is refused with an explanation (research R5). |

## Exchange states

The transient protocol state for one paste. Nothing here survives the gesture.

```text
idle
  -> mode enabled by the application          (application writes CSI ? 5522 h)
  -> gesture: terminal sends the event        (MIME list + grant, no data)
  -> application asks for one MIME            (OSC 5522 read with the grant)
  -> terminal asks the host for that MIME     (clipboard read callback, granted)
  -> host replies with chunks                 (base64 data packets)
  -> application attaches the image           (its own `[Image #N]` behavior)
  -> idle

failure paths, all terminal-side or host-side:
  no grant                     -> refusal packet, no data
  MIME unavailable             -> refusal packet, no data
  no GUI selection             -> refusal packet, no data
  non-leading local client     -> answer never reaches the Agent; the Session explains
  unsafe text payload          -> rejected by the pasting API, nothing written
```

## Invariants

1. A gesture in one Session never attaches an image to another Session.
2. An image reaches the Agent only as an attachment the Agent itself created from
   MIME data. No path, file, or textual substitute is ever sent (spec FR-005).
3. Every gesture ends in one visible outcome: an attachment, an unchanged text paste,
   or an explanation (spec FR-004).
4. No clipboard read occurs without a gesture (spec FR-006).
5. The Agent's host receives bytes only; it stores nothing and needs no clipboard
   (spec FR-005, FR-008).
