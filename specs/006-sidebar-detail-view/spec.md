# Feature Specification: Sidebar Detail View

**Feature**: `006-sidebar-detail-view`

**Created**: 2026-09-08

**Status**: Draft

**Input**: User description: "create a new detailed view; off by default with defcustom and a toggle command and bind to V. essentially; add to title under [numbered row list]. use different color face / color for title dimmer like cmux. can you research first; how each proj in refs/ get description of session? along side title?"

## Overview

The manager sidebar shows one line per Session. A user with several Sessions in
one Project sees near-identical rows, because the row label comes from the
directory name. The Session already carries a terminal title that names the
current work. This feature shows that title on a second, dimmer line under each
Session row, and it stays off until the user turns it on.

Compact view today:

```
 1. .spacemacs.d-30
 2. [ramhorn] repo
 3. claude-code-ide.el
 4. workspace-setup
 5. oh-my-pi
```

Detail view:

```
 1. .spacemacs.d-30
    title 1
 2. [ramhorn] repo
    title 2
 3. claude-code-ide.el
    title 3
 4. workspace-setup
 5. oh-my-pi
```

Rows 4 and 5 have no title, so they keep one line each.

## Clarifications

### Session 2026-09-08

- Q: What text is the "description" on the second line? → A: The Session
  terminal title that the package already records. The refs/ survey (see
  [research.md](research.md)) found no project with a separate description
  field. Of the five projects that do label a Session, cmux and orca derive
  the label from the transcript and herdr takes it from the agent-reported
  terminal title. t3code generates a title with a model. plannotator stores a
  static label built from CLI arguments, and the two Emacs projects show no
  label at all. This package already captures the terminal title per Session,
  which is the herdr source and the cheapest one available here.
- Q: Does the detail line replace the compact row? → A: No. It adds a line
  under the existing row. The existing row keeps its current content and
  alignment.
- Q: Is the setting global or per sidebar scope? → A: Global. The user asked
  for one setting and one toggle, not per-scope state.
- Q: On an Emacs restart, does the saved toggle state or the customize setting
  decide the view? → A: The customize setting is the only stored value. `V`
  changes the view for the running Emacs only and never writes a stored value.
  A restart always starts from the customize setting. The manager state file
  stores no view, so the two can never disagree.
- Q: With the detail view on, should a Session that has no terminal title show
  a fallback such as its directory path? → A: No fallback. The Session keeps a
  single row. The second line means the terminal title and nothing else. A
  fallback would repeat what the row label already derives from, and ragged
  row height is the honest signal that a Session has no title.
- Q: Should the title line start flush left, level with the Session number, or
  indent under the Session name? → A: Indent to the Session name column, the
  same alignment the row label already uses. This keeps the title subordinate
  to its row and out of the number column, at a cost of about four columns of
  width. It differs from the original sketch, which showed the title flush
  left.
- Q: Does the detail view also apply to the pin-order editor that `E` opens?
  → A: No. The sidebar only. The editor keeps its current behavior and its own
  `pin-order-show-titles` setting. The editor maps one line to one Session for
  reordering, so a second line per Session would break it. The two title
  displays stay separate, with separate controls.

## User Scenarios & Testing

### User Story 1 - Turn the detail view on and off (Priority: P1)

The user presses `V` in the manager sidebar and each Session row that has a
title gains a second, dimmer line under it. Pressing `V` again returns the
sidebar to the compact one-line rows.

**Why this priority**: This is the feature's main purpose, and it is the whole
observable behavior the user asked for.

**Independent Test**: Open a sidebar with at least two Sessions that have
terminal titles. Press `V` twice and compare the rendered buffer against the
compact baseline.

**Acceptance Scenarios**:

1. Given the detail view is off, the sidebar renders exactly the current
   compact rows, one line per Session.
2. Given the detail view is off, pressing `V` adds a detail line under every
   Session row that has a non-empty title.
3. Given the detail view is on, pressing `V` removes every detail line and
   restores the compact rows.
4. Given the detail view is on, the toggle reports the new state to the user.
5. Given the detail view is on and the user switches between the flat and
   grouped arrangements, detail lines appear in both.
6. Given the detail view was turned on with `V`, an Emacs restart returns the
   sidebar to the view named by the customize setting, discarding the toggle.
7. Given the user never presses `V` and never customizes the setting, the
   sidebar behaves exactly as it does today.

---

### User Story 2 - Read the title without losing the row (Priority: P1)

The user can tell the Session row apart from its detail line at a glance,
because the detail line uses a dimmer face than the row label.

**Why this priority**: A second line that looks like a row is worse than no
second line, because the user can no longer count Sessions.

**Independent Test**: Render a sidebar with the detail view on and inspect the
face of the row label and of the detail line at each position.

**Acceptance Scenarios**:

1. The detail line renders in a dedicated dim face, distinct from the face of
   the Session row label.
2. The detail line is not selectable as a Session: navigation commands move
   between Session rows and never land on a detail line.
3. The detail line carries the same Session identity as the row above it, so a
   mouse click or a command issued on the detail line acts on that Session.
4. A Session status highlight (working, idle, needs input, done, current) marks
   the Session row and does not repaint the detail line as a status row.
5. The detail line indents to the Session label column, so titles line up under
   each other.
6. A title longer than the sidebar width is truncated to a single line. The
   full title stays available through the row tooltip.
7. A title that contains newlines or carriage returns renders as a single line.

---

### User Story 3 - Set the default without pressing a key (Priority: P2)

The user sets a persistent preference so that every new Emacs session starts
with the detail view already on, or keeps it off.

**Why this priority**: The user asked for a setting as well as a toggle. It is
lower priority than the toggle, because the toggle alone delivers the feature.

**Independent Test**: Set the preference to on, start a fresh sidebar without
pressing `V`, and confirm detail lines appear.

**Acceptance Scenarios**:

1. The preference defaults to off.
2. With the preference on, a newly opened sidebar shows detail lines with no
   key press.
3. Changing the preference through the customize interface updates an open
   sidebar without a manual refresh.
4. A toggle press during a session changes the view for that running Emacs
   only. It does not write the setting, and the setting keeps its old value in
   the customize interface.

---

### Edge Cases

- A Session has no title, because its terminal backend does not report one:
  the Session keeps a single compact row, and no blank line appears.
- A Session title is an empty string or only whitespace: treated as no title.
- Every Session lacks a title: the detail view produces a sidebar identical to
  the compact view, and the toggle still reports its state.
- A Session is remote and disconnected: it renders like any other Session. It
  shows its remembered title if one exists, and the toggle triggers no network
  request.
- A Session title changes while the detail view is on: the detail line shows the
  new title after the next sidebar render, without a user action.
- The grouped view renders group headings: headings gain no detail line.
- The sidebar is very narrow: the detail line truncates instead of wrapping, so
  the row-to-Session count stays correct.
- The user presses `V` outside the manager sidebar: the binding belongs to the
  manager, so other buffers are unaffected.

## Requirements

### Functional Requirements

- **FR-001**: The manager sidebar MUST support two views: a compact view of one
  line per Session, and a detail view that adds one line under each Session
  row.
- **FR-002**: The compact view MUST stay byte-identical to today's rendering,
  including the active marker, the status gutter, the right-aligned Session
  number, and the label column.
- **FR-003**: The detail line content MUST be the Session's recorded terminal
  title, normalized to a single line, with the leading agent status glyphs
  removed. A CLI prefixes its title with one glyph for itself and one for its
  state, for example `π > ` when waiting and `π ⠋ ` when working. The line
  MUST show the text after those glyphs.
- **FR-004**: A Session with no title, an empty title, or a whitespace-only
  title MUST render with no detail line and no fallback content.
- **FR-005**: The detail line MUST render in a dedicated dim face that the user
  can customize, visually subordinate to the Session label.
- **FR-006**: A Session status highlight MUST apply to the Session row only and
  MUST NOT present the detail line as a status row.
- **FR-007**: The detail line MUST start at the Session label column, the same
  column the row label starts at, so that titles align under each other and
  never occupy the Session number column.
- **FR-008**: A detail line MUST NOT be a navigation target. Session-row
  navigation, project navigation, and Session numbering MUST behave as they do
  in the compact view.
- **FR-009**: A detail line MUST resolve to the same Session as the row above
  it for click and command purposes.
- **FR-010**: The package MUST provide a persistent user setting that selects
  the view at startup, defaulting to the compact view.
- **FR-011**: The package MUST provide an interactive command that switches the
  view and reports the resulting view to the user.
- **FR-012**: The command MUST be bound to `V` in the manager sidebar keymap,
  and MUST NOT change any existing binding.
- **FR-013**: The view choice MUST apply to both the flat and grouped
  arrangements, and to repo-local and global sidebars alike.
- **FR-014**: The view choice MUST NOT persist in the manager state file. Only
  the customize setting persists across Emacs restarts.
- **FR-015**: Switching the view MUST NOT change the active Session, the Emacs
  window layout, the selected Session row, or keyboard focus.
- **FR-016**: The feature MUST NOT read agent transcript files and MUST NOT
  issue any network or SSH request to obtain a title.
- **FR-017**: A title truncated in the detail line MUST remain fully readable
  through the existing row tooltip.
- **FR-018**: The feature MUST behave the same on every supported terminal
  backend. A backend that reports no title yields Sessions with no detail
  line, which is a title-availability limit and not a per-backend view
  difference.

### Key Entities

- **Session row**: The existing one-line entry for a Session. Carries the
  active marker, status gutter, Session number, and label. Selectable.
- **Detail line**: An added, non-selectable line under a Session row. Shows the
  Session title in a dim face. Present only when the Session has a title.
- **Session title**: Text the terminal reports for a Session and the package
  already stores per Session. May be absent.
- **View preference**: The single persistent user setting that selects the view
  at startup. Defaults to the compact view. A toggle changes the live view
  without writing this value.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A user who has never heard of this feature sees no change: with
  default settings, the sidebar renders identically to the previous release.
- **SC-002**: One key press switches the view, and the switch is visible in the
  sidebar immediately.
- **SC-003**: Given several Sessions in one Project, a user can name the work in
  each Session from the sidebar alone, without switching to a terminal.
- **SC-004**: In the detail view, a user can still count and address Sessions
  by number, because every numbered row is a Session and no detail line is
  numbered or selectable.
- **SC-005**: Switching the view preserves the active Session and the Emacs
  window layout in 100% of switches.
- **SC-006**: Switching the view and rendering the detail view complete with no
  user-visible delay, and cause zero network requests.
- **SC-007**: The full batch quality gate passes: every file byte-compiles with
  no unexpected warnings, and the ERT suite reports all tests passed.

## Assumptions

- The Session terminal title is the description the user wants. The refs/
  survey in [research.md](research.md) supports this narrowly: herdr labels a
  pane from the agent-reported terminal title, which is the same source this
  package already records per Session. cmux and orca reach a similar label by
  parsing a transcript, at much higher cost. No surveyed project keeps a
  description separate from its title.
- A title is available only from terminal backends that report one. This
  feature adds no new title source and no fallback content. Sessions without a
  title keep a single row, which is the graceful path rather than an error.
- "Dimmer like cmux" means a foreground blended toward the background. The
  Emacs equivalent is a face that inherits from `shadow`, kept customizable so
  a user can match a theme.
- The view is one global setting, not per sidebar scope and not manager
  state, because the user asked for one setting and one toggle. This follows
  the existing display flag for Session order suffixes, which is a plain
  setting read at render time.
- The existing sidebar refresh triggers are enough. The detail line reads a
  field the package already keeps current, so this feature adds no timer and no
  polling.
- Truncation is preferred over wrapping, because a wrapped detail line would
  break the fixed alignment the compact view relies on.
- The feature reuses the existing manager face group and keymap. It stores no
  new state and introduces no new runtime dependency.

## Dependencies

- The manager sidebar row renderer.
- The per-Session title field the package already records from the terminal.
- The manager sidebar keymap, which currently leaves `V` unbound.

## Out of Scope

- Generating a title for a Session whose terminal reports none, for example by
  summarizing a prompt with a model or by reading an agent transcript.
- A user-editable per-Session description separate from the terminal title.
  Custom Session names already exist for that purpose.
- A third line or a metadata row, for example model, token count, or elapsed
  time.
- Changing the compact view, the status faces, the gutter glyphs, or any
  existing key binding.
- Changing the pin-order editor that `E` opens, or its own
  `pin-order-show-titles` setting. That editor maps one line to one Session for
  reordering, so it stays single-line.
- Publishing titles to other tools or exposing a title feed for external use.
