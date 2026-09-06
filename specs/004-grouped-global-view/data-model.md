# Data Model: Grouped Global View

## Existing Session and manager item

Session IDs remain the identity of selectable rows and saved layouts.
Add a `group-metadata` slot to `claude-code-ide-session` and `claude-code-ide-manager-item`.
Keep existing directory, host, zmx-name, order, pinned, custom-name, and display-name fields.

The live Session owns connected metadata. A remembered manager item owns disconnected metadata.
`--make-item` copies live metadata, or a matching previously validated cache when a replacement Session has not received new metadata.
A cache belongs to the exact host and Session directory that produced it.
Never reuse a cache for a different host or directory merely because the Session ID or label matches.

### Metadata plist

| Field | Type | Meaning |
|---|---|---|
| `:kind` | `git` or `non-git` | Last successful metadata classification |
| `:host` | string or nil | Exact configured destination, or local host |
| `:directory` | string | Exact Session directory at query time |
| `:common-dir` | absolute string or nil | Canonical Git common directory, resolved on the owning host |
| `:project-path` | absolute string | Parent of a literal `.git` common directory, otherwise the common directory, or the non-Git project directory |
| `:worktree-path` | absolute string or nil | Current worktree root, for branchless row labels |
| `:branch` | string or nil | Symbolic branch name, absent for detached HEAD or non-Git |

Absent metadata means unknown. Do not store `error` as replacement metadata.
Request errors are transient reports and do not erase the last valid cache.

Validate field types and required combinations before accepting wire or persisted metadata.
For remote paths, require a leading slash and reject control characters without calling filesystem functions or file-name handlers.
Require `:host` and `:directory` to equal the target item fields.
For Git metadata, common directory and project path are required. A bare target can have no worktree path.
For non-Git metadata, common directory, worktree path, and branch are absent.
Branch and heading text must remain single-line. Render strings as text, not display instructions.
Invalid cached metadata becomes absent metadata without removing a valid Session row.

## Derived group identity

Use structured keys with `equal` comparison, not concatenated strings with ambiguous delimiters.

| Case | Group key |
|---|---|
| Known Git repository | `(git HOST COMMON-DIR)` |
| Confirmed non-Git directory | `(non-git HOST PROJECT-DIRECTORY)` |
| Remote metadata unknown, directory present | `(unresolved HOST EXACT-SESSION-DIRECTORY)` |
| Remote directory missing | `(unresolved-session HOST SESSION-ID)` |
| Local repository query fails | `(unresolved nil CANONICAL-SESSION-DIRECTORY)` |

Local non-Git project directories use existing project-directory semantics and local canonicalization.
Remote non-Git and unresolved directories remain exact strings, including trailing separators.
Known Git identity uses the canonical path returned by the owning host.
Group identity never uses project labels, branch names, remote URLs, or custom Session names.

Project groups, Unresolved groups, and Host sections are derived presentation data, not new Session scopes or durable records.
A transient render projection contains ordered Session items, group boundaries, labels, and quick slots.
It contains no extra selectable items for headings or empty Worktrees.

## Global view state

Extend only the existing global scope state with `:view`, whose values are `flat` and `grouped`.
An absent or invalid value means `flat`. Repo-local scopes ignore this field.
Use the existing scope accessors and state serialization. Do not add a second global view variable.
The choice applies across frames because they share global scope state.

When persistence is disabled, the choice lasts for the current Emacs process only.
When persistence is enabled, a toggle saves the choice before a refresh can reload it.
Toggling never changes active or selected Session IDs, pins, order keys, or layouts.

### Persisted state migration

Advance `claude-code-ide-manager--state-version` from 3 to 4.
Update the empty-state value, reset-state value, version whitelist, item serialization, and scope serialization together.
Versions 1–3 remain readable through the existing legacy restoration path, with `flat` view and absent grouping metadata.
Do not reset order keys, selected IDs, active IDs, or saved layouts during migration.
Do not create metadata requests during migration or startup.
Transient request state and derived group labels never enter persisted data.

## Ordering state

Keep the existing scalar `order-key` and `pinned` fields. Both views share them.
Flat view keeps its comparator and label behavior.
Grouped view uses host/group ordering before applying the existing pin/manual/fallback precedence inside a group.
Session fallback reversal does not reverse hosts or groups.

For grouped sidebar moves, capture the current flat baseline and each group's displayed Session sequence.
Swap the eligible adjacent rows in the moved group's sequence, keeping the same-group and same-pin-bucket restrictions.
Use the occupied-position merge below for all group sequences, then assign keys without clearing pins.
This works even when flat directory-name order and grouped branch-name order disagree. Keep flat-view swaps unchanged.
For grouped `E`, capture a baseline flat sequence and each group's edited sequence.
Replace only that group's occupied positions in the baseline, preserving interleaving with other groups.
Apply keys to the merged snapshot sequence and preserve existing behavior for post-open Sessions.
The existing apply operation still clears pins throughout the edited scope.
Materialization gives snapshot rows explicit keys in both cases.
Untouched groups preserve their displayed order and occupied flat positions. Their internal flat fallback order can become their grouped order.

Example before edit: flat `[a1, b1, a2, b2]`.
Moving `a2` before `a1` in grouped `E` produces flat `[a2, b1, a1, b2]`, not `[a2, a1, b1, b2]`.

## Grouped editor snapshot

Keep the snapshot buffer-local. Capture:

- Manager scope and editor view at open.
- Ordered Session IDs and immutable opening row labels.
- Group identity for each Session ID.
- Fixed heading identities, text, and order.
- Baseline flat sequence of snapshot Session IDs.

A global view toggle does not silently rebuild an open editor.
The editor continues to use its captured view. Explicit sort resync replaces its snapshot using that view.
An external metadata completion updates the sidebar, not the editor contents.

Apply validates all rows and current group membership before any pin/order mutation.
Remembered disconnected rows are valid when they remain in current scope items.
Vanished Sessions, changed groups, foreign/duplicate rows, or modified fixed headings reject the complete apply.
Current labels remain distinct from identity. A branch-label change alone need not invalidate membership if the row still matches its opening label.

## Transient metadata operation

Use one non-persisted host-operation table in the manager.
Each host entry owns an operation token, current SSH process, pending directory batches, and captured target snapshots.
The table is necessary to serialize the two real triggers: post-attach metadata and explicit host refresh.
It is not a general job system or durable metadata cache.

Each captured target contains Session ID, exact host/directory/zmx name, and the original live Session/process identity when present.
For a remembered target, capture that it had no live owner.
A result may update only targets still matching their captured ownership and identity.
A remembered target that reattaches before completion rejects that old result.
A connected target that detaches before completion rejects its old result and preserves any prior cache through normal detach handling.
A verified Stop removes the target. A callback must never recreate it.

Only the current operation token can publish results or start the next batch.
Host removal, cancellation, or an obsolete token prevents further dispatch.
Successful results update current live records and manager items, then save state before refreshing the sidebar.
No callback calls `refresh-all` before saving its updates.

## State transitions

| Event | Metadata effect | Session effect |
|---|---|---|
| Local refresh | Recompute once per unique local directory | No identity change |
| Remote attach registers live Session | Queue optional metadata for that target | Display terminal without waiting |
| Explicit metadata refresh | Snapshot known targets on one prompted host | No discovery or reattach |
| Valid Git result | Replace cache and derive repository group | Preserve Session ID and layout |
| Valid non-Git result | Replace cache with non-Git classification | Preserve Session ID and layout |
| Error, malformed response, or timeout | Preserve last valid cache, otherwise unresolved | Leave attachment unchanged |
| Disconnect | Copy current cache to remembered item | Existing detach semantics |
| Stale callback | Ignore affected target | Never recreate or replace owner |
| Group changes while E is open | Sidebar can regroup | Editor apply rejects stale membership atomically |
| Ordinary G, startup, toggle, navigation | No remote request | Existing selection and lifecycle semantics |
