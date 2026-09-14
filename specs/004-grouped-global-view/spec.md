# Feature Specification: Grouped Global View

**Feature**: `004-grouped-global-view`

**Created**: 2026-09-06

**Status**: Implemented and verified on 2026-09-06. See [acceptance results](quickstart.md#8-implementation-validation-record).

**Input**: `TODOs.org`, “global view with project + worktree”. Design interview decisions Q1–Q13.

## Clarifications

### Session 2026-09-06

- Q: Which remote sessions should the dedicated metadata refresh command update? → A: Prompt for one configured host. Refresh all known manager Sessions on that host, including remembered disconnected Sessions, without contacting other hosts or discovering new Sessions.

## User Scenarios & Testing

### User Story 1 - Switch between flat and grouped views (Priority: P1)

The user can see global manager Sessions under Project group headings without losing the current Session or its layout.

**Why this priority**: This is the feature's main purpose.

**Independent Test**: Open a global sidebar with Sessions in two repositories and linked Worktrees. Toggle the view in both directions.

**Acceptance Scenarios**:

1. Given Sessions in one repository's main and linked Worktrees, grouped view places their rows under one Project group heading.
2. Given two Sessions in one Worktree, grouped view shows two Session rows, not one Worktree row.
3. Given independent clones with the same remote URL, grouped view keeps them in separate Project groups.
4. Given identical repository names on one host, headings include enough parent-path information to distinguish the groups.
5. Given a non-Git Session, its project directory determines its Project group.
6. Given an active Session, a view toggle preserves that Session, its layout, and the selected Session row.
7. Given manager persistence is enabled, an Emacs restart restores the selected view.
8. Given a repo-local sidebar, the new global view setting does not change its behavior.

### User Story 2 - Navigate between project groups (Priority: P1)

The user can use `C-j` and `C-k` to move between Project groups without traversing every Session row.

**Why this priority**: Project navigation is an explicit requirement of the original feature request.

**Independent Test**: Navigate forward and backward through local and remote groups, including a group with a disconnected first Session.

**Acceptance Scenarios**:

1. From any Session row, `C-j` selects the first Session in the next Project group. `C-k` selects the first Session in the previous group.
2. For a connected target, the command displays the target Session and keeps keyboard focus in the sidebar.
3. Navigation wraps at the first and last groups and crosses host sections.
4. With only one Project group, a project jump does nothing.
5. When the first Session in a target group is disconnected, navigation selects its row without changing the displayed terminal.
6. For that disconnected target, the manager shows reattach guidance and makes no SSH request.
7. A later project jump continues from the selected disconnected Session's group, not from the still-active terminal's group.
8. Ordinary Session-row navigation skips headings.

### User Story 3 - Order sessions in grouped view (Priority: P1)

The user can pin Sessions, move Session rows, and use `E` while keeping Project groups intact.

**Why this priority**: Grouping must remain consistent with existing manager order controls.

**Independent Test**: Pin and reorder Sessions within two groups. Use `E` to apply valid within-group edits and reject cross-group edits.

**Acceptance Scenarios**:

1. Pins appear first within their Project group, followed by manual order and the configured fallback sort.
2. A Session move cannot cross a Project group boundary.
3. In grouped view, `E` permits within-group Session moves and whole-project block moves through linewise cut/paste.
4. Apply rejects cross-group Session moves, changed heading text or identity, and missing or duplicate headings.
5. Applying a valid order retains the existing editor behavior, including clearing pins in the edited manager scope.
6. Flat view and its order editor retain their existing behavior.
7. Quick slots follow displayed Session-row order across groups. Slots remain limited to 1–10, with `0` selecting slot 10.
8. Grouped `E` includes remembered disconnected Sessions. Their disconnected state alone does not prevent apply.
9. Apply rejects a snapshot if a Session vanished or its Project group changed while the editor was open.
10. Rejected apply changes neither order nor pins. The user can reopen the editor against the current groups.

### User Story 4 - Group remote sessions without network work during redraw (Priority: P1)

The user can see remote Project groups under configured-host headings, including remembered disconnected Sessions.

**Why this priority**: The original sketch explicitly includes a remote host and its Worktrees.

**Independent Test**: Attach remote Sessions from linked Worktrees, refresh their metadata, and then inspect the grouped view while disconnected.

**Acceptance Scenarios**:

1. Successful remote attach or reattach starts a metadata request. The dedicated metadata refresh command prompts for one configured host.
2. Remote Sessions from linked Worktrees share a Project group under their host heading.
3. The same repository path on different hosts does not create one shared group.
4. Cached information remains available for remembered disconnected Sessions.
5. Ordinary manager refresh (`G`), automatic refresh, startup, restoration, redraw, view toggle, and navigation make no SSH metadata requests.
6. Without repository information, the manager shows a clearly marked unresolved group rather than guessing repository relationships.
7. Without remote repository metadata, unresolved groups use the exact host and Session directory. A Session without a directory remains separate.
8. Once metadata becomes available, the manager replaces unresolved grouping with the resolved repository grouping.
9. A failed metadata request does not fail or undo attachment. It retains the last valid cache, if available.
10. Without cached metadata, failure leaves the target unresolved. A confirmed non-Git directory instead uses the non-Git grouping rule.
11. A removed configured host or invalid directory prevents request dispatch without changing the attached Session.
12. Dedicated metadata refresh updates all known manager Sessions on the chosen host, including remembered disconnected Sessions.
13. Dedicated metadata refresh neither contacts other hosts nor discovers new Sessions. It does not reattach disconnected Sessions.

### Edge Cases

- Multiple Sessions in one Worktree must remain independently selectable.
- Duplicate custom names must not make Session rows ambiguous.
- Detached HEAD and non-Git Sessions use a directory-name fallback when no branch exists.
- Independent clones remain separate even when their directory names and remote URLs match.
- Remembered disconnected remote Sessions remain visible under cached groups when metadata is available.
- Unavailable remote metadata must not cause the manager to interpret a remote path as a local repository.
- Empty Project groups and empty host sections do not appear.
- More than ten Sessions remain visible. Rows after slot 10 remain unnumbered.

## Requirements

### Functional Requirements

- **FR-001**: Add flat and grouped presentations to the existing global sidebar, not a separate sidebar or Session scope.
- **FR-002**: Provide an interactive toggle and a manager-menu entry for the view setting.
- **FR-003**: Use flat view initially. Remember the chosen view when manager persistence is enabled.
- **FR-004**: Share the global view choice across frames.
- **FR-005**: Preserve Sessions, active and selected Session identity, and saved layouts when the view changes.
- **FR-006**: Leave repo-local sidebar behavior unchanged.
- **FR-007**: Represent each Session with one row. Use Worktree branch labels without collapsing multiple Sessions into one row.
- **FR-008**: Group one Git repository and its linked Worktrees on one host together. Keep independent clones and different hosts separate.
- **FR-009**: For non-Git Sessions, use the project directory as the group identity.
- **FR-010**: Include only Worktrees represented by manager Sessions. Do not enumerate empty Worktrees as selectable rows.
- **FR-011**: Show local Project groups first, followed by remote host sections labeled `[host]`.
- **FR-012**: Sort host sections and Project groups by name. Apply Session order rules within groups.
- **FR-013**: Keep pins, manual Session order, and the configured fallback sort within each group. Prevent cross-group manual moves.
- **FR-014**: Support grouped `E` with writable project headings for whole-block cut/paste and within-group Session moves. Validate complete, unique headings and unchanged identities/text before saving.
- **FR-015**: Preserve order application and pin clearing. Grouped `E` validates Session presence in current scope items, not process liveness. Remembered disconnected Sessions remain eligible. Leave the flat-view editor unchanged.
- **FR-016**: Keep the branch visible in row labels. Append a custom name when present, such as `main · review`.
- **FR-017**: Without a custom name, add a Session-order suffix when needed to distinguish rows. Keep final row labels unambiguous.
- **FR-018**: Use the Worktree directory name when no branch exists.
- **FR-019**: Use repository directory names for headings. Add distinguishing parent-path information for duplicate names within a host.
- **FR-020**: Show a Project group's full path on hover. Never use matching labels as evidence of shared repository identity.
- **FR-021**: Assign global quick slots in displayed Session-row order across groups. Preserve slots 1–10 and the `0` binding for slot 10.
- **FR-022**: Make `C-j` and `C-k` select the first Session in the next or previous group, with wrapping across host sections.
- **FR-023**: Display connected jump targets while retaining sidebar focus. Keep existing Session-switch acknowledgment behavior.
- **FR-024**: For disconnected jump targets, select the row, retain the displayed terminal, and show explicit reattach guidance.
- **FR-025**: Continue group navigation from the selected row. Do nothing when only one group exists.
- **FR-026**: Make ordinary Session-row navigation skip headings.
- **FR-027**: Request remote repository and branch metadata after successful explicit attach or reattach. Provide a dedicated metadata refresh command in the manager menu. Prompt for one configured host, then refresh all known manager Sessions on that host, including remembered disconnected Sessions. Do not contact other hosts, discover new Sessions, or reattach disconnected Sessions through metadata refresh. Cache metadata for disconnected Sessions.
- **FR-028**: Keep ordinary manager refresh (`G`), automatic refresh, startup, restoration, redraw, view toggle, navigation, and repo-local sidebars free of SSH metadata requests.
- **FR-029**: Mark unresolved remote groups clearly. Group only by exact host and Session directory, or keep Sessions without directories separate. Replace unresolved grouping when repository metadata becomes available.
- **FR-030**: Keep all groups expanded and all headings non-interactive. Omit empty groups and empty host sections.
- **FR-031**: Apply existing remote control-request safeguards to metadata requests. Require a currently configured host, shared SSH options, a thirty-second deadline, and no retries.
- **FR-032**: Reject remote directories that are not absolute or contain control characters. Quote directory arguments for the remote POSIX shell without expansion.
- **FR-033**: Treat remote responses as data, never executable text. Validate absolute repository identity paths supplied by the remote host. Never resolve remote paths through local filesystem operations.
- **FR-034**: Metadata failure, timeout, malformed output, or missing Git must not fail or undo attachment. Preserve the last valid cache. Without a cache, use unresolved grouping. A confirmed non-Git result uses FR-009.
- **FR-035**: Grouped `E` must reject stale group membership or vanished snapshot Sessions before changing order or pins. Disconnection alone does not invalidate a snapshot.

### Existing Remote Contract Extension

This feature adds read-only Git metadata requests to the remote operations defined in feature 003.
It does not change stock zmx discovery, guarded attachment, Stop, or their safety rules.

The new metadata command is distinct from ordinary manager refresh (`G`).
The network-free refresh requirement in [Remote Session Access](../003-attach-remote-agents/contracts/remote-sessions.md) remains in force.

Metadata requests run after successful attachment, not as capability probes or prerequisites for attachment.
This extends the operations associated with an explicit attach action beyond the [Stock Zmx Attach Guard](../003-attach-remote-agents/contracts/zmx-attach-guard.md).
The implementation must update those contract documents to describe the extension without weakening the attach guard.

### Key Entities

Use the definitions in `CONTEXT.md`:

- **Session**: The independently selectable manager object, identified by Session ID.
- **Worktree**: A repository working directory that can contain multiple Sessions.
- **Project group**: Sessions belonging to one repository and its Worktrees on one host, or one non-Git project directory.
- **Configured host**: The approved remote destination that identifies a remote host section.
- **Grouped view** and **Flat view**: Two presentations of the same global manager Sessions.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Every manager Session appears exactly once in each view, with no empty Worktree rows.
- **SC-002**: Linked Worktrees share a group. Independent clones and different hosts do not.
- **SC-003**: A single project-jump command reaches the adjacent group without visiting its preceding Session rows.
- **SC-004**: View changes preserve active and selected Session identity and saved layouts.
- **SC-005**: Sidebar and editor order controls cannot move a Session across a group boundary in grouped view.
- **SC-006**: Quick slots select the corresponding displayed rows across group boundaries.
- **SC-007**: Redraw, view-toggle, and navigation scenarios produce no SSH metadata requests.
- **SC-008**: Disconnected group navigation preserves the displayed terminal and still permits the next project jump.
- **SC-009**: Grouped `E` applies valid order changes with disconnected rows and rejects stale groups without changing order or pins.
- **SC-010**: Unconfigured hosts and unsafe directory arguments never cause metadata dispatch. Metadata failures leave attached terminals intact.
- **SC-011**: Dedicated metadata refresh updates known manager Sessions only on the chosen configured host, including remembered disconnected Sessions. It causes no requests to other hosts, Session discovery, or reattachment.

## Scope Boundaries

- No separate manager sidebar, new Session identity scheme, or separate repo-local behavior.
- No rows for Worktrees without manager Sessions.
- No collapsing, interactive headings, or project-wide actions.
- Project-wide detach is a future idea from the user, not an accepted requirement for this feature.
- No automatic reattach during navigation.
- No implementation or commit has been authorized by the design interview alone.

## Decision Record

Q1–Q3 settled the row identity, Project group identity, and view switch.
Q4–Q6 settled persistence, ordering, labels, and quick slots.
Q7–Q9 settled navigation, remote metadata, and non-interactive headings.
Q10–Q12 settled grouped `E` support, duplicate project headings, and disconnected navigation.

Q13 confirmed the complete design and the exact host-plus-directory rule for unresolved remote groups.
The user required reviewer agreement before the implementation plan. The reviewer approved the corrected specification in the second review.
Implementation and commits remain outside this review.

### Reviewer Clarifications

The first review requested three conservative clarifications, without reopening accepted product choices:

- Keep `G` network-free and provide a distinct explicit metadata refresh action.
- Extend existing remote request safety rules to Git metadata, including safe directory arguments and attachment-independent failure.
- Let grouped `E` accept remembered disconnected rows by scope membership rather than process liveness.

The corrected spec also rejects stale grouped-editor snapshots and retains the last valid metadata cache after request failure.
The second review approved progression to an implementation plan with no remaining blockers or required user decisions.

The existing flat-view editor still rejects remembered disconnected rows during apply.
This feature corrects grouped-editor validation only, consistent with the accepted requirement to leave the flat-view editor unchanged.
