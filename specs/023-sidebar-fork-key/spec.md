# Feature Specification: Fork a Session from the Sidebar with `S`

**Feature Branch**: `023-sidebar-fork-key`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "remove S from keybinding in cc-ide sidebar; make S do the following -> fork the session! find a way to do it; either use or new fork spawn via escape sequence or what else info we have on session and launch with omp command line; should work over remote"

## Background

In the manager sidebar, `S` starts a new sibling Session with the permissions bypass. The user does not use that key and wants `S` to fork the Session on the selected row instead.

Spec 022 added `/fork spawn` to omp. It copies Session A's whole conversation into a new Sibling Session B in its own zmx session, with no model turn and no new message. Emacs attaches B through the spawn announcement, local or remote. Today the user must switch to A and type the command.

This feature makes `S` on a sidebar row run that same fork for the row's Session, without a switch to A and without a change to what the user typed in A.

Terms come from specs 021 and 022: **Session A** (the Session on the selected row), **Sibling Session** or **B** (the new Session), **parent link**, **spawn announcement**, and **`/fork spawn`**.

## Clarifications

### Session 2026-11-01

- Q: When you press `S` on a Session that is working on a turn, what should happen? → A: omp forks at once without the question. B gets only the saved conversation, without the turn that still runs.
- Q: How should you learn about a refused `S` fork while you are in the sidebar? → A: Emacs shows "Fork request sent to <A>" in the echo area. A refusal shows only in A.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fork the Session at point (Priority: P1)

The user sees a Session in the sidebar and wants a second copy of it, for example to try another approach. The user moves to the row and presses `S`. B appears with A's whole conversation, Emacs attaches B, and B waits for the user's next message.

**Why this priority**: This is the feature. It replaces a switch to A and a typed command with one key.

**Independent Test**: Start a local omp Session, send two messages, go to the sidebar, and press `S` on its row. B appears as a new row with A's two exchanges, and A's conversation and draft do not change.

**Acceptance Scenarios**:

1. **Given** a connected local omp Session A with a saved conversation, **When** the user presses `S` on A's row, **Then** omp creates B with a copy of A's whole conversation, and Emacs attaches B and adds its row.
2. **Given** A has unsent text in its input, **When** the user presses `S` on A's row, **Then** A's unsent text is the same after the fork as before.
3. **Given** an `S` fork completes, **When** the user looks at A and B, **Then** neither Session has a new message, and no model request started in either one.
4. **Given** the Emacs switch option from spec 021 is on (the default), **When** an `S` fork completes, **Then** Emacs shows B. With the option off, Emacs adds B's row and keeps the selected window and buffer.

---

### User Story 2 - Fork a remote Session (Priority: P1)

Session A runs on a remote host and is attached in Emacs. The user presses `S` on its row. omp creates B on the same host, and Emacs attaches B under that host.

**Why this priority**: The user works on remote hosts most of the time, and the user asked for remote support.

**Independent Test**: Attach a remote omp Session, send a message, and press `S` on its row. B appears under the same host with A's conversation.

**Acceptance Scenarios**:

1. **Given** a connected remote omp Session A on an approved host, **When** the user presses `S` on A's row, **Then** omp creates B on that host, and Emacs attaches B under that host.

---

### User Story 3 - The old `S` start is gone from the sidebar (Priority: P2)

The user no longer gets the permissions-bypass start from the sidebar. The sidebar help and the sidebar dispatch menu show the new meaning of `S`.

**Why this priority**: The key must have one meaning. A stale menu entry or help text would start the wrong action.

**Independent Test**: Open the sidebar dispatch menu and the sidebar help. `S` shows the fork action, and no sidebar entry starts a Session with the permissions bypass.

**Acceptance Scenarios**:

1. **Given** the sidebar, **When** the user opens its dispatch menu, **Then** `S` names the fork action, and no entry starts a Session with the permissions bypass.
2. **Given** the start menus outside the sidebar, **When** the user opens them, **Then** their own skip-permissions entries still work as before.

---

### Edge Cases

- **No Session row at point.** The user is on a group header or an empty line. Emacs shows a message that names the reason and forks nothing.
- **The row is not an omp Session.** Only omp can fork with `/fork spawn`. Emacs shows a message that names the reason and forks nothing.
- **The row is disconnected.** Emacs has no terminal to A. Emacs shows a message that tells the user to reconnect first and forks nothing.
- **A works on a turn.** omp forks at once and asks no question. B gets A's saved conversation, without the turn that still runs. A's turn keeps running.
- **omp refuses the fork.** Examples: A runs outside zmx, A started with a key on its command line, A has no saved conversation, or A is in vibe mode. omp shows the same refusal in A as for a typed `/fork spawn`, and nothing is created. Emacs shows no other message after "Fork request sent to <A>".
- **A shows a dialog or a menu.** A user cannot type `/fork spawn` then either. omp does not answer, close, or type into that dialog. It creates nothing and shows a message that names the reason. An open `/spawn` window is not such a dialog: the fork runs, as spec 022 says for `/fork spawn`.
- **The user presses `S` twice fast.** Each press is one fork request. Two presses create two Bs, the same as two typed `/fork spawn` commands.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: In the manager sidebar, `S` MUST fork the Session on the selected row. The sidebar MUST NOT bind `S`, or any other key, to the permissions-bypass start any more.
- **FR-002**: The sidebar dispatch menu MUST show `S` with the fork action, and its key list MUST match the sidebar keys.
- **FR-003**: An `S` fork MUST create the same B as a `/fork spawn` typed in A: one new B with a copy of A's whole saved conversation, the parent link to A, no new message in A or B, and no model turn. FR-009 sets the only difference, which is the busy-turn question.
- **FR-004**: An `S` fork MUST NOT change A's unsent input text, and MUST NOT add text to it.
- **FR-005**: An `S` fork MUST work for a local A and for a remote A on an approved host. B MUST start on A's host, and Emacs MUST attach B under that host.
- **FR-006**: Emacs MUST attach B through the existing spawn announcement and MUST apply the spec 021 switch option.
- **FR-007**: When the row at point is not a connected omp Session, Emacs MUST show a message that names the reason and MUST NOT send a fork request.
- **FR-008**: Every refusal that omp gives for a typed `/fork spawn` MUST also apply to an `S` fork, with the same message in A.
- **FR-009**: When A works on a turn, an `S` fork MUST NOT ask a question. omp MUST fork at once from A's saved conversation, and A's turn MUST keep running.
- **FR-010**: The start menus outside the sidebar MUST keep their own skip-permissions entries unchanged.
- **FR-011**: omp MUST accept the fork request from A's terminal input and fork as `/fork spawn` does, without the busy-turn question. omp MUST read the request as one whole unit, MUST NOT put any part of it in A's input text, and MUST NOT pass it to an open dialog.
- **FR-012**: When A shows a dialog or a menu, omp MUST NOT fork. It MUST show a message that names the reason. An open `/spawn` window MUST NOT block the fork, as in spec 022.
- **FR-013**: After Emacs sends a fork request, it MUST show "Fork request sent to <A>" in the echo area, with A's Session name. Emacs MUST NOT wait for or report omp's result. A refusal shows only in A.

### Key Entities

- **Fork request**: a request from Emacs to Session A, sent through A's terminal input, to fork A as `/fork spawn` does, without the busy-turn question. It carries no text and no options. It is a new kind in omp's existing family of Emacs requests, which omp reads without a change to the input text.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From the sidebar, a fork of the Session at point takes one key press and zero other manual steps, for local and for remote Sessions.
- **SC-002**: On a local host, B appears in the sidebar within 5 seconds after the key press.
- **SC-003**: In 10 `S` forks, A's unsent input text is unchanged in 100% of runs.
- **SC-004**: In 10 `S` forks, A and B gain zero new messages, and zero model requests start before the user types.
- **SC-005**: Zero sidebar keys start a Session with the permissions bypass.
- **SC-006**: The package test gate and the omp test suite pass with zero unexpected results.

## Assumptions

- The fork runs in A's omp, as a `/fork spawn`. Emacs does not build its own omp command line. omp already holds what the fork needs (the session file, the model, the refusals), and Emacs does not know A's session file.
- Emacs sends the fork request through A's terminal input. That path already reaches A for local and remote Sessions. Emacs already sends requests of this kind to omp, for the prompt command, the prompt keyword, and the external editor.
- No fork request exists in omp today. The current request kinds change the input text, so none of them can carry the fork. This feature adds the new request kind to omp and tests it there.
- Text plus Return is not the route. It would replace or mix with A's unsent input text, and during a turn it would queue instead of fork.
- `S` asks no confirmation, also when A works on a turn. This differs from a typed `/fork spawn`, which asks during a turn. The user can end an unwanted B with `/despawn`.
- The permissions-bypass start leaves the sidebar only. The start menus outside the sidebar keep it.
- Local and remote `S` forks behave the same, as constitution principle VI requires. This feature has no remote difference.
