# Feature Specification: Remote Worktree Follow

**Feature**: `018-remote-worktree-follow`

**Created**: 2026-10-15

**Status**: Draft

**Input**: User description: "omp with wtmove + cc-ide sidebar; branch does not change; idea to support that? spec it; it use zmx + ssh; might make thing complex"

## Overview

An Agent can move its working directory to another Git worktree while it
runs (for example, the Oh My Pi `wtmove` command). For a local Session, the
manager row follows the move and shows the new path and branch. For a remote
Session, the row keeps the start directory and the start branch for the full
life of the Session.

Observed on 2026-10-15 with Session `*claude-code[v12x@v12dev]*<2>`:

| Field | Value |
|---|---|
| Session directory | `/home/yufu/v12x` |
| Terminal directory (from the Agent report) | `/rpc:v12dev:/home/yufu/wt/v12x/feat-030-target-checkout/` |
| Branch on the sidebar row | `feat/omniscience-bench` |
| Real branch of the Agent | `feat/030-target-checkout` |

The Agent report reaches Emacs. The Session move step then rejects it,
because that step accepts only local directories. A remote Session also has
three more parts that a local Session does not have:

- The remote terminal runs inside zmx on the remote host, and Emacs attaches
  to it over SSH. The only live signal of the Agent directory is the
  terminal directory report. A remote Agent has no MCP connection.
- The branch and the repository group of a remote row come from an
  asynchronous SSH probe. Today that probe runs only after an attach or after
  an explicit refresh command.
- The remembered row stores the directory. A reattach after an Emacs restart
  uses the stored directory.

This feature makes a remote Session follow a directory move with the same
result as a local Session, within these constraints.

## Clarifications

### Session 2026-10-15

- Q: After a remote Agent moves to another worktree, when should the Session's Magit or project view change to the new worktree? → A: Never automatically. The view keeps the old worktree until the user runs a layout reset (`R`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The sidebar shows the new branch after a remote move (Priority: P1)

The user runs an Agent in a remote Session. The Agent moves to a linked
worktree on the same host. The sidebar row changes to the new worktree
branch, and the row stays in the same repository group.

**Why this priority**: This is the reported problem. A wrong branch label
causes the user to act on the wrong worktree.

**Independent Test**: Start a remote Session in the main worktree of a
repository. Move the Agent to a linked worktree. Look at the sidebar row and
the row details.

**Acceptance Scenarios**:

1. **Given** a live remote Session in the main worktree on branch `A`,
   **When** the Agent reports a move to a linked worktree on branch `B` on
   the same host, **Then** the row shows branch `B` and the new path, and
   the row stays under the same host and repository group.
2. **Given** a remote Session that moved, **When** the user opens the row
   details, **Then** the details show the new path and branch `B`.
3. **Given** a remote Session that moved to a directory that is not in a
   Git repository, **When** the move result arrives, **Then** the row shows
   the new directory as a non-Git row, the same as a local Session in that
   directory.
4. **Given** a remote Session that moved to a worktree of a different
   repository, **When** the move result arrives, **Then** the row moves to
   the group of that repository.

---

### User Story 2 - A moved remote Session keeps its new directory after a restart (Priority: P2)

The user moves an Agent to another worktree, then restarts Emacs or loses
the SSH connection. The remembered row and the reattached Session use the
new directory, not the start directory.

**Why this priority**: Without this, the fix from User Story 1 is lost at
each restart, and the row shows the wrong branch again.

**Independent Test**: Move a remote Agent. Restart Emacs. Look at the
disconnected row. Reattach it and look at the row again.

**Acceptance Scenarios**:

1. **Given** a remote Session that moved, **When** Emacs restarts, **Then**
   the disconnected row shows the new path and the last known branch.
2. **Given** that disconnected row, **When** the user reattaches it,
   **Then** the Session starts in the new directory, and the row keeps its
   number, custom name, and layout.

---

### User Story 3 - Session views stay usable after a remote move (Priority: P3)

After a remote move, the user switches to the Session and uses its project
view, Magit view, companion shell, and file references. Nothing fails
because the Session directory changed.

**Why this priority**: A remote project view checks that its saved request
matches the current Session directory. A move makes old requests stale. The
move must not break the Session for the user.

**Independent Test**: Open the project view of a remote Session. Move the
Agent. Switch away from the Session, then back. Open the companion shell and
send a file reference.

**Acceptance Scenarios**:

1. **Given** a remote Session with an open project view, **When** the Agent
   moves and the user switches back to the Session, **Then** the switch
   succeeds, and the project view still shows the old worktree.
2. **Given** a remote Session that moved, **When** the user sends a file
   reference, **Then** the reference path is relative to the new directory.
3. **Given** a remote Session that moved, **When** the user runs a
   row-scoped worktree command, **Then** the command targets the new
   worktree.
4. **Given** a remote Session that moved and still shows the old worktree,
   **When** the user runs a layout reset (`R`), **Then** the project view
   and the Magit view show the new worktree.

---

### Edge Cases

- The Agent reports several moves fast. Only the last directory shows on
  the row. A probe result for an earlier directory never shows.
- A probe for the old directory is still running when the move arrives.
  Its result never shows on the row.
- A probe for another Session on the same host is running when the move
  arrives. The new probe waits in the queue. It does not fail, and it does
  not cancel the other probe.
- The probe fails (SSH error, timeout, or the directory is gone). The row
  shows the new path without a branch and stays in its previous group. The
  failure is reported in the same way as other probe failures.
- A companion shell creation starts before the move and ends after it. The
  shell opens in the old directory, because its view request is older than
  the move (FR-011).
- The report names the directory that the Session already has. Nothing
  changes, and no probe runs.
- The report is not an absolute path, or it contains control characters.
  The Session ignores the report.
- The terminal directory of the buffer has no remote prefix of the Session
  host (for example, the host has no RPC method configured, so the terminal
  builds a TRAMP name from the hostname that the Agent reported). The
  Session still takes the remote path part of the report, because the
  terminal runs on the Session host by construction.
- The user attaches a moved Session through `zmx list` discovery, and the
  row was never remembered. The row starts at the directory that zmx
  reports. It follows the next move report from the Agent.
- The buffer name (`*claude-code[v12x@v12dev]*`) and the zmx Session name
  keep the start directory. A local Session has the same behavior.
- The Session sort position changes when the directory changes. A local
  Session has the same behavior.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A remote Session MUST accept a directory report from its own
  terminal and store the remote path part as its directory. The stored value
  MUST be a bare absolute path on the Session host, never a TRAMP name.
- **FR-002**: The move step for a remote Session MUST NOT check, expand, or
  resolve the path on the local file system. It also MUST NOT open a
  synchronous connection to the remote host.
- **FR-003**: The move step MUST ignore a report that is not absolute, that
  contains control characters, or that is equal to the current directory.
- **FR-004**: After a remote move, the system MUST request new Git metadata
  for the new directory through the existing remote metadata probe. It MUST
  NOT add a new remote command, a remote file, or a new connection type.
- **FR-005**: The system MUST NOT show a probe result on a row when that
  result was for a directory other than the current Session directory.
- **FR-006**: While the new probe runs, the row MUST show the new path. It
  SHOULD stay in its previous repository group until the result arrives.
- **FR-007**: When the probe result arrives, the row MUST show the branch,
  worktree, and group from that result, with the same rules as a row that
  started in that directory.
- **FR-008**: When the probe fails, the row MUST show the new path without
  a branch. The failure MUST be reported in the same way as other remote
  metadata failures.
- **FR-009**: The system MUST save the new directory to the remembered row
  after a remote move, so that a restart and a reattach use the new
  directory.
- **FR-010**: A move MUST NOT change the Session ID, the row number, the
  custom name, the zmx Session name, the buffer name, or the saved layout.
- **FR-011**: A remote move MUST NOT change the project view or the Magit
  view of the Session. These views keep the old worktree until the user runs
  a layout reset (`R`). The reset MUST then show the new worktree. A switch
  to the Session MUST NOT fail, and MUST NOT rebuild the view, because of a
  view request that has the old directory.
- **FR-012**: A companion shell that is already open MUST stay open in its
  directory. A companion shell that opens after the move MUST start in the
  new directory.
- **FR-013**: Local Session moves MUST keep their current behavior.

### Key Entities

- **Session**: one Agent terminal. A remote Session has a host and a bare
  directory on that host. This feature lets the directory change during the
  life of the Session.
- **Directory report**: the working directory that the Agent terminal
  reports. It is the only live directory signal for a remote Agent.
- **Remote metadata probe**: the read-only SSH request that gets the
  repository, worktree, and branch for one or more directories on one host.
- **Remembered row**: the saved copy of a Session row that the manager
  shows after a restart or a disconnect, and that a reattach uses.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a remote Agent moves to another worktree, the sidebar
  row shows the correct branch within 5 seconds on a working SSH connection,
  in 10 of 10 tries.
- **SC-002**: In a test with 5 fast moves in a row, the row shows the
  branch of the last directory in 10 of 10 tries.
- **SC-003**: After a move and an Emacs restart, the disconnected row shows
  the moved path in 10 of 10 tries.
- **SC-004**: A move does not cause an error message when the user switches
  to the Session, opens the project view, or opens the companion shell.
- **SC-005**: The user needs zero manual commands to see the correct branch
  after a move.

## Assumptions

- The Agent reports its directory to the terminal when it moves. The
  `v12dev` Session showed this report on 2026-10-15.
- The Agent terminal runs on the Session host. An Agent does not report a
  directory on another host. A report is therefore a path on the Session
  host, even when the terminal name shows another hostname.
- A remote Agent has no MCP connection to Emacs. The MCP directory report is
  only for local Sessions and stays unchanged.
- Discovery through `zmx list` gives the start directory, not the live
  directory. This feature does not change zmx.
- FR-011 is a user decision (Clarifications, Session 2026-10-15). It matches
  the local move behavior: a local move also keeps the old view until a
  rebuild or `R` (research R6). Constitution principle VI needs no recorded
  difference for FR-011.
- Out of scope: renaming buffers or zmx Sessions after a move, moves between
  hosts, and a remote MCP connection.
