# Data Model: Remote Project History

## Remote Repository Target

A target identifies one repository on one remote host.

| Field | Type | Rules |
|---|---|---|
| Host | String | Exact configured SSH destination. Non-empty and safe under existing host validation. |
| Repository | String | Absolute host-local path metadata. No control characters. Never a TRAMP or RPC file name. |

### Identity

The pair `(Host, Repository)` is unique. The same repository text on two hosts identifies two different targets.

### Validation

- Validate the host against the current configured-host list before use.
- Validate repository syntax before recording or use.
- Do not run local file predicates against the repository value.
- Do not contact the host during restore or candidate rendering.

## Recent Repository History

History groups repository paths by exact host and preserves most-recent-first order.

| Field | Type | Rules |
|---|---|---|
| Host | String | Group key. Stored as plain metadata. |
| Repositories | Ordered list of strings | Unique within the host. Most recent first. Maximum 20. |

### Relationships

- One host history contains zero to 20 repository paths.
- One remote repository target belongs to exactly one host history.
- The configured-host list controls whether a stored host history is available for selection.

### State Transitions

```text
Absent target
    │ accepted remote-open request
    ▼
Most recent target
    │ another target accepted
    ▼
Older retained target
    │ selected again
    └──────────────► Most recent target

Entry beyond position 20 ──► Removed
Malformed restored entry ──► Discarded
Unconfigured stored host ──► Retained but unavailable
```

### Restore Rules

1. Treat a missing history field as empty.
2. Ignore malformed host records and malformed repository values.
3. Preserve the first occurrence of each repository in stored order.
4. Keep no more than 20 repositories per host.
5. Keep unconfigured host groups inert.
6. Make no remote request.

## Remote-Open Request

A request captures an exact host, repository, and launch options.

### History Effect

- A prompt cancellation makes no request and changes no history.
- A synchronous validation failure changes no history.
- A returned operation ID records the captured target as most recent.
- Later remote failure does not remove the accepted target from history.
