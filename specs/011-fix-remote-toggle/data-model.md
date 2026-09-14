# Data Model: Fix Remote Session Toggle

This feature adds no stored field or schema. It reads existing in-memory values.

## Session

Represents one live Agent connection owned by the editor.

| Field | Meaning | Validation used by toggle |
| --- | --- | --- |
| `id` | Stable identity for the live Session | Must resolve to the same registered Session |
| `directory` | Bare project path on the Session host | Must remain metadata. Never qualify or access it as a local path |
| `host` | Remote destination, or nil for local | Preserves local and remote identity when paths collide |
| `buffer` | Owned terminal buffer | Must be live before toggle can use it |
| `process` | Terminal attachment process or buffer | May supply the live terminal when `buffer` is absent |

**Relationships**:

- A local Session has no host.
- A remote Session has one host.
- A Session can own one live terminal buffer.
- A Session can have one saved manager layout.

## Manager Layout

Represents saved display state for one Session.

| Value | Meaning | Validation used by toggle |
| --- | --- | --- |
| Session key | Identifies the owning Session | Must resolve to a live Session |
| `project-view-buffer` | Managed project view associated with the Session | Must be exactly the invoking buffer |
| Window state | Saved arrangement for the Session | Existing toggle logic restores it unchanged |

**Relationships**:

- A layout belongs to one Session key.
- A project-view buffer can appear in existing shared view state, but toggle uses the active layout owner.
- Exact buffer identity prevents unrelated remote buffers from inheriting a Session.

## Remembered Target

Represents a disconnected remote target in manager state.

| Value | Meaning | Toggle rule |
| --- | --- | --- |
| Session key | Persistent target identity | Does not imply a live Session |
| Host and directory | Reattach metadata | Must not trigger lookup by directory alone |
| Terminal buffer | Absent while disconnected | Makes the target ineligible for toggle |

## Resolution State Transitions

```text
Invoking buffer
├── owns live terminal ───────────────> exact Session
├── equals active saved project view ─> exact live layout Session
└── neither
    ├── local project fallback found ─> preferred local Session
    └── no live Session ──────────────> explicit user error
```

Toggle changes only window visibility. It does not change Session state, target connection state, host approval, or persistence.
