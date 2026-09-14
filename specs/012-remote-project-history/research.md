# Research: Remote Project History

## Decision: Reuse manager persistence

Store recent remote repositories in the manager's existing persisted state. Add one top-level `:remote-repositories` field beside `:scopes` and `:layouts`.

**Rationale**: The manager already owns cross-restart state, persistence enablement, loading, saving, and clearing. Reusing it gives the feature the same lifecycle without user configuration or another file format.

**Alternatives considered**:

- Roll a separate history file. Rejected because it duplicates storage lifecycle and error handling.
- Use `savehist`. Rejected because it requires separate registration and would split manager state across two persistence systems.
- Derive history from persisted Session rows. Rejected because a Session directory is a Worktree, not necessarily the repository selected by the user.

## Decision: Use an additive state field without a schema bump

Serialize an ordered alist whose keys are exact configured host strings and whose values are most-recent-first absolute repository paths. Treat a missing field as empty.

**Rationale**: Existing versions already ignore unknown top-level fields. The added field does not change the meaning of existing fields. Versions 1 through 4 can restore with empty history, while version 4 state written by this feature includes the extra field.

**Alternatives considered**:

- Increment the state version. Rejected because no existing field changes shape or meaning.
- Store timestamps. Rejected because list order fully represents MRU order.
- Store display labels. Rejected because labels are presentation data and can collide.

## Decision: Validate restored metadata without remote I/O

Accept only string hosts and syntactically valid absolute remote paths. Keep history grouped by its stored host, but expose entries only when that host remains configured.

**Rationale**: Restore must remain local and inert. Current host approval must be checked at use time because configuration can change between Emacs sessions.

**Alternatives considered**:

- Contact every host during restore. Rejected because startup and restore must not initiate remote work.
- Delete entries for currently unconfigured hosts during restore. Rejected because a temporarily removed host can become configured again. Inert retention preserves convenience without granting access.

## Decision: Accept standard completion input

After host selection, use `completing-read` with remembered paths and permit
non-candidate input. Validate each result as an absolute path. Retry invalid
input until the user enters a valid path or cancels.

**Rationale**: `completing-read` already supports free minibuffer input and
standard completion front ends provide commands such as `vertico-exit-input`.
Removing a sentinel and second prompt makes remembered and new paths use one
interface.

**Alternatives considered**:

- Show an explicit `Other…` candidate. Rejected because standard completion
  already accepts non-candidate input without a second prompt.
- Use a remote directory browser. Rejected because it would add remote I/O and change the existing security and latency model.
- Build a custom selection buffer. Rejected because the standard completion interface already covers the workflow.

## Decision: Make the explicit command always prompt

`claude-code-ide-manager-open-remote` always asks for host and repository. `claude-code-ide-manager-open` continues to use the remote row or remote Project-view context.

**Rationale**: The explicit `W o` workflow means "choose a remote project." Context reuse made another project inaccessible whenever point was on a remote row. Keeping contextual reuse in ordinary `o` preserves the fast path.

**Alternatives considered**:

- Require point on an empty manager line. Rejected because the manager normally keeps point on a Session row.
- Add another command or prefix solely to force prompts. Rejected because the existing explicit command already represents project choice.

## Decision: Record after synchronous request acceptance

Record the host and repository only after `claude-code-ide-remote-worktree-request` returns an operation ID. That call synchronously validates host approval and path syntax before it schedules remote preparation.

**Rationale**: A thrown validation error or canceled prompt cannot enter history. Waiting for remote completion would require a new cross-module callback and would omit valid targets when observation stops. The history represents accepted open requests, not proof that a remote operation completed.

**Alternatives considered**:

- Record before request creation. Rejected because refused targets would pollute history.
- Record after remote approval or completion. Rejected because it adds lifecycle coupling and makes history depend on continued local observation.

## Decision: Bound and normalize MRU data at both seams

On record, remove duplicate paths, prepend the selected path, and retain at most 20 entries for that host. On restore, discard malformed entries, deduplicate in stored order, and apply the same limit.

**Rationale**: Record-time normalization keeps normal state small. Restore-time normalization treats persisted data as untrusted and protects against old or edited state.

**Alternatives considered**:

- Enforce the limit only when recording. Rejected because persisted data can be malformed or oversized.
- Add a history-management interface. Rejected because a 20-entry MRU list needs no separate UI.
