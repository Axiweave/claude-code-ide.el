# Feature Specification: Fork into a Sibling Session with `/fork spawn`

**Feature Branch**: `022-fork-spawn`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "I want a /fork spawn command; that do pure fork but not sending extra info"

## Background

Spec 021 added `/spawn <request>`. It sends the request to the model, and the model picks one of four modes and writes the start content. One of those modes is fork: Sibling Session B starts with a copy of A's whole conversation and waits for the user.

To get a plain fork today, the user must type a request and wait for a model turn. That turn costs time and tokens, the model can pick the wrong mode, and A's conversation gets the request, the tool call, and the tool result.

`/fork` already has subcommands that open the fork in a new terminal place: `/fork pane` and `/fork window`. This feature adds one more subcommand, `/fork spawn`. It opens the fork as a Sibling Session in its own zmx session, with no model turn and no extra message in A or in B.

Terms come from spec 021: **Session A** (the Session where the command runs), **Sibling Session** or **B** (the new Session), **parent link**, and **spawn announcement**.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fork the current conversation into a new Session (Priority: P1)

The user works in Session A in Emacs and wants a second Session that knows everything A knows, for example to try another approach. The user types `/fork spawn`. omp creates B with a copy of A's conversation at once. Emacs attaches B and switches to it, and B waits for the user's next message.

**Why this priority**: This is the whole request. It gives a fork with one command and no model turn.

**Independent Test**: In a local zmx-backed omp Session with a few turns, run `/fork spawn`. Confirm that a new row and buffer appear, that B shows A's conversation and waits for input, and that A's conversation has no new message.

**Acceptance Scenarios**:

1. **Given** a local zmx-backed omp Session A with a saved conversation, **When** the user runs `/fork spawn`, **Then** omp creates B in a new zmx session with a copy of A's whole conversation, and Emacs attaches B and adds its row.
2. **Given** a `/fork spawn` completes, **When** the user looks at B, **Then** B shows A's conversation, has sent nothing to the model, and waits for input.
3. **Given** a `/fork spawn` completes, **When** the user looks at A, **Then** A's conversation and context have no new message, and A shows B's name as a status line only.
4. **Given** the Emacs switch option from spec 021 is on (the default), **When** a `/fork spawn` completes, **Then** Emacs shows B. With the option off, Emacs adds B's row and keeps the selected window and buffer.
5. **Given** A runs in a directory, **When** a `/fork spawn` completes, **Then** B runs in the same directory.

---

### User Story 2 - Remove a forked Session (Priority: P2)

The user is done with a B that `/fork spawn` created. In A, the user runs `/despawn` and picks B. omp ends B the same way as for any other Sibling Session.

**Why this priority**: Without the parent link, forked Sessions collect in the manager and only Stop can end them.

**Independent Test**: Run `/fork spawn`, then `/despawn` in A. Confirm that B is in the list, and that ending it removes its zmx session, row, and buffer.

**Acceptance Scenarios**:

1. **Given** a B that `/fork spawn` created from A, **When** the user runs `/despawn` in A, **Then** B is in the list of children, and ending it gives the same result as ending a B from `/spawn`.

---

### User Story 3 - Fork a remote Session (Priority: P3)

Session A runs on a remote host. The user runs `/fork spawn` there. omp creates B on the same host, and Emacs attaches B under that host.

**Why this priority**: Constitution principle VI requires remote parity, and `/spawn` already works for remote Sessions.

**Independent Test**: Attach a remote zmx-backed omp Session, run `/fork spawn`, and confirm that B appears under the same host with A's conversation.

**Acceptance Scenarios**:

1. **Given** a remote zmx-backed omp Session A on an approved host, **When** the user runs `/fork spawn`, **Then** omp creates B on that host and Emacs attaches B under that host.

---

### Edge Cases

- **A outside zmx.** B could get no parent link. omp refuses with a message that names the reason and creates nothing, the same as `/spawn`.
- **A started with a key on its command line.** The zmx session list prints B's command line, so the key would leak. omp refuses with the same message as `/fork pane`.
- **A has no saved conversation.** omp refuses with a message that names the reason and creates nothing.
- **A works on a turn.** omp asks the same question as `/fork pane`: B may not include the partial response. When the user answers no, omp creates nothing. When the user answers yes, B gets the conversation that is saved at that moment, and A's turn keeps running.
- **Extra text after `/fork spawn`.** omp shows the `/fork` usage message and creates nothing. `/fork spawn` takes no request. A user who wants B to start with a message uses `/spawn`.
- **B fails to start.** omp shows the zmx error in A, sends no announcement, and leaves no zmx session behind.
- **No Emacs attached to A.** omp still creates B and shows B's name in A. The user can attach B later with the existing attach commands.
- **A `/spawn` window is open.** `/fork spawn` does not use the spawn window or the model, so it runs and creates its one B. The open `/spawn` request still creates its own B.
- **A is in vibe mode.** omp refuses with "Exit vibe mode first." and creates nothing, the same as every other `/fork` form.
- **Many forks.** Each `/fork spawn` creates one new B with its own name. omp does not limit how many forks one Session makes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: omp MUST provide `/fork spawn` as a subcommand of `/fork`, next to `pane` and `window`, and MUST show it in the `/fork` subcommand list and usage message.
- **FR-002**: `/fork spawn` MUST create one Sibling Session B whose conversation is a copy of A's whole saved conversation, with the same result as `/fork` and as the fork mode of `/spawn`.
- **FR-003**: `/fork spawn` MUST NOT run a model turn, MUST NOT open the spawn window, and MUST NOT add a message, tool call, or tool result to A's conversation.
- **FR-004**: B MUST start with no new message: no opening prompt, no handoff note, and no summary. B MUST send nothing to the model and MUST wait for the user.
- **FR-005**: omp MUST create B the same way as a `/spawn` B: in a new zmx session on A's host, in A's directory, with a package-recognized name, with the parent link to A, and with A's Agent command, profile, and model. B MUST NOT inherit A's zmx session name, name prefix, or Emacs buffer.
- **FR-006**: After a successful creation, omp MUST write the same spawn announcement as `/spawn` and MUST show B's name in A as a status line. Emacs MUST attach B and apply the spec 021 switch option with no package change.
- **FR-007**: omp MUST refuse `/fork spawn` when A runs outside zmx, when A started with a key on its command line, or when A has no saved conversation. Each refusal MUST name its reason, create nothing, and send no announcement.
- **FR-008**: When A works on a turn, omp MUST ask the same confirmation as `/fork pane` before it creates anything. A declined confirmation MUST create nothing.
- **FR-009**: When creation fails, omp MUST show the error in A, MUST NOT send an announcement, and MUST NOT leave a zmx session behind.
- **FR-010**: `/fork spawn` MUST reject extra text with the `/fork` usage message and create nothing.
- **FR-011**: `/despawn` in A MUST list a B from `/fork spawn` and end it the same way as a B from `/spawn`.

### Key Entities

- **Forked Sibling Session**: a Sibling Session (spec 021) that starts with a copy of A's conversation and no new message. It carries the same parent link as any other Sibling Session.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From `/fork spawn` to a visible, usable B buffer takes one command and zero manual steps in Emacs, for local and for remote Sessions.
- **SC-002**: On a local host, B appears and has focus within 5 seconds after the user runs `/fork spawn`.
- **SC-003**: In 10 `/fork spawn` runs, A's conversation gains zero messages, B starts with zero new messages, and zero model requests start in A or in B before the user types.
- **SC-004**: In 10 `/fork spawn` runs, B's conversation matches A's saved conversation at the moment of the command in 100% of runs.
- **SC-005**: `/despawn` in A lists 100% of the Sessions that `/fork spawn` created from A and still run.
- **SC-006**: The package test gate and the omp test suite pass with zero unexpected results.

## Assumptions

- The work is in omp only. The package already attaches any announced Sibling Session (spec 021, FR-010 to FR-013), so it needs no change.
- `/fork spawn` does not ask the `spawn.confirm` question. The user names the exact action, as with `/fork pane`, so a confirmation adds nothing.
- B runs in A's directory. `/fork spawn` takes no directory, worktree, or model argument. `/spawn` covers those cases.
- The subcommand name `spawn` does not collide with the existing `/fork` subcommands `pane`, `window`, and `tab`.
