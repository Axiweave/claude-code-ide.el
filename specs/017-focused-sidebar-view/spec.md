# Feature Specification: Focused Sidebar View

**Feature**: `017-focused-sidebar-view`

**Created**: 2026-10-01

**Status**: Draft

**Input**: User description: "we have an idea; have a focused view; (toggle by f on side bar); only show session that need monitoring/input; so in this picture; only 3 (working one); plus idle/need-asking one; for idle one; after clear idle state -> switch to other session => user is non-interesting anymore -> kick out of focused view; so we will have only 3 session then we can more easily to jump between them becasue the number is low (1, 2, 3); btw still show [v12mac] v12x if its remote session even in focused view."

## Overview

The manager sidebar lists every Session. With many Sessions, the few that need
the user mix with Sessions that need nothing. Only the first ten rows get a
quick number, so a working Session low in the list can have no number at all.
The reference screenshot shows this: the working `spec-kit` Session renders as
`-` and the user cannot reach it with a number key.

The focused view hides every Session that needs no monitoring and no input.
The remaining rows get numbers from 1, so the user jumps between them with one
key each.

Full view today (grouped arrangement, from the reference screenshot):

```
[v12mac]
  v12x
     1. dev
 ⚙   2. feat/omniscient...      (working)
 ⚙   3. feat/omniscient...      (working)
     4. main
[v12dev]
  v12x
     5. feat/omniscient...
[ramhorn]
  SAGA-sdk
     6. main [disconnected]
oh-my-pi
     7. main
claude-code-ide.el
 ▌   8. main                    (active Session)
.spacemacs.d-30
     9. master
dotfiles_new
    10. master
spec-kit
 ⚙    - main                    (working, no quick number)
```

Focused view of the same Sessions:

```
[v12mac]
  v12x
 ⚙   1. feat/omniscient...
 ⚙   2. feat/omniscient...
spec-kit
 ⚙   3. main
```

The active Session `8. main` is absent, because it has no status that needs
the user and it did not enter the focused view while active.

## Clarifications

### Session 2026-10-01

- Q: In the focused view, should the Session you are currently in always
  appear, even when it is not working and not waiting? → A: No. The active
  Session appears only when it was in the focused set during its current
  activation. The reference screenshot therefore shows three rows, not four.
- Q: Should a fresh Emacs be able to start with the focused view already on?
  → A: Yes. A customize setting selects the startup view and defaults to off.
  `f` changes the view for the running Emacs only and never writes the
  setting, the same pattern as the `V` detail view.

## User Scenarios & Testing

### User Story 1 - See only the Sessions that need me (Priority: P1)

The user presses `f` in the manager sidebar. The sidebar hides every Session
that is not working and not waiting for the user. Pressing `f` again restores
the full list.

**Why this priority**: This is the core of the feature. Without the filter,
nothing else in this spec has a purpose.

**Independent Test**: Open a sidebar with Sessions in mixed states. Press `f`
and compare the visible rows with the set of Sessions that have a monitored
status. Press `f` again and compare with the full-view baseline.

**Acceptance Scenarios**:

1. **Given** the focused view is off, **When** the user presses `f`, **Then**
   the sidebar shows only Sessions with a monitored status: `working`,
   `needs-input`, `failed`, `done`, or output-idle (idle with unseen output).
   A Session whose agent state is the acknowledged `idle` state, or that has
   no status, is hidden.
2. **Given** the focused view is on, **When** the user presses `f`, **Then**
   the sidebar shows every Session exactly as the full view did before.
3. **Given** the user presses `f`, **When** the view changes, **Then** the
   echo area reports whether the focused view is now on or off.
4. **Given** the focused view is on, **When** a hidden Session starts working
   or starts to wait for the user, **Then** that Session appears at the next
   sidebar render without a user action.
5. **Given** the focused view is on, **When** no Session has a monitored
   status, **Then** the sidebar shows one line that states that no Session
   needs attention, and no Session rows.
6. **Given** the user never presses `f` and never changes the setting,
   **Then** the sidebar behaves exactly as it does today.
7. **Given** the startup setting is on, **When** the user opens a sidebar in a
   fresh Emacs, **Then** the focused view is on with no key press.
8. **Given** the user presses `f`, **Then** the startup setting keeps its old
   value, and an Emacs restart returns to the view that the setting selects.

---

### User Story 2 - Jump with low numbers (Priority: P1)

In the focused view, the visible Session rows are numbered from 1 in display
order. Each number key switches to the row that shows that number.

**Why this priority**: The user wants the low numbers so that one key reaches
each monitored Session. A filter that kept the old numbers would not deliver
this.

**Independent Test**: Render the reference set of Sessions in the focused view.
Press `1`, `2`, and `3`, and check that each key switches to the row that shows
the same number.

**Acceptance Scenarios**:

1. **Given** the focused view shows three Sessions, **Then** their rows show
   the numbers 1, 2, and 3 in display order.
2. **Given** the focused view is on, **When** the user presses a number key,
   **Then** the switch goes to the visible row with that number, both with
   and without keeping focus in the sidebar.
3. **Given** a Session had no quick number in the full view, **When** it
   appears in the focused view within the first ten rows, **Then** it gets a
   number.
4. **Given** the focused view is on, **When** the user presses a number larger
   than the count of visible rows, **Then** no switch happens.
5. **Given** a Session leaves the focused view, **When** the sidebar renders
   again, **Then** the remaining rows are numbered from 1 with no gaps.

---

### User Story 3 - Handled Sessions leave on their own (Priority: P1)

The user switches to an idle or finished Session. The switch acknowledges the
Session, as it does today: output-idle state clears, and a `done` or `failed`
result becomes the acknowledged `idle` state. The Session stays visible while
the user works in it. When the user switches to another Session, the handled
Session leaves the focused view.

**Why this priority**: Without this rule, a Session that the user already
handled would vanish under the user, or would stay forever and fill the list
again. The user named this rule explicitly.

**Independent Test**: Mark one Session idle. Switch to it with the focused view
on, then switch to a second Session. Check the visible rows after each step.

**Acceptance Scenarios**:

1. **Given** an output-idle, `done`, or `failed` Session is in the focused
   view, **When** the user switches to it, **Then** the switch acknowledges
   it, and the Session stays in the focused view as the active Session.
   Its quick number stays the same.
2. **Given** that Session is active and has no monitored status, **When** the
   user switches to another Session, **Then** the first Session leaves the
   focused view.
3. **Given** a Session is active and in the focused view, **When** it gets a
   monitored status again before the user leaves, **Then** it stays in the
   focused view after the user leaves.
4. **Given** the user clears the idle state of all Sessions at once, **Then**
   every Session that now has no monitored status leaves the focused view,
   except the active Session if it was in the focused view.
5. **Given** the active Session never had a monitored status during its
   current activation, **Then** it does not appear in the focused view.
6. **Given** a `needs-input` or `working` Session is in the focused view,
   **When** the user switches to it and then to another Session without a
   status change, **Then** the first Session stays in the focused view,
   because the switch does not acknowledge these two states.

---

### User Story 4 - Keep host and project context (Priority: P2)

A visible remote Session still shows its host and project, for example
`[v12mac]` and `v12x`, so the user knows where each Session runs.

**Why this priority**: Two remote Sessions can share a branch name on
different hosts. Without the host and project, the user cannot tell the rows
apart. The filter is still usable without this story, so it ranks below the
filter and the numbers.

**Independent Test**: Render remote and local Sessions in the focused view, in
both the grouped and the flat arrangement. Check the host and project text for
each visible Session.

**Acceptance Scenarios**:

1. **Given** the grouped arrangement and the focused view are on, **Then** each
   visible Session appears under its host heading and project heading.
2. **Given** the grouped arrangement and the focused view are on, **When** a
   host or project has no visible Session, **Then** its heading does not
   appear.
3. **Given** the flat arrangement and the focused view are on, **Then** each
   visible remote Session row keeps the host and project label that the flat
   view shows today.
4. **Given** the focused view is on, **When** the user switches between the
   grouped and flat arrangements, **Then** the filter stays on in both.

---

### Edge Cases

- A Session is disconnected: it has no live terminal, so the sidebar shows no
  status for it, and it stays hidden. It appears again when a reattach gives
  it a monitored status.
- The user switches to a hidden Session through a command outside the focused
  rows: the Session becomes active but stays hidden, because it has no
  monitored status. The sidebar then has no active-row marker. This follows
  the clarification that being active alone does not earn a row.
- The active Session finishes a turn while the user watches it: the result
  becomes the acknowledged `idle` state at once, so it shows no `done` status.
  It stays visible under FR-003 because it was `working` during this
  activation, and it leaves when the user switches away.
- More than ten Sessions have a monitored status: the first ten visible rows
  get numbers, and the rest render with `-`, as in the full view today.
- Sessions change status while the sidebar is open: the visible rows follow the
  next sidebar render. The feature adds no timer of its own.
- Row navigation, project navigation, the next and previous priority-Session
  commands, and the row-pick command: they act only on visible rows while the
  focused view is on.
- The user presses `f` outside the manager sidebar: the binding belongs to the
  sidebar, so other buffers are unaffected.
- The pin-order editor: it keeps listing every Session, because it reorders the
  full list.
- A sidebar for one repository and the global sidebar are both open: the
  focused view applies to both, because it is one global choice.

## Requirements

### Functional Requirements

- **FR-001**: The manager sidebar MUST support a focused view that shows only
  Sessions in the focused set, defined by FR-002 and FR-003.
- **FR-002**: A Session MUST be in the focused set when it has a monitored
  status: `working`, `needs-input`, `failed`, `done`, or output-idle. The
  acknowledged `idle` agent state and the absence of any status MUST NOT
  count as a monitored status.
- **FR-003**: The active Session MUST stay in the focused set while it remains
  active, if it was in the focused set at any time during its current
  activation. It MUST leave the focused set when another Session becomes
  active and it has no monitored status.
- **FR-004**: A Session that was never in the focused set during its current
  activation MUST NOT appear only because it is active.
- **FR-005**: In the focused view, quick numbers MUST count visible Session rows
  from 1 in display order. The cap of ten numbered rows stays the same.
- **FR-006**: In the focused view, every quick-number switch command, in the
  sidebar or elsewhere, MUST switch to the visible row that shows that number.
  A number with no visible row MUST do nothing.
- **FR-007**: The focused view MUST keep the display order of the current
  arrangement and sort. It removes rows and never reorders them.
- **FR-008**: In the grouped arrangement, the focused view MUST show the host
  heading and project heading of each visible Session. It MUST omit headings
  that have no visible Session.
- **FR-009**: In the flat arrangement, the focused view MUST keep each row
  label, including the host and project text of remote Sessions.
- **FR-010**: The package MUST provide an interactive command that turns the
  focused view on or off and reports the new state in the echo area.
- **FR-011**: The command MUST be bound to `f` in the manager sidebar keymap,
  and MUST NOT change any existing binding.
- **FR-012**: While the focused view is on, the sidebar MUST show that the
  focused view is on, so that a short list does not look like lost Sessions.
- **FR-013**: When the focused set is empty, the sidebar MUST show a single line
  that states that no Session needs attention.
- **FR-014**: With the focused view on, row navigation, project navigation,
  priority-Session navigation, and the row-pick command MUST act only on
  visible rows.
- **FR-015**: Turning the focused view on or off MUST NOT change the active
  Session, the window layout, Session status, or keyboard focus.
- **FR-016**: Turning the focused view on or off MUST NOT clear any idle state
  or acknowledge any result.
- **FR-017**: The focused view MUST be one global choice for the running Emacs.
  A customize setting MUST select the view at startup and MUST default to off.
  The `f` command MUST NOT write the setting, and the manager state file MUST
  NOT store the view. Changing the setting through the customize interface
  MUST update an open sidebar without a manual refresh.
- **FR-018**: Local and remote Sessions MUST follow the same focused-set rules.
  The focused view MUST NOT issue any network or SSH request.
- **FR-019**: The pin-order editor MUST keep listing every Session.

### Key Entities

- **Monitored status**: A Session status that needs the user to watch or act:
  `working`, `needs-input`, `failed`, `done`, or output-idle. The sidebar
  already shows each one with a glyph and a row color. A switch to the
  Session acknowledges output-idle, `done`, and `failed`. It does not
  acknowledge `working` or `needs-input`.
- **Focused set**: The Sessions with a monitored status, plus the active
  Session when FR-003 keeps it.
- **Activation**: The period from the moment a Session becomes active to the
  moment another Session becomes active.
- **Focused view**: The sidebar view that renders only the focused set,
  numbered from 1.
- **Full view**: The sidebar view that renders every Session. This is the
  sidebar behavior today.
- **Focused view setting**: The customize setting that selects the view at
  startup. Defaults to off. The `f` toggle changes the live view without
  writing this value.

## Success Criteria

### Measurable Outcomes

- **SC-001**: With the reference Sessions from the screenshot, the focused view
  shows exactly three Session rows, numbered 1 to 3, under the headings
  `[v12mac]`, `v12x`, and `spec-kit`.
- **SC-002**: The user reaches any Session with a monitored status in one key
  press, when ten or fewer Sessions have a monitored status.
- **SC-003**: After the user handles an idle Session and switches away, that
  Session is absent from the focused view at the next sidebar render in 100%
  of cases.
- **SC-004**: A user who never presses `f` sees no change: the sidebar renders
  identically to the previous release.
- **SC-005**: Turning the focused view on or off preserves the active Session,
  the window layout, and every Session status in 100% of toggles.
- **SC-006**: The full batch quality gate passes: every file byte-compiles with
  no unexpected warnings, and the ERT suite reports all tests passed.

## Assumptions

- "Need monitoring or input" means the statuses the sidebar already marks:
  `working`, `needs-input`, `failed`, `done`, and output-idle. The feature
  adds no new status source.
- The active Session in the screenshot (`8. main`) has no monitored status and
  is not in the expected three rows. So being active does not by itself put a
  Session in the focused set. The user's rule about idle Sessions shows that an
  active Session stays only after it was in the focused set.
- The existing switch behavior acknowledges a Session when the user switches
  to it. This feature relies on that behavior and does not change it.
- "Still show `[v12mac]` `v12x`" means the focused view keeps the host and
  project context that the current arrangement shows. It does not mean a new
  label format.
- The existing sidebar refresh triggers are enough. Status changes already
  cause a sidebar render.
- Renumbering after a Session leaves is expected. The user wants low numbers
  more than stable numbers.

## Dependencies

- The manager sidebar row renderer and its quick-number assignment.
- The per-Session status that the sidebar already shows: CLI-reported agent
  state and output-idle tracking.
- The switch path that clears idle state on a switch.
- The manager sidebar keymap, which currently leaves `f` unbound.

## Out of Scope

- New status sources or new status kinds.
- Storing the live `f` state across Emacs restarts.
- A focused version of the pin-order editor.
- Notifications outside the sidebar.
