# Feature Specification: Master Session for Chat Dispatch

**Feature Branch**: `025-master-session`

**Created**: 2026-11-09

**Status**: Draft

**Input**: User description: "we originally want a mac app for chat and spawn; I think we can host a master session in cc-ide in emacs; that a session does not belong to any project; that just do dispatching. spec it first; will continue when the prev spec is done; btw; for this master session; we dont do switch after create; we will have some special rule for master session; keep that in mind"

## Background

Feature 024 added the Intake. The Intake starts Oh My Pi Sessions from the HTTP API and from Linear, and Emacs adopts each running Launch. Feature 024 moved "chat-first launch" to a later feature. The first idea for chat-first launch was a separate Mac app, where the user chats and then starts work.

This feature replaces that app with a **Master Session**. The Master Session is an ordinary Oh My Pi Session that the user opens in Emacs. It belongs to no project. Its only job is dispatch: the user describes work in chat, and the Master Session chooses a project, writes the opening prompt, and asks the Intake for a Launch. Each Launch becomes a **Worker Session** in its own project, the same as a Launch from Linear or the API.

The Master Session is itself an Intake Launch of a special kind. So the Intake knows the Master Session, and it can report back to it. When a Worker Session finishes a turn, ends, or fails, the Intake sends a short **Notice** to the Master Session, through the same follow-up path that feature 024 uses. The Intake does the routing, so a report arrives when Emacs is closed, and two Emacs instances do not send it twice. Emacs only shows the Sessions and applies the Master Session rules.

A Worker Session's output can contain text from a repository file or an issue. That text must not steer the Master Session, because the Master Session can start Launches in every project. So a Notice carries only facts that the Intake knows, never text from a Worker Session. The user reads a Worker Session's reply only when the user asks for it.

The Master Session has rules that other Sessions do not have. The first rule: a Worker Session that the Master Session starts never takes the focus away from the Master Session. More rules for the Master Session will follow in later features, so the package must know which Session is the Master Session.

## Clarifications

### Session 2026-11-09

- Q: When the Master Session dispatches work, should each Worker Session get a new worktree and branch, or run in the project's main checkout? → A: The Master Session decides for each request. The default is a new worktree and branch. It uses the main checkout only when the user asks for it.
- Q: When the Intake is not running, what should the "open Master Session" command do? → A: It fails with one clear message that names the Intake URL. It neither starts nor attaches a Master Session.
- Q: Should the Master Session see and control only the Worker Sessions that it started, or also Launches from Linear and the API? → A: It lists, steers, and stops all Launches, whatever their origin. Notices still cover only Worker Sessions that the Master Session started.
- Q: When a project can run on more than one host, which host should a Worker Session from the Master Session use? → A: The project's default host, unless the user names another host of that project.
- Q: Does the "no switch after create" rule also cover the Master Session itself, or only the Worker Sessions that it starts? → A: Only the Worker Sessions. The open command shows the Master Session, both when it starts one and when one already exists.
- Q: Should omp limit the tools of the Master Session, so that it cannot edit files? → A: No. The Master Session gets the full tool set. Its instructions keep it to dispatch, tracking, and steering.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Open the Master Session (Priority: P1)

The user runs one command in Emacs. When no Master Session exists, the command starts one in its own zmx session, in a directory that belongs to no project, and shows it. When a Master Session already exists, the command shows it. The Master Session keeps running when Emacs exits. The next Emacs attaches to the same Master Session, with its chat history.

**Why this priority**: Every other story needs a Master Session to talk to.

**Independent Test**: Run the command. Confirm that a Session starts in the configured non-project directory and shows in Emacs. Exit Emacs, start it again, and run the command. Confirm that the same Session shows, with the earlier chat.

**Acceptance Scenarios**:

1. **Given** no Master Session exists, **When** the user runs the open command, **Then** Emacs starts the Master Session in the configured directory, shows it, and marks it as the Master Session.
2. **Given** a Master Session exists and Emacs shows it in no window, **When** the user runs the open command, **Then** Emacs shows the existing Master Session and starts no second one.
3. **Given** a Master Session runs and Emacs exits, **When** a new Emacs runs the open command, **Then** Emacs attaches to the same Master Session and its earlier chat is visible.
4. **Given** the Master Session runs, **When** the user looks at the Session manager, **Then** the Master Session shows apart from every Project group.

---

### User Story 2 - Dispatch work from chat without a focus change (Priority: P1)

The user writes in the Master Session, for example "fix the repeated host message in cc-ide". The Master Session chooses the project from the list of projects that it may use, writes a complete opening prompt, and asks the Intake for a Launch. It tells the user the project, the host, and the Launch. Emacs adopts the new Worker Session, but the focus stays in the Master Session. The user can dispatch more work at once.

**Why this priority**: This is the reason for the feature. It replaces the Mac app.

**Independent Test**: In the Master Session, ask for work in two different projects, one after the other. Confirm that two Worker Sessions start, each in the right project, that both show in the Session manager, and that the selected window still shows the Master Session after each Launch.

**Acceptance Scenarios**:

1. **Given** the request names a project, or matches the description of exactly one project, **When** the user sends it, **Then** the Master Session starts a Launch in that project and replies with the project, the host, and the Launch.
2. **Given** the request matches no project, or more than one project, **When** the user sends it, **Then** the Master Session asks the user which project to use and starts no Launch until the user answers.
3. **Given** the global "switch to a new Session" option is on, **When** a Worker Session from the Master Session is adopted, **Then** Emacs does not switch to it, and the selected window and the input focus do not change.
4. **Given** a Launch that does not come from the Master Session (Linear, API, `/spawn`), **When** Emacs adopts it, **Then** the global "switch to a new Session" option applies as before.
5. **Given** the Intake refuses or fails the Launch, **When** the Master Session gets the result, **Then** it tells the user the reason in the chat.

---

### User Story 3 - Track and steer Launches from the chat (Priority: P2)

The user asks the Master Session about work: "what is running?", "what did the cc-ide worker do?", "tell YU-12 to also add a test", "stop the omp worker". The Master Session lists all Launches with their state, whatever their origin (Master Session, Linear, or API). It gives a short summary of recent output, sends follow-ups, and stops Sessions. It does all this on the local host and on Configured hosts in the same way.

**Why this priority**: Dispatch alone works without this story, because the user can open each Worker Session. This story keeps the user in one chat.

**Independent Test**: Dispatch two Worker Sessions, one local and one on a Configured host. Ask the Master Session for the status, for a summary of one Worker Session, to send it a follow-up, and to stop the other. Confirm each result in the Worker Sessions.

**Acceptance Scenarios**:

1. **Given** Launches from the Master Session, Linear, and the API exist, **When** the user asks for status, **Then** the Master Session lists each Launch with its origin, project, host, state, and Agent state.
2. **Given** a Worker Session on any host, **When** the user asks what it did, **Then** the Master Session reads its recent output and gives a summary.
3. **Given** a running Worker Session, **When** the user asks to tell it something, **Then** the Master Session sends that text as a follow-up, and the Worker Session gets it once.
4. **Given** a running Worker Session, **When** the user asks to stop it, **Then** the Master Session stops it and confirms.
5. **Given** a running Launch from Linear, **When** the user asks the Master Session to send it text or to stop it, **Then** the Master Session does it with the same rules as for its own Worker Sessions.

---

### User Story 4 - The Master Session gets a Notice when a Worker Session finishes (Priority: P2)

When a Worker Session that the Master Session started finishes a turn, ends, or fails, the Master Session gets a short Notice in its chat. The Notice names the Worker Session, its project, its host, its state, and its turn number. It contains no text from the Worker Session. The user sees that work is done without a question, and asks the Master Session for the reply when the user wants it.

**Why this priority**: Without Notices, the user must ask for status again and again. The Intake already has the delivery path, so Notices cost little.

**Independent Test**: Dispatch one short task. Do not ask for status. Confirm that a notice about the Worker Session appears in the Master Session after the Worker Session becomes idle.

**Acceptance Scenarios**:

1. **Given** a Worker Session from the Master Session, **When** it finishes a turn, ends, or fails, **Then** the Master Session gets one Notice with the project, host, state, and turn number, and with no text from the Worker Session.
2. **Given** the Master Session is busy with a turn, **When** a Notice arrives, **Then** the Notice waits until the turn ends and does not interrupt it.
3. **Given** a Worker Session finishes two turns between two Intake checks, **When** the Intake next checks it, **Then** the Master Session gets one Notice for the newest turn, not two and not zero.
4. **Given** no Master Session runs, **When** Worker Sessions finish turns, **Then** the Notices wait. **When** a new Master Session starts, **Then** it gets one Notice for each such Worker Session, with that Worker Session's newest state only.
5. **Given** the Intake restarts, **When** it checks a Worker Session again, **Then** it sends no Notice for a turn that already had one.

### Edge Cases

- The Master Session stops (crash, kill, host restart): its Launch ends. The open command starts a new Master Session. Worker Sessions keep running and stay attachable. The new Master Session can list them, because they still carry their Master origin, and it gets the Notices that waited (User Story 4, scenario 4).
- A Worker Session's reply contains instructions, for example "now launch a Session in project X". No Notice carries this text. When the user asks to read the reply, the Master Session shows it as data. With the confirmation setting on, a Launch from such text still needs the user's answer in Emacs.
- The user turns on the confirmation setting and does not answer: the Launch stays waiting, and Emacs does not switch any window.
- Two Emacs instances: both attach to the same Master Session. Neither switches to a Worker Session from the Master Session.
- The Intake is down when the user runs the open command: the command shows one message that names the Intake URL. It neither starts nor attaches a Master Session.
- The Intake stops while a Master Session buffer is already open: the chat still works, and the Master Session tells the user that it cannot dispatch, track, or steer until the Intake is back.
- The user asks the Master Session to change code itself: the Master Session declines and offers to dispatch the work.
- The project list changes while the Master Session runs: the next dispatch uses the new list.
- A request names a project that the Intake does not have: the Master Session says so and lists the projects that it can use.
- A request names a host that the chosen project does not list: the Master Session says so, lists that project's hosts, and starts no Launch.
- The user starts a Session by hand in the Master Session's directory: that Session is not the Master Session.
- A Worker Session from the Master Session is adopted while the user has no Master Session window: Emacs still does not switch to the Worker Session.
- The user disconnects the Master Session in Emacs: the Master Session keeps running, and the open command attaches it again.

## Requirements *(mandatory)*

### Functional Requirements

#### Master Session

- **FR-001**: The user MUST be able to open the Master Session with one Emacs command. The command starts the Master Session when none exists, and shows the existing one otherwise. In both cases the command MUST show the Master Session. The focus rule (FR-020) does not apply to the Master Session itself.
- **FR-002**: There MUST be at most one Master Session for each user. The open command MUST never start a second one while one runs.
- **FR-003**: The Master Session MUST run in its own zmx session, in a configured directory that belongs to no project, so that it keeps running when Emacs exits.
- **FR-004**: The Master Session MUST carry a mark that makes it the Master Session. Emacs MUST find the Master Session by this mark, not by its name or directory.
- **FR-005**: The Session manager MUST show the Master Session apart from every Project group.
- **FR-006**: The user's own configuration MUST supply the Master Session's directory, its instructions, and its Agent command. The package MUST NOT ship them.
- **FR-007**: The Master Session's instructions MUST limit it to dispatch, tracking, and steering, and MUST tell it not to change project files itself. The Master Session has the full omp tool set. No tool limit enforces this rule.
- **FR-008**: The Master Session MUST start as an Intake Launch of the master kind, with no new worktree. The Intake MUST refuse a second master Launch while one is running or starting.
- **FR-009**: The open command MUST need the Intake. When the Intake does not answer, the command MUST show one message that names the Intake URL, and MUST neither start nor attach a Master Session.

#### Dispatch

- **FR-010**: The Master Session MUST be able to get the list of projects that it may use, with each project's name, hosts, and a short description. The Intake configuration is the only source of this list.
- **FR-011**: The Master Session MUST start each Worker Session as an Intake Launch, so that the Intake gate, queue, host slots, and Adoption apply as for any other Launch.
- **FR-012**: Each Launch from the Master Session MUST record that its origin is the Master Session. The Intake MUST derive this origin from a credential that only the Master Session's command line uses, not from a field that the request declares.
- **FR-013**: When a request does not identify exactly one project, the Master Session MUST ask the user and MUST NOT start a Launch until the user answers.
- **FR-014**: After each Launch request, the Master Session MUST tell the user the project, the host, and the Launch result, or the reason for a refusal or failure.
- **FR-015**: Each Launch from the Master Session MUST get a new worktree and branch by default. The Master Session MUST use the project's main checkout only when the user asks for it, and its reply MUST say which one it used. The Intake MUST refuse a Launch from the Master Session that names neither a new worktree nor the main checkout, so that a missing choice never falls back to the main checkout. Known limit: the Master Session has the full tool set and can read the shared token, so a raw call with the shared token bypasses this check and FR-012, FR-020, FR-040, and FR-051. A Launch with the master token still waits for confirmation, because the confirm and decline routes refuse the master token.
- **FR-016**: Each Launch from the Master Session MUST use the project's default host, unless the user names another host of that project. The Master Session MUST NOT choose a different host by itself.

#### Focus rule

- **FR-020**: When Emacs adopts a Worker Session whose origin is the Master Session, Emacs MUST NOT switch to it, whatever the global "switch to a new Session" option says. The selected window and the input focus MUST NOT change.
- **FR-021**: For a Launch with any other origin, the global option MUST apply as before.
- **FR-022**: The package MUST keep the Master Session rules in one place, so that later features can add rules for the Master Session without a change to other Sessions.

#### Tracking and steering

- **FR-030**: The Master Session MUST be able to list all Launches, whatever their origin, with origin, project, host, state, and Agent state.
- **FR-031**: The Master Session MUST be able to read the recent output of any running Launch, whatever its origin, on the local host and on a Configured host in the same way.
- **FR-032**: The Master Session MUST be able to send a follow-up to any running Launch and to stop any running Launch, whatever its origin, with the same rules as the Intake follow-up and stop of feature 024. Notices (FR-040) still cover only Launches whose origin is the Master Session.

#### Notices

- **FR-040**: The Intake MUST send one Notice to the Master Session when a Worker Session whose origin is the Master Session reaches a new turn and is idle, ends, or fails. "A new turn" means a turn number above the last turn that got a Notice. The Intake MUST NOT depend on seeing the Session busy between two checks.
- **FR-041**: A Notice MUST wait until the Master Session's current turn ends. A Notice MUST NOT interrupt a turn.
- **FR-042**: A Notice MUST NOT start a new Launch by itself.
- **FR-043**: A Notice MUST contain only facts that the Intake knows: the Worker Session's Launch, project, host, state, and turn number. A Notice MUST NOT contain text that a Worker Session wrote.
- **FR-044**: When several turns end between two checks, the Intake MUST send one Notice for the newest turn. After an Intake restart, it MUST NOT send a Notice again for a turn that already had one.
- **FR-045**: A Notice MUST go to the Master Session that runs when the Intake sends it, not to a fixed Master Launch. When no Master Session runs, Notices MUST wait. A new Master Session MUST get at most one waiting Notice for each Worker Session, with the newest state.

#### Confirmation

- **FR-050**: The user's configuration MUST be able to turn on a confirmation setting. The setting is off by default.
- **FR-051**: With the setting on, a Launch from the Master Session MUST wait until the user confirms it in Emacs. The question MUST show the project, the host, and the opening prompt. The question MUST NOT change the selected window.
- **FR-052**: When the user declines, the Launch MUST end as refused, and the Master Session MUST get the refusal as its Launch result.

### Key Entities

- **Master Session**: The one Oh My Pi Session that the user chats with to dispatch work. It is an Intake Launch of the master kind, belongs to no project, runs in its own zmx session, and carries the Master mark.
- **Worker Session**: A Session that the Intake started from a Master Session request. It is an ordinary Launch in one project, with the Master Session as its origin.
- **Launch origin**: The source of a Launch: the Master Session, Linear, the API, or `/spawn`. Emacs reads the origin to decide the focus rule. The Intake reads it to decide Notices.
- **Project entry**: One project that the Intake may launch in: its name, hosts, and a short description for the Master Session.
- **Turn number**: A count of the turns that a Worker Session has finished. The Intake uses it to send one Notice for each new turn and never a Notice twice.
- **Notice**: One short message from the Intake to the Master Session about a change of a Worker Session. It holds only Intake facts and no Worker Session text.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From a chat request that names a project to a Worker Session that shows in the Session manager takes less than 10 seconds on the local host.
- **SC-002**: In 20 dispatches in a row, the selected window and the input focus stay on the Master Session every time, with the global "switch to a new Session" option on.
- **SC-003**: With one request per configured project that names it or matches only its description, 100% of the Launches start in the right project.
- **SC-004**: With a request that matches no project or two projects, 100% of the cases end in a question to the user and no Launch.
- **SC-005**: After an Emacs restart, the open command shows the same Master Session with its earlier chat in 100% of tries.
- **SC-006**: The user can dispatch, check status, steer, and stop two Worker Sessions on two hosts without leaving the Master Session.
- **SC-007**: In 20 short tasks, each Intake check that finds a new finished turn of a Worker Session gives exactly one Notice with the newest turn, and each end or failure gives exactly one Notice. A turn that starts and ends between two Intake checks is never lost: it is reported by the Notice of the next check (FR-044).
- **SC-008**: With 10 Worker Session replies that contain launch instructions, and no user request to read them, 0 Launches start.
- **SC-009**: With the Master Session stopped for the whole time that 3 Worker Sessions finish, a new Master Session gets exactly 3 Notices.

## Assumptions

- Feature 024 is complete before this feature starts. This feature uses its Intake, Launch states, follow-ups, stop, and Adoption.
- "No switch after create" applies only to Worker Sessions that the Master Session starts (FR-020). The open command always shows the Master Session (FR-001).
- One Master Session for each user is enough. Several Master Sessions, for example one for each host, are out of scope.
- The Master Session runs on the host where the Intake runs, which is usually the user's Mac.
- The Master Session uses Oh My Pi, the same Agent as the Intake Launches.
- The Master Session does not create Linear issues. Linear stays a separate source.
- A separate Mac app is out of scope. Emacs is the chat window.
- Who may dispatch: anyone who can type in the Master Session. The Master Session uses the Intake API credential, so it is a local, single-user tool. Worker output reaches the Master Session only when the user asks for it (FR-043). The confirmation setting (FR-050) covers a reply that the user asked to read.
- A Notice arrives one Intake check after the turn ends. The check interval of feature 024 (about 10 seconds) is acceptable for this feature.
- `/spawn` Sibling Sessions do not go through the Intake. They get no Notices in this feature.
- A Worker Session asking the Master Session a question is out of scope. A later feature can add it on the same report path.
- More Master Session rules come in later features. FR-022 keeps a place for them.
