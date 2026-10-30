# Feature Specification: Local Session Reattach

**Feature Branch**: `019-local-session-reattach`

**Created**: 2026-10-29

**Status**: Draft

**Input**: User description: "Make local sessions behave like the remote ones in the manager, so I can reattach when restarting Emacs. Still keep the current a/A for attaching as well." The attached screenshot shows remote Sessions that stay in the manager as numbered `[disconnected]` rows under their host and Project group after an Emacs restart.

## Background

A remote Session that loses its client stays in the manager as a Disconnected session row. The row keeps its number, name, order, pin, and Project group. Selection or `c` reattaches it under the same identity. The row goes away only after a verified Stop, an explicit detach, or a confirmed absence of its zmx session.

A local Session that runs inside a local zmx session does not get this treatment. When its client ends, for example when Emacs exits, the manager removes the row. The Agent keeps running inside zmx, but the user must find it again with `a` (attach one) or `A` (attach-select). The manager then gives it a new identity, so the custom name, order, pin, and Saved layout are gone.

This feature makes the local workflow match the remote one. Constitution principle VI names local behavior as the reference. Here the remote workflow is ahead, so this feature brings local up to it.

## Clarifications

### Session 2026-10-29

- Q: When Emacs starts, should the manager remove remembered local rows whose zmx session no longer exists, or keep them until you act on them? → A: Remove dead local rows automatically when the manager first shows rows in a new Emacs. Keep all rows if the zmx list cannot be read (FR-011, FR-013).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Local rows survive an Emacs restart (Priority: P1)

The user runs several local zmx-backed Sessions, then restarts Emacs. When the manager opens again, each Session whose zmx session still runs shows as a `[disconnected]` row. Each row has the same number, name, Project group, order, and pin as before the restart.

**Why this priority**: This is the core ask. Without remembered rows, there is nothing to reattach from the manager.

**Independent Test**: Start two local zmx-backed Sessions, give one a custom name and pin it, then restart Emacs. Open the manager and compare the rows with the rows before the restart.

**Acceptance Scenarios**:

1. **Given** two local zmx-backed Sessions in one project, **When** Emacs exits and starts again, **Then** the manager shows both rows as `[disconnected]` in the same Project group and order.
2. **Given** a local zmx-backed Session with a custom name and a pin, **When** Emacs restarts, **Then** its disconnected row keeps the custom name and the pin.
3. **Given** a local zmx-backed Session, **When** the user kills its terminal buffer without Stop or detach, **Then** the row stays in the manager as `[disconnected]`.
4. **Given** a local Session that does not use zmx, **When** Emacs exits, **Then** the manager does not remember it, as today.

---

### User Story 2 - Reattach a disconnected local row (Priority: P1)

The user selects a disconnected local row, or presses `c` on it. The manager attaches a new client to the same zmx session under the same Session identity and switches to it. The Agent does not restart.

**Why this priority**: A remembered row has no value if the user cannot reattach from it. Stories 1 and 2 together deliver the requested behavior.

**Independent Test**: With a disconnected local row from Story 1, press `c` on the row. Confirm that the terminal shows the running Agent's earlier output and that the row keeps its number, name, and pin.

**Acceptance Scenarios**:

1. **Given** a disconnected local row whose zmx session still runs, **When** the user presses `c` on it, **Then** the manager reattaches it, switches to it, and the row becomes live with the same number, name, order, and pin.
2. **Given** a disconnected local row and auto-reattach on selection enabled, **When** the user selects the row, **Then** the manager reattaches it and switches to it.
3. **Given** a disconnected local row and auto-reattach on selection disabled, **When** the user selects the row, **Then** the manager reports that the Session is disconnected and tells the user to press `c`.
4. **Given** a disconnected local row with a Saved layout, **When** the user reattaches it, **Then** the manager restores that Saved layout as it does for a live Session.

---

### User Story 3 - `a` and `A` keep working and do not duplicate rows (Priority: P2)

The user keeps using `a` and `A` to adopt local zmx sessions, including sessions started outside Emacs. When the chosen zmx session already has a disconnected row, the attach reuses that row instead of adding a second one.

**Why this priority**: The user asked to keep `a` and `A`. Duplicate rows for one zmx session would make the manager wrong.

**Independent Test**: With a disconnected local row, press `a` and pick the same zmx session. Confirm that the manager shows one live row with the original identity.

**Acceptance Scenarios**:

1. **Given** a disconnected local row for zmx session N, **When** the user attaches N with `a`, **Then** the manager shows one live row for N with the remembered number, name, order, and pin.
2. **Given** disconnected local rows for zmx sessions N1 and N2, **When** the user marks both in `A` and applies, **Then** both rows become live and no new rows appear.
3. **Given** a local zmx session with no remembered row, **When** the user attaches it with `a` or `A`, **Then** the manager adds a new row, as today.
4. **Given** a local zmx session that already has a live row, **When** the user opens `a` or `A`, **Then** the picker does not list it, as today.

---

### User Story 4 - Rows for ended Agents go away (Priority: P2)

When a local Agent exits and its zmx session ends, the manager removes the row. A remembered row whose zmx session no longer exists, for example after a reboot, also goes away instead of staying as a row that can never reattach.

**Why this priority**: Without cleanup, dead rows pile up after every reboot. The user would have to remove each one by hand.

**Independent Test**: Remember a disconnected local row, end its zmx session outside Emacs, then restart Emacs and open the manager. Confirm the row is gone.

**Acceptance Scenarios**:

1. **Given** a live local zmx-backed Session, **When** the Agent exits and its zmx session ends, **Then** the manager removes the row.
2. **Given** a remembered local row whose zmx session no longer exists, **When** the manager first shows remembered rows in a new Emacs instance, **Then** the manager removes that row.
3. **Given** a remembered local row whose zmx session no longer exists, **When** the user selects it or presses `c` on it, **Then** the manager reports that the zmx session is gone and removes the row.
4. **Given** the local session list cannot be read (for example, zmx is not installed), **When** the manager checks remembered rows, **Then** it keeps every row and does not report an error until the user tries to reattach one.

---

### User Story 5 - Stop and detach end a disconnected local row (Priority: P3)

The user removes a disconnected local row with the existing detach command (`X`/`D`) or stops its Agent with `K`. These commands behave as they do for disconnected remote rows.

**Why this priority**: The user needs a way to clear a row that they no longer want. The commands already exist for remote rows.

**Independent Test**: On a disconnected local row, press `D`, and confirm the row goes away while the zmx session still runs. On another row, press `K`, and confirm both the row and the zmx session go away.

**Acceptance Scenarios**:

1. **Given** a disconnected local row, **When** the user detaches it, **Then** the manager removes the row and the zmx session keeps running.
2. **Given** a disconnected local row, **When** the user stops it and the stop succeeds, **Then** the manager removes the row and the zmx session no longer exists.
3. **Given** a disconnected local row, **When** the stop fails, **Then** the manager keeps the row and reports the failure.

### Edge Cases

- A second Emacs instance is attached to the same local zmx session. Reattach from this instance adds one more client and does not take the session from the other instance.
- The remembered Session directory no longer exists. Reattach reports the missing directory and keeps the row, as a local attach does today. The user can restore the directory or remove the row with detach.
- The remembered row has no Agent type. Reattach asks for the Agent type, as remote reattach does.
- The user selects a disconnected row while a reattach of that row is already in progress. The manager does not start a second client.
- A local row and a remote row use the same zmx name. They stay separate rows, because a remote name belongs to its host and never matches a local name.
- Manager state persistence is off. No row survives an Emacs restart, local or remote, as today.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The manager MUST keep a local zmx-backed Session as a Disconnected session row when its client ends and its zmx session still exists.
- **FR-002**: The manager MUST keep disconnected local rows across Emacs restarts with the same Session identity, number, display name, custom name, order, pin, Project group, and Saved layout.
- **FR-003**: The manager MUST mark disconnected local rows with the same `[disconnected]` status text and help text that disconnected remote rows use.
- **FR-004**: The manager MUST place a disconnected local row in its local Project group, at the position its live row had. In each view (Grouped, Flat, Focused), it MUST follow the rules that apply to disconnected remote rows.
- **FR-005**: `c` on a disconnected local row MUST reattach it under the same Session identity and switch to it. `c` MUST NOT reject local rows.
- **FR-006**: Selection of a disconnected local row MUST follow the same auto-reattach preference as selection of a disconnected remote row. One preference MUST govern both.
- **FR-007**: Reattach MUST connect to the existing zmx session and MUST NOT start a new Agent.
- **FR-008**: `a` and `A` MUST continue to list and adopt local zmx sessions that have no live row in this Emacs instance, including sessions started outside Emacs.
- **FR-009**: When `a` or `A` adopts a local zmx session that has a remembered row, the manager MUST reuse that row's identity and MUST NOT add a second row.
- **FR-010**: The manager MUST remove a local row when its Agent exits and its zmx session no longer exists.
- **FR-011**: The manager MUST remove remembered local rows whose zmx session no longer exists when it first shows remembered rows in an Emacs instance, if the local session list can be read.
- **FR-012**: When reattach finds that the zmx session no longer exists, the manager MUST report this and remove the row.
- **FR-013**: When the local session list cannot be read, the manager MUST keep every remembered local row. A reattach attempt MUST report the reason and keep the row.
- **FR-014**: Detach (`X`/`D`) on a disconnected local row MUST remove the row and leave the zmx session running.
- **FR-015**: Stop (`K`) on a disconnected local row MUST end its zmx session and then remove the row. A failed Stop MUST keep the row.
- **FR-016**: Local Sessions that do not run inside zmx MUST keep today's behavior: the row goes away when the Session ends.
- **FR-017**: Existing remote disconnected-row behavior MUST NOT change.

### Key Entities

- **Disconnected local row**: A manager row for a local zmx-backed Session that has no live client in this Emacs instance. It holds the Session identity, zmx name, Session directory, Agent type, presentation fields (number, names, order, pin), and Saved layout. It has no host.
- **Local zmx session**: The persistent PTY on this machine that owns the Agent process. Its existence decides whether a disconnected local row can be reattached.
- **Auto-reattach preference**: The single user preference that decides whether selection of any disconnected row reattaches it or only reports that it is disconnected.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After an Emacs restart, 100% of local zmx-backed Sessions whose Agent still runs appear in the manager with the same number, name, order, and pin as before the restart.
- **SC-002**: The user can return to a running local Agent after an Emacs restart with one action on its row (selection or `c`). Today this takes a picker and a new identity.
- **SC-003**: Reattach of a local row never starts a second copy of the Agent. Earlier terminal output stays visible after reattach in every test.
- **SC-004**: After a machine reboot, zero rows remain for local Agents that no longer run, without any manual cleanup by the user, when the local session list can be read.
- **SC-005**: For any one zmx session, the manager never shows more than one row, whichever path (selection, `c`, `a`, `A`) attaches it.
- **SC-006**: All existing tests for remote disconnected rows and for `a`/`A` pass unchanged, except tests that assert the old local-row removal.

## Assumptions

- The feature applies only when local Sessions run inside zmx. Without zmx, no Agent survives Emacs, so nothing can be reattached.
- Manager state persistence is on. With persistence off, rows do not survive a restart, which is today's behavior for remote rows too.
- The existing auto-reattach preference for remote rows (still uncommitted work) becomes one preference for both local and remote rows. No separate local preference is added.
- The local session list is a cheap local query. This is the concrete difference from remote rows: remote cleanup at startup would need a network call per host, so remote rows keep today's behavior and are not checked at startup.
- Local rows keep today's place in Grouped view (local Project groups, without a host heading). This feature does not add a "local host" heading.
- Reattach uses the environment that the zmx session got when it was created. The known MCP/SSE port limitation in `CONTEXT.md` still applies and is not solved here.
