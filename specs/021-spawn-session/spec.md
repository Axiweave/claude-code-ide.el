# Feature Specification: Spawn and Remove Sibling Sessions from omp

**Feature Branch**: `021-spawn-session`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "omp -> send escape sequence to open a new omp session (not subagent); with our zmx stuff -> then cc-ide attach to it automatically. Do A for trigger: 1. fresh session, but support both, then based on what I ask, like guided-goal. 2. only slash command for now, but leave room for real tool; like guided-goal, only expose the tool when running that command. 3. make it a defcustom, default to switch to it. 4. keep the link but do not require a result back yet; no async subagent work yet, but leave room for it. Also think about removing a session."

## Background

omp subagents run inside the parent Agent process. They are hidden, the parent waits for them, and they end with their task. This feature adds a different kind of child: a **Sibling Session**. A Sibling Session is a full top-level omp Session with its own process, terminal, and zmx session. Emacs shows it as a normal Session row and buffer, and the user talks to it directly. It keeps running after its parent moves on or ends.

The feature has two directions:

- **Spawn.** The user asks omp in Session A for a new Session. omp creates Session B in zmx and tells the Emacs that shows A about it. That Emacs attaches B through its existing attach path.
- **Remove.** The user asks omp to end a Session. omp ends it, and Emacs removes the row and the buffer the same way as Stop.

Technical evidence for planning (escape-sequence channel, zmx creation behavior, reattach replay, environment inheritance) is in [research.md](research.md).

## Clarifications

### Session 2026-11-01

- Q: Which component starts Session B? → A: omp starts B in zmx. The escape sequence only tells Emacs that B exists. Emacs never starts a process because of terminal output.
- Q: What starts a spawn? → A: Only a user slash command for now. The spawn tool exists, but omp exposes it only while that command runs, the same way `/guided-goal` exposes the `goal` tool. A later change can expose the tool by default.
- Q: Does Emacs switch to Session B? → A: A user option controls this. The default switches to B.
- Q: Does the parent get a result back from B? → A: No. omp records the parent link when it creates B. No result travels back, and no wait exists. The link leaves room for this later.
- Q: Which form of A's context does a context-carrying B get? → A: Three forms exist: fork (a copy of A's whole conversation), fork with handoff (that copy plus a handoff note), and handoff summary (a new conversation that starts from a summary). The model picks one from the user's request, the same way it picks fresh (FR-003, FR-007).
- Q: Which Sessions can the remove command end? → A: Only Sessions that this Session spawned, found through the parent link. A Session ends itself with the existing `/exit`. FR-021 requires that `/exit` removes the row for local and remote Sessions (FR-014). Planning found that the package already does this for both.
- Q: Before omp creates B, must the user confirm the mode, directory, and opening prompt or handoff note? → A: An omp setting controls it. The default is off: the spawn call creates B at once. When on, omp shows the mode, the directory, and the content that B starts with, and asks yes/no first (FR-022).
- Q: When the request asks for B in a new git worktree, does the spawn create it? → A: Yes, the same way `/wt` creates one with default settings. B gets a new branch and worktree from A's current commit, with a copy of A's uncommitted changes. A keeps its checkout and its changes. When B needs a clean tree, the model says so in the opening prompt or handoff note, and B cleans its own worktree (FR-023).
- Q: When the remove command ends a child that runs in a worktree that the spawn created, what happens to that worktree and its branch? → A: omp follows `worktree.onExit`. `keep` (the default) keeps them. `ask` asks in A as part of the remove confirmation. `remove` deletes them only when the worktree is clean, on its branch, and not moved, and asks in every other case (FR-024).
- Q: When `ask.enabled` is off, the model cannot ask the FR-003 question. What does `/spawn` do? → A: The model picks the most likely mode and asks no question. The `spawn.confirm` setting is the only check (FR-003, FR-022).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Spawn a fresh Session from a request (Priority: P1)

The user works in Session A in Emacs. The user types the spawn command with a request, for example "start a session that fixes the flaky manager test". omp decides that the request needs a fresh Session, writes an opening prompt from the request, and creates Session B. Emacs attaches B and switches to it. B already works on the opening prompt.

**Why this priority**: This is the core of the request. It delivers a visible, interactive sibling Session with no manual attach.

**Independent Test**: Start a local zmx-backed omp Session in Emacs. Run the spawn command with a short request. Confirm that a new row and buffer appear, that Emacs shows the new buffer, and that the new Agent works on a prompt that matches the request.

**Acceptance Scenarios**:

1. **Given** a local zmx-backed omp Session A shown in Emacs, **When** the user runs the spawn command with a request for new, separate work, **Then** omp creates Session B in a new zmx session, Emacs attaches B, adds its row, and shows B.
2. **Given** the switch option is off, **When** a spawn completes, **Then** Emacs adds B's row and does not change the selected window or buffer.
3. **Given** a spawn completes, **When** the user looks at Session A, **Then** A is still running, its conversation has a short record of the spawn with B's name, and A's context is otherwise unchanged.
4. **Given** a request that names an existing directory on the same host, for example an existing worktree, **When** the spawn completes, **Then** B runs in that directory and Emacs files B's row under that directory's project.
5. **Given** A has uncommitted changes and the request asks for a new worktree, **When** the spawn completes, **Then** B runs in a new worktree on a new branch from A's current commit, with a copy of A's uncommitted changes. A's checkout and changes stay as they were.

---

### User Story 2 - Spawn a Session that keeps the current context (Priority: P2)

The user wants a new Session that continues from what A already knows, for example "hand this off to a new session and keep going there". omp decides from the request that B needs A's context and creates B with that context.

**Why this priority**: The user asked for fresh and context-carrying spawns. A fresh Session covers most delegation. The three context-carrying modes cover fork and handoff.

**Independent Test**: In a Session with a few turns of conversation, run the spawn command with a handoff request. Confirm that B starts with A's context and that A's own context does not change.

**Acceptance Scenarios**:

1. **Given** a Session A with conversation history, **When** the user asks for a Session that continues this work, **Then** B starts with A's context in the form that the model picked (FR-007), and A keeps its own history unchanged.
2. **Given** a request such as "fork this", "fork this and continue with the tests", or "hand off with a summary", **When** the spawn completes, **Then** B starts with a fork, a fork with a handoff note, or a handoff summary, to match the request.
3. **Given** a request that does not make the mode clear, **When** the spawn command runs, **Then** omp asks the user one question and creates no Session until the user answers.

---

### User Story 3 - Remove a Session from omp (Priority: P2)

The user is done with a Session that A spawned earlier. In A, the user runs the remove command and picks that child. omp ends the child's Agent and its zmx session. Emacs removes the row and closes the buffer the same way as Stop. A Session ends itself with the existing `/exit`.

**Why this priority**: Without removal, spawned Sessions collect in the manager. The user asked to include removal in this feature.

**Independent Test**: Spawn a Session B. Run the remove command for B. Confirm that B's Agent and zmx session end, that its row and buffer disappear from Emacs, and that Session A keeps running.

**Acceptance Scenarios**:

1. **Given** a Session that FR-014 allows as a target, **When** the user runs the remove command and confirms, **Then** its Agent and zmx session end, and Emacs removes its row and closes its buffer with the same result as Stop.
2. **Given** any target, **When** the user runs the remove command, **Then** omp asks for confirmation that names the target before it ends anything, the same way as the manager's confirmed Stop. When the target works on a turn, the question also names the running work.
3. **Given** the user declines the confirmation, **When** the question closes, **Then** nothing ends and the target keeps running.
4. **Given** no Emacs is attached when a removal runs, **When** the user later opens the manager, **Then** the removed Session does not appear as live or reattachable.
5. **Given** a remote target shown in Emacs, **When** the removal ends it, **Then** Emacs removes its row after the host confirms that the zmx session is gone. When the host cannot answer, the row stays as `[disconnected]`.

---

### User Story 4 - Spawn from a remote Session (Priority: P3)

Session A runs on a remote host. The user runs the spawn command there. omp creates B on the same host. Emacs attaches B as a remote Session under that host, with the same switch behavior as a local spawn.

**Why this priority**: Constitution principle VI requires remote parity. Remote Sessions are a main use of this package.

**Independent Test**: Attach a remote zmx-backed omp Session. Run the spawn command. Confirm that B appears under the same host and that its terminal works.

**Acceptance Scenarios**:

1. **Given** a remote zmx-backed omp Session A on a host in the approved host list, **When** the user spawns B, **Then** omp creates B on that host and Emacs attaches B under that host.
2. **Given** a remote Session A on a host that is no longer in the approved host list, **When** omp announces B, **Then** Emacs attaches nothing, shows one message that names the host and B, and B keeps running in zmx.

---

### Edge Cases

- **No Emacs attached to A.** omp still creates B and shows B's name in A. The announcement reaches no Emacs. The user can attach B later through the existing attach commands.
- **Two Emacs instances attached to A.** Each one gets the announcement. Each one attaches B once. One Emacs never attaches B twice.
- **Announcement text in ordinary output.** A file that A prints can contain the same escape sequence. Emacs acts only on an announcement in a live owned omp Session buffer. Emacs attaches only a zmx session that exists, that has a valid package name, and that runs a known Agent command. Emacs never runs a command because of the announcement.
- **Reattach to A.** A reattach does not repeat old announcements. A Session that the user removed or detached does not come back.
- **A outside zmx.** A has no zmx name, so B could get no parent link and the remove command could never end B. omp refuses every spawn mode with a message that names the reason, and creates nothing (FR-020).
- **B fails to start.** omp shows the zmx error in A, sends no announcement, and leaves no zmx session behind.
- **B fails to start after omp made a new worktree.** omp also removes that worktree and its branch. A failed spawn leaves no zmx session, no worktree, and no branch behind.
- **The user leaves the spawn command without a spawn.** The model ends a turn with no spawn call and no mode question, or the user switches Session. The spawn window closes, and A's tool set returns to its state before the command.
- **The user runs the spawn command while another guided command runs.** omp refuses and names the command that runs, the same way as the existing guided commands. omp also refuses a second spawn command while the first spawn window is open.
- **The model tries a second spawn.** The spawn window closed at the first spawn call, so the tool is not available. One command creates at most one Session.
- **The user declines a spawn confirmation.** With the confirmation setting on, the user answers no. omp creates nothing, sends no announcement, and the spawn window closes like after any other spawn call.
- **The `ask` tool is off.** With `ask.enabled` off, the model cannot ask the mode question. It picks the most likely mode from the request and spawns. Turn on the confirmation setting (FR-022) to check the mode before omp creates B.
- **Fork from an unsaved Session.** A has not saved its conversation yet. omp refuses both fork modes with a message that names the reason, and offers no fallback spawn.
- **A started with a key on its command line.** The zmx session list prints B's command line, so a key there leaks. omp refuses every spawn mode with a message that names the reason, the same way as `/fork`.
- **A Session tries to remove itself.** The remove command lists only children, so the Session is not a target. The user ends it with `/exit`, and FR-021 removes the row.
- **A has no live children.** The remove command shows a message that says so and ends nothing.
- **A was detached and reattached.** The parent link uses A's zmx name, which does not change. A still finds its children.
- **A child spawned its own child.** The remove command in A lists only A's direct children. A grandchild keeps running.
- **New worktree is not possible.** A is not in a git checkout, the checkout has no commits, or the branch name already exists. omp refuses with a message that names the reason, and creates nothing.
- **B needs a clean worktree.** The spawn still copies A's uncommitted changes. The model writes the cleanup into B's opening prompt or handoff note, and B cleans its own worktree. omp never cleans A's checkout for a spawn.
- **Removed child had uncommitted work in its spawned worktree.** With `worktree.onExit` set to `remove`, omp does not delete the worktree. It asks in A as part of the remove confirmation. With `keep`, the worktree and branch stay.
- **The user runs the spawn command while A works on a turn.** omp queues the command behind the running turn, the same way `/guided-goal` does, and does not stop that turn.

## Requirements *(mandatory)*

### Functional Requirements

**Spawn (omp)**

- **FR-001**: omp MUST provide a slash command that takes a free-text request and creates one Sibling Session from it.
- **FR-002**: omp MUST expose the spawn tool to the model only inside a spawn window. The window opens when the command runs. It MUST close at the first spawn call (success or failure), at a Session switch, or at the end of a turn that neither calls the spawn tool nor asks the FR-003 question. Other tool calls, for example file reads before a handoff, MUST leave the window open. When the window closes, omp MUST restore the previous tool set.
- **FR-003**: The model MUST choose one of four spawn modes from the user's request: fresh, fork, fork with handoff, or handoff summary. When the request does not make the mode clear, the model MUST ask the user one question through omp's `ask` tool before it spawns. The spawn window stays open until the user answers. Exception: when `ask.enabled` is off, the model MUST pick the most likely mode and ask no question.
- **FR-004**: In fresh mode, B MUST start with a new conversation and an opening prompt that the model writes from the request. B MUST start work on that prompt at once.
- **FR-005**: omp MUST create B in a new zmx session on A's host, with a name that the package recognizes as an omp Session. The creation MUST NOT inherit A's zmx session name or name prefix, and MUST NOT report state for A's Emacs buffer.
- **FR-006**: omp MUST record, at creation, the zmx name of the parent Session on B's zmx session. No result travels back from B to A, and A does not wait for B.
- **FR-007**: In fork mode, B MUST start with a copy of A's whole conversation, with the same result as `/fork`, and MUST wait for the user. In fork-with-handoff mode, B MUST start with the same copy plus one new message: a handoff note that the model writes from the request. B MUST start work on that note at once. In handoff-summary mode, B MUST start with a new conversation whose first message is a summary that omp writes from A's conversation. In every mode, A's own conversation and context MUST stay unchanged. A summary step MUST NOT compact A in place, as `/handoff` does today.
- **FR-008**: After a successful creation, omp MUST write one announcement to A's terminal with B's zmx name, and MUST show B's name in A. Emacs reads B's directory from zmx, not from the announcement.
- **FR-009**: When creation fails, omp MUST show the error in A, MUST NOT send an announcement, and MUST NOT leave a zmx session behind.
- **FR-020**: omp MUST refuse every spawn mode when A runs outside zmx or when A started with a key on its command line. It MUST refuse the two fork modes when A has no saved conversation. Each refusal MUST name its reason, create nothing, and send no announcement.
- **FR-022**: omp MUST provide a setting that makes a spawn ask for confirmation. The default MUST be off, and the spawn call then creates B at once. When the setting is on, omp MUST show the spawn mode, the directory, and the content that B starts with: the opening prompt, the handoff note, or the handoff summary. It MUST ask yes/no before it creates anything. A declined confirmation MUST create nothing and send no announcement.
- **FR-023**: When the request asks for a new worktree, omp MUST create a new branch and worktree from A's current commit and copy A's uncommitted changes into it, the same way `/wt` does with default settings. B MUST start in that worktree. omp MUST record on B's zmx session, at creation, that the spawn created this worktree. omp MUST NOT change A's checkout, even when the setting that makes `/wt` clean the source checkout is on.

**Spawn (Emacs package)**

- **FR-010**: The package MUST accept a spawn announcement only in a live owned omp Session buffer, and MUST do no slow work inside the terminal parser.
- **FR-011**: Before it attaches, the package MUST confirm on the announcing Session's host that B exists, that B has a valid package name, and that B runs a known Agent command. For a remote host, the host MUST be in the approved host list.
- **FR-012**: The package MUST attach B through the existing zmx attach path, with the same result as a manual attach, and MUST NOT attach B twice in one Emacs.
- **FR-013**: The package MUST provide a user option that selects whether a spawn switches to B. The default MUST switch to B. With the option off, the package MUST add the row and leave the selected window and buffer as they were.

**Remove**

- **FR-014**: omp MUST provide a slash command that ends one Session whose parent link names the Session where the command runs. The command MUST list only those live children on A's host and let the user pick one. It MUST NOT offer the Session where it runs, or any other Session.
- **FR-015**: The remove command MUST ask for confirmation that names the target before it ends anything. When the target works on a turn, the question MUST also name the running work. A declined confirmation MUST end nothing.
- **FR-016**: A removal MUST end the target Agent and its zmx session, and Emacs MUST remove the row and close the buffer with the same result as Stop.
- **FR-017**: When no Emacs is attached, the removal MUST still end the target. No Emacs may later show the target as live or reattachable.
- **FR-021**: When the terminal client of a zmx-backed Session ends without Stop, Detach, or Disconnect, the package MUST check at once whether the zmx session still exists, for local and remote Sessions. The package MUST remove the row only when the check succeeds and the session is absent. A failed or slow check MUST keep the row as `[disconnected]`.
- **FR-024**: When the remove command ends a child whose worktree the spawn created, omp MUST apply `worktree.onExit` to that worktree and its branch. `keep` MUST keep them. `ask` MUST add the question to the remove confirmation in A. `remove` MUST delete them only when the worktree is clean, on its branch, and not moved, and MUST ask in every other case. omp MUST NOT touch a worktree that the spawn did not create.

**Room for later**

- **FR-018**: The spawn tool MUST work without the slash command, so that a later change can expose it by default without a new tool.
- **FR-019**: The parent link MUST be readable from the zmx session list, so that a later change can group or report on child Sessions.

### Key Entities

- **Sibling Session**: A top-level omp Session that another Session created on request. It has its own process, terminal, zmx session, row, and buffer.
- **Parent link**: The zmx name of the Session that created a Sibling Session. omp records it when it creates the Sibling Session. The remove command uses it to find the children of a Session. No result travels along it.
- **Spawn announcement**: A one-way message from omp to the Emacs that shows the parent Session. It names the new zmx session. It carries no command and no directory.
- **Spawn mode**: Fresh, fork, fork with handoff, or handoff summary. The model selects it from the user's request.
- **Spawned worktree record**: A mark on a Sibling Session that the spawn created its worktree and branch. omp records it at creation. The remove command uses it to decide whether `worktree.onExit` applies (FR-024).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From the spawn command to a visible, usable B buffer takes zero manual steps in Emacs, for local and for remote Sessions.
- **SC-002**: With the default option, B appears and has focus within 5 seconds after the model confirms the spawn on a local host.
- **SC-003**: In 10 spawns, every B is attached exactly once per attached Emacs, and no reattach of A adds a row or a buffer.
- **SC-004**: Printed text that contains a fake announcement starts zero processes and attaches zero sessions that do not pass FR-011.
- **SC-005**: After a removal, zero processes and zero zmx sessions of the target remain, and the manager shows zero rows for it.
- **SC-006**: Outside the spawn window, the spawn tool is in the model's tool set zero times. After a turn that ends with no spawn call and no mode question, the tool is gone in 100% of runs.
- **SC-007**: The package test gate and the omp test suite pass with zero unexpected results.
- **SC-008**: In 10 spawn commands where the model tries to spawn twice, each command creates at most one zmx session and sends at most one announcement.
- **SC-009**: Across Sessions with and without children, the remove command offers zero Sessions whose parent link does not name the Session where it runs.

## Assumptions

- The feature changes two repositories: the omp Agent (commands, tool, zmx creation, announcement) and this package (announcement handler, attach, user option). Spec 010 set this precedent.
- B runs on the same host as A. A request can name an existing directory or ask for a new worktree on that host (FR-023). A request cannot name another host.
- B uses A's Agent command, profile, and model unless the request names a different one. This matches the existing `/fork` launch, including its two refusals (FR-020).
- The slash command names are planning decisions. They must not collide with the existing `/new`, `/fork`, or `/handoff`.
- Two Emacs instances that show A both attach B. A per-Emacs choice is out of scope.
- The parent link is recorded but not shown in the manager in this feature.
- Session A records the spawn in its own conversation as a short line. A's model context gets no other change.
- Sessions that are not omp, and omp Sessions outside Ghostel, get no new behavior. omp falls back to showing B's name.
