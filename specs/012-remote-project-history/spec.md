# Feature Specification: Remote Project History

**Feature Branch**: `[012-remote-project-history]`

**Created**: 2026-09-14

**Status**: Draft

**Input**: User description: "Persist previously opened remote projects across Emacs restarts and offer them in a picker, while still allowing a new absolute path."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reopen a Recent Remote Project (Priority: P1)

A user opens the remote Worktree menu and selects a repository used before instead of typing its absolute path again.

**Why this priority**: This removes the repeated manual input that makes remote project opening slow and error-prone.

**Independent Test**: Open a repository once, restart Emacs, open the remote-project picker, and select that repository from the remembered choices.

**Acceptance Scenarios**:

1. **Given** a repository was accepted for a configured host, **When** the user opens the remote-project picker after restarting Emacs, **Then** that repository appears for the same host.
2. **Given** several repositories were accepted for one host, **When** the user opens the picker, **Then** the most recently accepted repository appears first.
3. **Given** two configured hosts have different histories, **When** the user selects either host, **Then** only repositories remembered for that host appear.

---

### User Story 2 - Open a New Absolute Path (Priority: P1)

A user enters an absolute repository path that is not in the remembered choices.

**Why this priority**: Remembered choices must not prevent access to a new or infrequently used repository.

**Independent Test**: Enter a valid absolute path that is not a completion candidate and confirm that the remote-open request uses it.

**Acceptance Scenarios**:

1. **Given** the wanted repository is not remembered, **When** the user enters its absolute path in the repository picker, **Then** the system accepts that path for the selected host.
2. **Given** the user supplies a relative or malformed path, **When** the system validates the entry, **Then** it refuses the entry without recording it.
3. **Given** a new absolute path is accepted, **When** the user opens the picker again, **Then** that path appears first.

---

### User Story 3 - Choose Another Project from a Remote Row (Priority: P2)

A user invokes the explicit remote Worktree command while point is on an existing remote Session row and chooses another host or repository.

**Why this priority**: The explicit command must not trap the user in the selected row's repository.

**Independent Test**: Put point on a remote Session row, invoke the explicit command, and verify that host and repository selection still occur.

**Acceptance Scenarios**:

1. **Given** point is on a remote Session row, **When** the user invokes the explicit remote-open command, **Then** the system asks for a host and repository instead of silently reusing the row.
2. **Given** point is on a remote Session row, **When** the user invokes the ordinary contextual open command, **Then** the command continues to use that row's remote context.

---

### User Story 4 - Keep Invalid History Inert (Priority: P3)

A user starts Emacs with obsolete or malformed remembered repository data and can still use remote project commands safely.

**Why this priority**: Persistent convenience data must not weaken host approval or block normal use.

**Independent Test**: Restore mixed valid and invalid remembered entries and verify that only approved, absolute targets become choices without contacting a host.

**Acceptance Scenarios**:

1. **Given** history contains an unconfigured host, **When** Emacs restores the history, **Then** that host's entries are unavailable for remote access.
2. **Given** history contains duplicate or malformed paths, **When** the picker reads the history, **Then** it presents each valid path once and omits invalid paths.
3. **Given** history is absent because it predates this feature, **When** Emacs restores existing manager state, **Then** all existing state remains usable and repository history starts empty.

### Edge Cases

- A configured host has no remembered repositories.
- A repository path contains spaces or characters that make display-string parsing unsafe.
- The same absolute path exists on two different hosts.
- A user cancels repository selection before supplying a valid path.
- A host is removed from the configured host list after its repositories were remembered.
- The remembered list exceeds its retention limit.
- Persistence is disabled in the manager settings.
- A remote-open request is refused before target acceptance.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST remember accepted remote repository targets across Emacs restarts when manager persistence is enabled.
- **FR-002**: Each remembered target MUST retain its exact configured host and absolute repository path as separate values.
- **FR-003**: The explicit remote-open command MUST ask the user to select a configured host regardless of the manager row under point.
- **FR-004**: After host selection, the system MUST present remembered repositories for only that exact host.
- **FR-005**: The repository picker MUST order choices from most recently accepted to least recently accepted.
- **FR-006**: The repository picker MUST accept a new absolute path that is not a remembered completion candidate.
- **FR-007**: The system MUST validate current host approval and absolute-path syntax before it records or uses a target.
- **FR-008**: The system MUST record a target only after the remote-open request accepts the captured host and repository.
- **FR-009**: Reusing a remembered repository MUST move it to the front without creating a duplicate.
- **FR-010**: The system MUST retain no more than 20 repository paths per host.
- **FR-011**: Restoring remembered targets MUST make no remote connection and start no remote operation.
- **FR-012**: Missing history in older manager state MUST restore as an empty history without affecting other saved manager data.
- **FR-013**: Invalid restored entries MUST remain inert and MUST NOT authorize access to an unconfigured host.
- **FR-014**: Disabling manager persistence MUST prevent repository history from surviving a later Emacs session.
- **FR-015**: The ordinary contextual open command MUST retain its existing behavior for a selected remote Session or remote project view.
- **FR-016**: Display labels MUST map directly to stored target values without deriving a path by parsing displayed text.
- **FR-017**: Canceling host or repository selection MUST leave remembered history unchanged.

### Key Entities

- **Remote repository target**: One exact configured host and one absolute repository path on that host.
- **Recent repository history**: An ordered, bounded set of unique repository paths grouped by exact host.
- **Remote-open request**: The captured request whose acceptance makes a repository eligible for history.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can reopen any of the 20 most recent repositories for a host without retyping its path.
- **SC-002**: A remembered repository remains selectable after one complete Emacs restart when persistence is enabled.
- **SC-003**: A user can select another remote project from a remote Session row in no more than three selections before Worktree selection.
- **SC-004**: Repeated acceptance of the same host and path produces exactly one picker choice.
- **SC-005**: All restored malformed paths and all targets for unconfigured hosts produce zero remote requests.
- **SC-006**: Existing saved manager state without repository history restores with no loss of Session rows, layouts, or manager choices.
- **SC-007**: In a representative usability check, users can reopen a remembered remote repository without consulting or copying its absolute path.

## Assumptions

- The existing configured-host list remains the authority for remote access.
- A repository path is plain host-local metadata and is not a local or remote file name during persistence restore.
- The explicit remote Worktree command is the discovery workflow; the ordinary open command remains contextual.
- Twenty recent repositories per host cover normal use without a separate history-management interface.
- Clearing all manager persistence also clears recent remote repository history.
- This feature does not discover repositories on a host, browse the remote filesystem, or verify repository existence during restore.
