# Data Model: Remote Image Paste

This feature adds no persisted application data or database schema.
It adds a route decision, a capability probe, and transient host and receiver state.
The wire metadata has a fixed schema, but no transfer state survives the attempt.

## Entity: Paste route

The decision the package makes when the user presses the paste gesture.

| Field | Source | Validation |
|---|---|---|
| `cli-type` | The Session's recorded CLI type, as today (`claude`, `codex`, `omp`, …) | Must be a known type. Unknown types take the existing text path. |
| `host` | The Session's host, or nil for a local Session | Nil means local. A non-nil value must already be an approved exact host. |
| `clipboard-has-image-p` | `gui-get-selection 'CLIPBOARD 'TARGETS` scan, as today (`claude-code-ide-session--clipboard-image-p`) | Existing rule: an `image/*` target or a known image target symbol. |
| `terminal-paste-events-p` | The Ghostel capability predicate | Absent predicate, or a nil result, means unsupported. |
| `agent-paste-events-p` | Private set of CLI types eligible for the route | `omp` today. Its installed receiver must also support the verified profile. |

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

The host serves these bytes in memory. The transport never creates an image file.
OMP may use its ordinary attachment storage after verified receipt.

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
| `mime-types` | Host attempt policy, not the upstream grant table | Only advertised representations may be served. |
| `lifecycle` | Original upstream handler, with host cancellation | Consumed once or removed when the attempt expires, fails, or ends. |

Rules:

- The grant is created by a paste gesture and by nothing else.
- A request without the grant is answered with a refusal, not with data.
- The grant never authorizes a second read, a different MIME set, or a read from
  another Session (spec FR-007).

## Entity: Verified receiver attempt

| Field | Owner | Validation |
|---|---|---|
| Request ID | OMP receiver | Fresh `ghostel-v1-` UUID. Required on each response packet. |
| Selected MIME | OMP receiver | Must match the advertised image and metadata. |
| Image bytes | OMP receiver | Exact declared count and SHA-256 before preparation. |
| Deadline | OMP receiver | Request-start time plus the remaining host budget. Never extended. |
| Commit permission | OMP receiver | Single use, active, unexpired, and bound to the original Session and editor. |
| Phase | OMP receiver | Reading, preparing, committed, or canceled. |

The watchdog remains active through asynchronous image preparation.
A busy attempt refuses another gesture rather than replacing its state.
Packets or continuations from a canceled attempt cannot modify another attempt.
No field here is a second grant store.

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
  -> application requests metadata and image  (one granted read with a fresh ID)
  -> terminal reads the selected image once   (authorized clipboard callback)
  -> terminal sends metadata and image        (upstream packet encoding)
  -> receiver verifies bytes and expiry
  -> receiver prepares the image               (ordinary Agent processing)
  -> guarded synchronous editor commit
  -> idle

failure paths:
  no grant                     -> refusal packet, no data
  MIME unavailable             -> refusal packet, no data
  no GUI selection             -> refusal packet, no data
  non-leading local client     -> preflight refusal, no transmission or takeover
  unsafe text payload          -> rejected by the pasting API, nothing written
  malformed or incomplete data -> receiver refusal, no attachment
  receiver deadline expired    -> no commit, explanation
  overlapping gesture          -> busy explanation, active attempt unchanged
  connection outcome unknown   -> delivery unconfirmed, no automatic retry
```

## Invariants

1. A gesture in one Session never attaches an image to another Session.
2. An image reaches the Agent only as an attachment the Agent itself created from
   MIME data. No path, file, or textual substitute is ever sent (spec FR-005).
3. Every gesture produces an attachment, unchanged text paste, or explanation.
   A lost connection may leave delivery unconfirmed (spec FR-004).
4. No clipboard read occurs without a gesture (spec FR-006).
5. The transport creates no image file on the Agent host and needs no remote clipboard.
   Ordinary Agent attachment storage remains unchanged (spec FR-005, FR-008).
