# Data Model: Remote RPC Project Views

## Design Rules

Use the existing generated Session ID as the Session key. Never use a directory as a Session key.

Keep this feature's records in memory. Reuse existing manager layout storage, but do not persist attempts, workers, buffer ownership, or new manual-close history.

Buffer objects and attachment objects establish runtime ownership. Buffer names are display labels, not proof of ownership.

## Entities

### 1. Host Preferences

| Field | Type | Rule |
|-------|------|------|
| Project-view hosts | List of exact host strings | Default nil. An entry does not approve a host. |
| Cleanup hosts | List of exact host strings | Default nil. Independent of Project-view enablement. |
| Approved hosts | Existing `claude-code-ide-remote-hosts` | Authoritative destination allowlist. This feature does not modify it. |

Effective preparation permission requires both approval and Project-view enablement. Cleanup permission requires the separate cleanup option and known local ownership.

Preference changes may invalidate an attempt. They must not start preparation, open a view, contact a host, or clean up buffers.

### 2. Session View Intent

Store one record per remembered Session ID in the feature module.

| Field | Purpose |
|-------|---------|
| Session ID | Stable existing Session identity. |
| Exact host | The configured destination spelling. |
| Attachment token | The current Session object or terminal buffer object, not its name. |
| Requested view key | Last resolved shared identity, or unknown. |
| Requested view buffer | Exact live buffer object, when available. |
| Captured layout view name | Memory-only name captured with the exact buffer object. Supports safe saved-state substitution after rename. |
| Manual-close suppression | Boolean. Only `R` clears a true value for this remembered Session. |
| Current attempt | Exact attempt object, or nil. |
| Last preparation outcome | Ready, failed, canceled, or none. Prevents accidental retries during navigation. |

Suppression survives replacement of the terminal buffer during reattach. It does not gain a new cross-restart persistence field.

Reuse the manager's existing `first-managed-switch` flag with the exact attachment token. Do not add a second attachment-considered flag.

A sibling Session's buffer kill invalidates the shared buffer reference. It does not set this Session's suppression. If this Session still requests the view, managed display can prepare a replacement.

### 3. Preparation Attempt

| Field | Purpose |
|-------|---------|
| Attempt object identity | Unique token. A newer `R` replaces the current object. |
| Session ID and attachment token | Reject completion from an old attachment. |
| Exact host and RPC directory | Target identity captured without changing Session metadata. |
| State | `checking-client`, `health`, `resolving-view`, `waiting-for-view`, `preparing`, `ready`, `failed`, or `abandoned`. |
| Worker thread | Owns synchronous remote and provider work. |
| Connection initialization in progress | Shared flag. Cancellation invalidates immediately but defers thread signaling until the guarded native checkpoint. |
| Health start and deadline timer | Bounds health only, including initial connection acquisition. |
| Resolved view key | Chooses the per-view writer boundary after identity resolution. |
| Candidate buffer | Provider result before publication. |
| Abandon reason | Cancel, reset, detach, disabled host, lost approval, or deadline. |

The current-attempt pointer is the primary freshness check. No global request generation counter is necessary.

An invalidated attempt cannot schedule new feature work, enter provider fallback, register a result, or change a layout. It never owns the shared RPC connection.

### 4. Shared Project View

Key forms:

```text
(exact-host git canonical-remote-worktree-root)
(exact-host directory exact-remote-directory)
```

The kind discriminator prevents a directory view from masquerading as a known Git Worktree view.

| Field | Purpose |
|-------|---------|
| View key | Exact host plus resolved Git Worktree or non-Git directory identity. |
| Buffer object | A live Magit/Dired/custom status buffer, or nil after a kill. |
| Origin | `created-by-feature`, `preexisting`, or `uncertain-custom`. |
| Creator kind | Known Magit/Dired creation path, or unknown. |
| Feature writer | The attempt currently allowed to prepare this view. |
| Interested Sessions | Session IDs whose runtime intents request this key. |

The registry retains origin when an owned buffer is reused by a later attempt. It never upgrades a preexisting or uncertain buffer into feature ownership.

Two different Git Worktrees remain separate even when their Git common directory is the same. Existing metadata uses `:worktree-path`, not `:common-dir`, for this distinction.

Use known existing group metadata only as evidence it actually supplies. Unknown or mismatched metadata does not establish cleanup exclusivity. Do not change metadata refresh policy.

### 5. Frame Display Intent

Keep a frame-local runtime record for Project-view integration. Do not replace the manager's existing global state model.

| Field | Purpose |
|-------|---------|
| Current managed Session ID | The Session this frame currently presents. |
| Terminal buffer object | The exact attachment visible in this frame. |
| View buffer and view window | The last actual Project-view display, if any. |
| Layout epoch | Advances for manager-driven layout mutations. |
| Command snapshot | Before-command Session, terminal, view, and epoch for closure detection. |

Completion may display only when the same Session and terminal remain current and visible. The selected window can be the terminal, manager, or another window.

If the frame now presents another Session, the result can remain available in the registry. It cannot change that frame.

Default-layout creation and restoration update the frame token. Session-ended and remembered-remote-state transitions clear only matching stale attachment tokens, without clearing suppression.

After restore, a ready requested buffer may still need insertion because the saved layout predates completion. That insertion uses no remote operation.

### 6. Cleanup Snapshot

Capture this ephemeral snapshot at the explicit detach command boundary, before generic terminal cleanup removes ownership evidence.

| Field | Purpose |
|-------|---------|
| Session ID and attachment token | Reject cleanup for a newer attachment. |
| Host | Evaluate the independent cleanup option. |
| Candidate view records | Only records already owned by this feature. |
| Other attached Sessions | Known host and project evidence for sharing checks. |
| Retention reasons | Modified, reused, source file, shared, unknown, or vetoed. |

Do not put source-file buffers in the candidate list. Do not scan a project's files or ask the server to resolve ownership during cleanup.

## State Transitions

| Event | Previous state | Result |
|-------|----------------|--------|
| Startup, render, ordinary refresh, or preference enablement | Any | No new attempt. |
| Bulk attach without display | New attachment | No new attempt. |
| First managed display on an approved enabled host | No suppression, no current attempt | Display terminal, then start preparation. |
| Ordinary navigation with a surviving view | Ready | Restore the exact buffer and saved layout without remote refresh. |
| Ordinary navigation after failure or explicit cancellation | Failed/canceled | Terminal only. No automatic retry. |
| Managed display after sibling killed the requested buffer | Missing shared buffer, no own suppression | Permit replacement preparation. |
| Reattach followed by managed display | New attachment, no suppression | Permit fresh preparation or refresh. |
| Reattach after own manual closure | Suppressed | Preserve suppression. Do not prepare automatically. |
| `R` | Any attached enabled-host state | Abandon old attempt, clear suppression, reset full layout, start fresh health. |
| Cancel action | Pending | Invalidate immediately. Signal private abandonment outside connection initialization, or stop at its guarded checkpoint. Retain terminal and connection. |
| Health deadline | Health | Report host, abandon only this attempt, retain terminal and connection. |
| Natural transport failure | Pending | Report failure. Preserve the installed client's own cleanup policy. |
| Session switch | Pending | Continue preparation without permission to replace the new Session's layout. |
| Valid completion in the original visible Session | Preparing | Publish and display without selecting a window. |
| Valid completion while another Session is current | Preparing | Publish for later use, without changing that frame. |
| Old attachment completion | Any | Ignore the result. |
| User dismisses a displayed Project view | Displayed | Suppress only the initiating Session. |
| User kills a shared view buffer | Displayed | Mark buffer dead for all users. Suppress only the initiating Session. |
| Explicit detach succeeds | Attached | Invalidate attempt, then apply the independent conservative cleanup policy. |
| Generic terminal close, network loss, Stop, or exit | Attached | Invalidate stale attempt ownership. Do not invoke Project-view cleanup. |

## Invariants

1. A Session ID never changes because a view resolves to a Worktree root.
2. Each exact host and view identity has at most one published current buffer.
3. A Session has at most one current preparation attempt.
4. A feature writer must own both its attempt and its view before it publishes.
5. No automatic path clears manual-close suppression.
6. Ordinary Session switching does not cancel preparation.
7. A never-displayed candidate cannot establish manual closure.
8. Feature cancellation never signals `quit` or calls connection cleanup.
9. Cleanup never discovers remote identity or saves a buffer.
10. A newer attachment cannot inherit an old attempt's completion or cleanup.
11. View restoration never resolves a dead buffer name into an unrelated live buffer.
12. A buffer opened from a Project view remains a source-file buffer, not an owned view.

## Cleanup Eligibility

A buffer is eligible only when every condition below is true:

- The current action is a successful explicit manager detach.
- The host's separate cleanup option is enabled.
- The snapshot still refers to the detached attachment, not a newer one.
- The registry proves this feature created the buffer through a known Magit/Dired path.
- The buffer is still the registered buffer object.
- The buffer's exact major mode is `magit-status-mode` or `dired-mode`.
- The buffer is unmodified, has no `buffer-file-name`, and has no process.
- `tramp-temp-buffer-file-name` is nil.
- No unknown buffer-local kill or query hook is present. Ignore the `t` marker that inherits global hooks.
- No other attached Session uses the same view identity.
- No same-host attached Session has insufficient identity evidence to exclude sharing.
- No cleanup veto or ownership uncertainty exists.

If any condition fails, retain the buffer. Report the relevant retained views without prompting for a save. Do not close the RPC connection in either case.

For an eligible view, bind `kill-buffer-query-functions` to nil for the kill, as existing Session cleanup does. Run global kill hooks unchanged.

This prevents perspective-related prompts without bypassing the global hooks that keep perspective and buffer-name state consistent. Verify cleanup in the real perspective-enabled profile.

Explicit detach of a disconnected remembered row is also eligible when the same local ownership proof exists. It must not contact the host.
