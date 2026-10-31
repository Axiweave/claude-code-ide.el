# Feature Specification: Disconnect Session

**Feature Branch**: `020-disconnect-session`

**Created**: 2026-10-31

**Status**: Draft

**Input**: User description: "implement disconnect function; bind to d; that keep the row but disconnet it; like how we restart emacs"

## Background

The manager has two commands that end a Session client:

- **Detach** (`D`/`X`) closes the client, leaves the Agent running in zmx, and removes the row. When the host is in the Project-view cleanup list, Detach also closes the unmodified Project-view buffers that it owns.
- **Stop** (`K`) ends the Agent and removes the row.

Spec 019 added a third result. When the terminal client of a zmx-backed Session ends without Stop or Detach, the row stays as a Disconnected session row. This happens when the user kills the terminal buffer, when a remote connection drops, and at an Emacs restart with manager state persistence on. Selection or `c` reattaches the row later.

The user can get this result today only by a buffer kill. A buffer kill is not safe as a habit. On a Session that does not run in zmx, a buffer kill ends the Agent. This feature adds **Disconnect**, a named command on `d`. Disconnect gives the result of a buffer kill on a zmx-backed Session and refuses every Session where that result would end the Agent.

## Clarifications

### Session 2026-10-31

- Q: Should Disconnect be available only on `d` in the manager, or also from inside a Session terminal and the main `claude-code-ide` menu? → A: Manager `d`, plus an interactive command for the current Session (`M-x`), with no new menu key (FR-015).
- Q: After you disconnect the Session that the main window shows, what should that window show? → A: The buffer-kill result. Emacs closes each window that shows the terminal. A frame's sole main window cannot close, so it shows another buffer. Disconnect activates no other Session (FR-017).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Disconnect a live Session and keep its row (Priority: P1)

The user has a live zmx-backed Session in the manager and wants to release its terminal client without losing the row. The user moves point to the row and presses `d`. The terminal client closes, the Agent keeps running, and the row stays in place with `[disconnected]`.

**Why this priority**: This is the full ask. It is the only story that delivers new behavior.

**Independent Test**: Start a local zmx-backed Session, rename it, and pin it. Press `d` on its row. Compare the row before and after, and confirm that the zmx session still runs.

**Acceptance Scenarios**:

1. **Given** a live local zmx-backed Session, **When** the user presses `d` on its row, **Then** its terminal buffer closes, its zmx session keeps running, and the row shows `[disconnected]`.
2. **Given** a live remote zmx-backed Session, **When** the user presses `d` on its row, **Then** its terminal buffer closes, its remote zmx session keeps running, and the row shows `[disconnected]` under its host.
3. **Given** a live Session with a custom name, a pin, a manual position, and a Saved layout, **When** the user disconnects it, **Then** the row keeps the same number, name, pin, position, Project group, and Saved layout.
4. **Given** a live Session with working or idle activity, **When** the user disconnects it, **Then** the row shows no activity, as other disconnected rows do.
5. **Given** the user disconnects a Session, **When** the manager redraws, **Then** point stays on the same row.
6. **Given** the user disconnects a Session, **When** the command completes, **Then** the manager shows a message that names the Session and tells the user to press `c` to reattach.
7. **Given** the user is in a live zmx-backed Session buffer, **When** the user runs the Disconnect command with `M-x`, **Then** that Session disconnects with the same result as `d` on its row.

---

### User Story 2 - Reattach a disconnected Session (Priority: P1)

After a disconnect, the user returns to the Session with the existing reattach paths. Disconnect adds no new reattach path.

**Why this priority**: A disconnect has no value if the row cannot come back. Stories 1 and 2 together deliver the requested behavior.

**Independent Test**: Disconnect a Session with `d`, then press `c` on the row. Confirm that the terminal shows the earlier Agent output and the row keeps its identity.

**Acceptance Scenarios**:

1. **Given** a row that the user disconnected with `d`, **When** the user presses `c` on it, **Then** the manager reattaches it under the same Session identity, and the Agent does not restart.
2. **Given** a row that the user disconnected with `d` and auto-reattach on selection is on, **When** the user selects the row, **Then** the manager reattaches it and switches to it.
3. **Given** a row that the user disconnected with `d` and manager state persistence is on, **When** Emacs restarts, **Then** the row is still in the manager as `[disconnected]` and the user can reattach it.

---

### User Story 3 - Disconnect refuses actions it cannot do safely (Priority: P2)

The user runs Disconnect on a Session where it makes no sense or can lose work. The manager refuses and explains why. Nothing changes.

**Why this priority**: This guard is the reason for a named command. A buffer kill on a Session without zmx ends the Agent. A command whose name says it keeps the Agent must never end one.

**Independent Test**: Run Disconnect on a plain (non-zmx) Session, on a row that is already disconnected, and with no Session at point. Confirm that each one shows a message and changes nothing.

**Acceptance Scenarios**:

1. **Given** a live Session that does not run in zmx, **When** the user runs Disconnect, **Then** the manager refuses, says that the Session is not zmx-backed, and keeps the Session running.
2. **Given** a row that is already disconnected, **When** the user presses `d`, **Then** the manager says that the Session is already disconnected and changes nothing.
3. **Given** point is not on a Session row, **When** the user presses `d`, **Then** the manager says that no Session is at point.
4. **Given** the current buffer belongs to no Session, **When** the user runs the Disconnect command with `M-x`, **Then** the command says that there is no current Session.
5. **Given** a remote row with a reattach or stop already in progress, **When** the user runs Disconnect, **Then** the manager refuses and names the operation in progress.

### Edge Cases

- The Session terminal is visible in one or more windows. As after a buffer kill, each split or side window that showed it closes, and a sole main window shows another buffer. Disconnect activates no other Session. The Saved layout stays for reattach.
- The remote host becomes unreachable during the disconnect. The terminal client still closes on this machine, and the row stays as `[disconnected]`. The disconnect does not need a reply from the host.
- A second Emacs instance has a client on the same zmx session. The disconnect closes only this instance's client.
- The disconnected Session has Project-view buffers (remote Project files). Disconnect does not clean them up, as a buffer kill does not. Only Detach can clean them up, and only for hosts in the Project-view cleanup list.
- Manager state persistence is off. The row stays `[disconnected]` for the rest of this Emacs instance and goes away at restart, as other disconnected rows do.
- The user presses `d` in Grouped, Flat, or Focused view. Each view keeps the disconnected row where its rules put disconnected rows today.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The manager MUST bind `d` to Disconnect in the manager buffer.
- **FR-002**: Disconnect MUST close the terminal client of the zmx-backed Session and MUST NOT end its Agent or its zmx session.
- **FR-003**: After Disconnect, the manager MUST keep the row as a Disconnected session row with the same Session identity, zmx name, Session directory, Agent type, host, number, display name, custom name, order, pin, Project group, and Saved layout.
- **FR-004**: A row that Disconnect produces MUST be a Disconnected session row as spec 019 defines it, with no added state. All existing reattach, detach, stop, persistence, and cleanup paths MUST treat it as they treat any other Disconnected session row.
- **FR-005**: Disconnect MUST work for local and remote zmx-backed Sessions with the same behavior.
- **FR-006**: Disconnect MUST NOT need a reply from a remote host.
- **FR-007**: Disconnect MUST refuse a Session that does not run in zmx and keep that Session running.
- **FR-008**: Disconnect MUST report and change nothing when the row is already disconnected or when there is no target Session.
- **FR-009**: Disconnect MUST refuse a remote row while a reattach or stop for that row is in progress.
- **FR-010**: After `d`, point MUST stay on the same row.
- **FR-011**: Disconnect MUST show a message that names the Session and tells the user to press `c` to reattach.
- **FR-012**: Disconnect MUST NOT run Project-view cleanup. Detach keeps its cleanup behavior.
- **FR-013**: The manager command menu (`?`) MUST list Disconnect on `d`.
- **FR-014**: The behavior of `D`, `X`, `K`, `c`, `a`, and `A` MUST NOT change.
- **FR-015**: An interactive command MUST disconnect the Session of the current buffer, with the same result and refusals as `d`. It MUST NOT add a key to the main `claude-code-ide` menu.
- **FR-016**: A disconnected row MUST show no activity (working, idle, or needs-input), as other Disconnected session rows do.
- **FR-017**: Disconnect MUST NOT add window rules. Each window that showed the terminal MUST get the buffer-kill result: a split or side window closes, and a frame's sole main window shows another buffer. Disconnect MUST NOT activate another Session. The disconnected Session stops being the active Session, as after a buffer kill.

### Key Entities

- **Disconnect**: A command on one Session, from the manager row at point or from the current buffer. It closes the terminal client and keeps the Agent, the zmx session, and the row.
- **Disconnected session row**: The existing row state for a zmx-backed Session without a live client in this Emacs instance. It holds the Session identity, zmx name, Session directory, Agent type, host (remote rows only), presentation fields (number, names, order, pin), and Saved layout. Spec 003 defines it for remote rows, and spec 019 extends it to local rows. Disconnect produces it.
- **Detach**: The existing command on `D`/`X`. It closes the client, keeps the Agent, and removes the row. For hosts in the Project-view cleanup list, it also closes the Project-view buffers that it owns. Disconnect keeps the row and runs no Project-view cleanup.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The user can release a Session client and keep its row with one key press, with no risk of ending the Agent. Today the only way is a buffer kill, which ends the Agent of a Session that does not run in zmx.
- **SC-002**: In every test, a row after Disconnect has the same number, name, order, pin, Project group, and Saved layout as before Disconnect.
- **SC-003**: Zero Agents end because of Disconnect. Earlier terminal output stays visible after reattach in every test.
- **SC-004**: Disconnect followed by `c` returns the user to the same Session in one key press each.
- **SC-005**: All existing tests for Detach, Stop, reattach, and attach pass unchanged.

## Assumptions

- Spec 019 is in place (commit `a19f021`), so a local zmx-backed row already stays as `[disconnected]` when its terminal buffer closes. Without spec 019, a local buffer kill removes the row. Disconnect reuses that state and adds no new row state.
- `d` has no binding in the manager buffer today, so the new binding hides no command.
- Disconnect works on one Session only. A bulk disconnect is out of scope.
- Disconnect asks for no confirmation, because it ends no Agent and the user can reverse it with `c`.
- Local and remote Sessions need no different behavior for this feature (constitution principle VI).
