# Feature Specification: Launch Agent Sessions from Outside Events

**Feature Branch**: `024-session-launch-intake`

**Created**: 2026-11-08

**Status**: Draft

**Input**: User description: "spec it" — the intake service from `ref-docs/intake-service-prior-art.md`. It takes events from many sources (Linear issues, GitHub, a queue, a Mac app where the user chats before a launch), decides which events are real work, and launches Agent Sessions for a project on the local machine or a Configured host through one general interface.

## Background

Today a new omp Session starts only from a person: a command in Emacs, or `/spawn` in a running omp Session (spec 021). No outside event can start one. Work that arrives in Linear, in GitHub, or in a chat must be copied by hand into a new Session.

This feature adds an **Intake**: one long-running service that accepts Launch requests and outside events, records them, and starts omp Sessions in zmx on a chosen host. Each launched Session is an ordinary zmx-backed omp Session. Emacs adopts it the same way it adopts a Sibling Session, and the user can attach to it at any time.

The feature changes three places. The Intake is a new service in its own repository. omp gets a launch command that does not need a terminal or a parent Session. This package gets a public adopt command that the Intake can call, and an optional setting that lets Emacs follow the Intake and adopt new Launches itself. Prior art, the comparison with other tools, and the reasons for this split are in `ref-docs/intake-service-prior-art.md`.

## Clarifications

### Session 2026-11-08

- Q: Should feature 024 cover all seven user stories, or only a first slice that a later feature extends? → A: Stories 1–4 (P1 and P2). Chat-first cross-host launch, native Linear agent sessions, and observe mode for inferred events move to later features. Delegation moves with Linear agent sessions, so the Linear source in this feature acts on the trigger label only.
- Q: When a Linear label starts a Session, should that Session always get its own new worktree and branch, or run in the project's main checkout? → A: Linear Launches always get a new worktree with a branch named from the issue ID. Direct requests choose for themselves, and their default is the project's main checkout.
- Q: When a follow-up message arrives while the launched Session is still working on a turn, should it wait until that turn ends, or reach the Agent at once and change the current turn? → A: By default, queue it and deliver it when the turn ends. Make the choice a setting with three values: queue (default), guide the running turn, or stop the turn and then deliver. A mode where an Agent inspects the running Session and the follow-up and picks the value is a later feature.
- Q: Should the Intake launch only omp Sessions, or also the other Agents this package supports (Claude Code, Codex, OpenCode, Pi)? → A: omp only. The project mapping picks the omp command and profile. Other Agents are a later feature.
- Q: When the Intake runs on a different machine from Emacs, how should Emacs learn about a new Launch so that it can adopt the Session? → A: Support both paths. Push: the Intake calls the public adopt command through `emacsclient`, locally or over SSH. Pull: Emacs follows the Intake's change stream and adopts new Launches. The usual setup runs the Intake on the user's Mac with Emacs, with no public IP and behind NAT.
- Q: Which Linear comments become follow-ups, so that the Agent's own replies, posted with the user's Linear identity, do not loop back into its Session? → A: Only a comment that starts with a fixed follow-up prefix. The prefix is a setting, and its default is `/omp`. The Intake removes the prefix before delivery.
- Q: Should a refused Launch (untrusted actor, duplicate label event, or Linear source off) get a Linear comment on the issue? → A: No. Only a running Launch, a failed Launch, and an unmapped issue (FR-051) get a comment. Refusals show only in the Intake's Launch list.
- Q: Linear writes no history entry for a label set when the issue is created or in its first minutes. Should such an issue launch? → A: Yes. The Intake adds a creation Trigger for a new issue that has the label but no history entry that added it. The actor is the issue creator, and the same gate applies.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Launch a Session with one request (Priority: P1)

The user, a script, or another program sends one Launch request to the Intake. The request names a project and an opening prompt. It can also name a host and ask for a new worktree. The Intake starts an omp Session in a new zmx session on that host, and the Session starts work on the prompt. Emacs adopts the Session, and its row appears in the manager.

**Why this priority**: Every other story ends in this step. With only this story, any program that can send a request can start real, attachable work.

**Independent Test**: Send one Launch request from a shell on the user's private network. Confirm that a new zmx session exists on the named host, that its Agent works on the prompt, and that the Session row appears in Emacs with no manual step.

**Acceptance Scenarios**:

1. **Given** a project in the Intake configuration and a running Emacs, **When** a client sends a Launch request for that project with a prompt, **Then** an omp Session starts on the project's default host, works on the prompt, and appears in the Emacs manager.
2. **Given** a request that asks for a new worktree, **When** the Launch succeeds, **Then** the Session runs in a new worktree on a new branch, and the project's main checkout does not change.
3. **Given** a request that names a Configured host, **When** the Launch succeeds, **Then** the Session runs on that host, and Emacs attaches it under that host, the same way as a local Session.
4. **Given** the Launch fails on the host, **When** the client reads the result, **Then** the result names the reason, and the host keeps no zmx session, no worktree, and no branch from this Launch.
5. **Given** no Emacs runs when a Launch succeeds, **When** the user later starts Emacs, **Then** the Session is still running, and the user can attach it through the existing attach commands.

---

### User Story 2 - Start work from a Linear issue (Priority: P1)

The user adds a chosen label to a Linear issue. Within a minute, the Intake launches a Session for the project that the issue maps to, with the issue as the opening prompt. The Intake posts one comment on the issue that names the Session and the host.

**Why this priority**: Linear is the first event source that the user named. A label is an explicit request from a person, so the Intake can act on it with no model judgment.

**Independent Test**: Add the label to a test issue. Confirm that one Session starts within the poll window, that the issue gets one comment, and that a second label event on the same issue starts no second Session.

**Acceptance Scenarios**:

1. **Given** an allow-listed user adds the trigger label to an issue in a watched team, **When** the next poll runs, **Then** the Intake launches one Session for the mapped project and posts one comment with the Session name and host.
2. **Given** a user who is not on the allow-list adds the label, **When** the poll runs, **Then** the Intake launches nothing, and the refusal shows in the Intake's list with its reason.
3. **Given** the Intake sees the same label event twice, for example after a restart, **When** it processes the second copy, **Then** it starts no second Session.
4. **Given** an allow-listed user adds the trigger label to an issue that maps to no project, **When** the poll runs, **Then** the Intake launches nothing and posts one comment that asks the user to name the repository.
5. **Given** the Launch fails, **When** the poll runs, **Then** the Intake posts one comment that names the reason.

---

### User Story 3 - See and stop launched Sessions (Priority: P2)

The user asks the Intake for its Launches. Each row shows where the Launch came from, the host, the zmx session name, and the current state. The user can stop one Launch. Its Agent and zmx session end, and Emacs removes the row the same way as Stop.

**Why this priority**: Automatic launches cost money and attention. The user must see what runs and why, and must be able to end it.

**Independent Test**: Start two Launches. List them and confirm the origin and state of each. Kill one zmx session by hand and confirm that the list shows it as ended. Stop the other through the Intake and confirm that its zmx session and Emacs row are gone.

**Acceptance Scenarios**:

1. **Given** live and ended Launches, **When** the user lists Launches, **Then** each row shows its origin (source and link), host, zmx session name, and a state that matches the live zmx session.
2. **Given** a zmx session ended outside the Intake, **When** the user lists Launches, **Then** that Launch shows as ended, not as running.
3. **Given** a running Launch, **When** the user stops it through the Intake, **Then** its Agent and zmx session end, Emacs removes its row, and its worktree stays.
4. **Given** a client that watches for changes, **When** it misses changes during a disconnect, **Then** one list request brings it up to date.

---

### User Story 4 - Send a follow-up to a launched Session (Priority: P2)

An allow-listed user writes a new comment that starts with the follow-up prefix on a Linear issue that already has a live Launch. The comment reaches the running Session as a new user message. A client can also send a follow-up to a Launch directly.

**Why this priority**: Work from an issue often needs a correction. Without a follow-up path, a correction starts a second Session or needs a manual attach.

**Independent Test**: Launch a Session from an issue. Add a comment that starts with the follow-up prefix from an allow-listed user. Confirm that the Session receives the comment text as a user message and that no second Session starts.

**Acceptance Scenarios**:

1. **Given** a live Launch for an issue, **When** an allow-listed user posts a comment that starts with the follow-up prefix, **Then** the Session receives the comment text without the prefix as a new user message, and the Intake starts no new Session.
2. **Given** a live Launch for an issue, **When** an allow-listed comment does not start with the follow-up prefix, for example a reply that the Agent posted, **Then** the Intake delivers nothing and starts nothing.
3. **Given** an ended Launch, **When** a follow-up arrives, **Then** the Intake delivers nothing, starts nothing, and records the follow-up as refused with its reason.
4. **Given** a comment that the Intake itself posted, **When** the next poll runs, **Then** the Intake does not treat it as a follow-up.
5. **Given** the Session works on a turn and the follow-up setting is queue, **When** a follow-up arrives, **Then** the Session receives it only after the turn ends, and the turn is not stopped.
6. **Given** two follow-ups arrive during one turn, **When** the turn ends, **Then** the Session receives both, once each, in arrival order.

---

### Edge Cases

- **Host full.** The host already runs its maximum number of Sessions. The Intake keeps the Launch queued and starts it when a slot frees. It never starts it on another host on its own.
- **Reserved slot.** Sessions that the user starts by hand count toward the host limit. The Intake leaves one slot free for them.
- **Host unreachable.** The Launch fails with a reason that names the host. The Intake does not retry on another host.
- **Host not configured in Emacs.** The Session starts on the host, but Emacs does not attach it. Emacs shows one message that names the host and the Session. This matches spec 021. This case applies to a host that the Intake's map for that Emacs names. The Intake sends no push for a host that the map leaves out.
- **Emacs on another machine.** The Intake runs on a host where Emacs does not run. With push on, the Intake calls the adopt command on the Emacs machine over SSH. With pull on, Emacs adopts the Session from the change stream. Either path needs no manual step.
- **Intake cannot reach Emacs.** The Emacs machine is behind NAT, asleep, or has no SSH access from the Intake host. The push fails, and the Intake records the failure and does not retry. With pull on, Emacs adopts the Session when it next reads the Launch list.
- **Mac sleeps.** The Intake runs on the Mac, and the Mac sleeps. Polling pauses. After wake, the next poll covers the time the Mac slept, and FR-024 makes sure that no label event starts two Sessions.
- **Intake restart.** Queued Launches resume once. Running Launches keep running. No trigger starts a second Session.
- **Session ends by itself.** The Agent exits, or the user ends it in Emacs. The Intake shows the Launch as ended at its next check.
- **Issue text tries to change the Agent's instructions.** The opening prompt marks the issue text as content from the issue author. The Agent still has full shell access. This is the accepted risk in Assumptions.
- **Same issue, label added again.** The label is removed and added again while a Launch for the issue is live. The Intake starts no second Session and records the duplicate.
- **Issue branch already exists.** An earlier Launch for the issue left its branch. A new Launch for the issue gets a new branch with the next free numeric suffix, for example `eng-123-2`. The earlier branch and worktree stay unchanged.
- **Issue moves to another team or project.** A live Launch keeps running in its first project. A new trigger on the moved issue maps through the new project.
- **Very long or binary follow-up.** The Intake refuses a follow-up over the size limit and records the reason. It never sends partial text.
- **Session ends with queued follow-ups.** The Session ends before its turn ends. The queued follow-ups wait in the Session's own queue, so they end with the Session. The Intake shows each one as handed to the Session, not as read by the Agent. It refuses a follow-up that arrives after the end and records the reason.
- **Launch credential leaked.** The user replaces the credential. Requests with the old credential then fail.
- **Two Emacs instances run, or push and pull both run.** Each Emacs adopts the Session once. One Emacs never adopts it twice, whichever path reaches it first.

## Requirements *(mandatory)*

### Functional Requirements

**Launch command (omp)**

- **FR-001**: omp MUST provide a command that starts one omp Session in a new zmx session with no terminal and no parent Session. It takes a directory, an opening prompt, optional labels, and an optional request for a new worktree and branch.
- **FR-002**: The command and `/spawn` MUST create Sessions the same way: name pattern, labels, opening prompt delivery, and worktree creation and cleanup. A change to one MUST apply to both.
- **FR-003**: On success, the command MUST print one machine-readable result with the zmx session name, the directory, and the branch when it made one. On failure, it MUST print the reason, end with a failure status, and leave no zmx session, no worktree, and no branch.
- **FR-004**: A Session that this command starts MUST report its Agent state to Emacs the same way a Sibling Session does.

**Adopt command (this package)**

- **FR-010**: The package MUST provide a public command that adopts one named zmx session, local or on a Configured host. A program outside Emacs MUST be able to call it. The result MUST match the adoption of a Sibling Session, including the user option that selects whether a spawn switches to the new Session.
- **FR-011**: The adopt command MUST refuse a host that is not a Configured host and a name that is not a package Session name. It MUST show one message that names the refused host or name. It MUST NOT adopt one zmx session twice in one Emacs.
- **FR-012**: The package MUST provide an optional setting with an Intake address and credential. When the setting is set, the package MUST follow the Intake's change stream and adopt each running Launch on a Configured host through the FR-010 command. When it reconnects or Emacs starts, the package MUST read the Launch list once and adopt running Launches it has not adopted. When the setting is not set, the package MUST NOT contact the Intake.

**Intake: requests and Launches**

- **FR-020**: The Intake MUST accept Launch requests only from clients that present the Intake credential. It MUST be reachable only from the user's own machines and private network, not from the public internet.
- **FR-021**: A Launch request MUST name a project and an opening prompt. It MAY name a host, a new worktree with a branch name, and a request key. A request that does not ask for a new worktree MUST run in the project's repository path. A request that names an unknown project or a host outside the project's host list MUST fail with a reason.
- **FR-022**: The Intake MUST resolve each project to a repository path, a default host, allowed hosts, and an omp command with its profile from its own user configuration. Every Launch MUST start omp. This package MUST NOT own that mapping.
- **FR-023**: The Intake MUST record every Trigger and Launch durably before it acts on it. A restart MUST NOT lose a queued Launch or start a Launch twice.
- **FR-024**: Each Trigger MUST have a stable identity derived from its source event. Two copies of one Trigger, or two requests with the same request key, MUST start at most one Session.
- **FR-025**: The Intake MUST enforce a per-host limit on live Sessions, counting every package Session on the host. It MUST keep one slot free for Sessions that the user starts by hand. When a host is full, the Launch MUST wait in a queue for that host.
- **FR-026**: The Intake MUST derive the state of a Launch from the live zmx session on its host at each check. Its own records MUST NOT keep a Launch in the running state after its zmx session is gone.
- **FR-027**: After a successful Launch, the Intake MUST push the adoption: it MUST call the FR-010 command through `emacsclient` on each Emacs machine in its configuration, as a local call on the same machine and over SSH on another. A failed push MUST be recorded and MUST NOT be retried. The pull path in FR-012 covers missed pushes. When no Emacs runs, the Launch MUST still succeed.
- **FR-028**: The Intake MUST list Launches with origin, host, zmx session name, state, and refusal or failure reason. It MUST also offer a change stream. A client that misses changes MUST be able to catch up with one list request.
- **FR-029**: The Intake MUST stop a Launch on request. A stop MUST end its Agent and zmx session with the same result as Stop in Emacs, and MUST keep its worktree and branch.
- **FR-030**: The Intake MUST deliver a follow-up to a live Launch as a new user message in its Session. It MUST refuse a follow-up to an ended Launch, or a follow-up over the size limit, and record the reason.
- **FR-031**: A follow-up setting MUST control delivery while the Session works on a turn. `queue` (the default) MUST deliver the follow-up after the turn ends. `guide` MUST deliver it at once into the running turn without a stop. `stop` MUST stop the turn and then deliver it. In every value, the Session MUST receive each follow-up once, in arrival order.

**Intake: the gate**

- **FR-040**: Every Trigger MUST pass a gate before any model sees it. The gate MUST use only fixed rules: whether the source is turned on, whether the actor is trusted, whether the issue already has a live Launch, and whether the issue maps to a project.
- **FR-041**: The user MUST be able to turn off each source. A Trigger from a source that is off MUST be recorded and MUST launch nothing.
- **FR-043**: The gate MUST trust the actor of a Trigger only when the Trigger comes from an authenticated source: a client with the Intake credential, or a tracker read done with the user's own tracker access. For a Linear Trigger, the actor MUST also be on the actor allow-list.

**Linear source**

- **FR-050**: The Intake MUST check watched Linear teams at least once every 60 seconds for issues that received the trigger label.
- **FR-051**: The Intake MUST map an issue to a project in this order: a repository named in the issue, an issue label, the Linear project, the Linear team. When no rule matches for a Trigger whose gate result is `unmapped`, it MUST launch nothing and post one comment that asks for the repository.
- **FR-052**: The Intake MUST post one comment after each Launch result for an issue: the Session name and host on success, or the reason on failure. A Launch that the gate refuses as `untrusted`, `duplicate`, or `source_off` MUST get no comment. Its refusal shows only in the Launch list (FR-028).
- **FR-053**: The opening prompt MUST contain the issue title, description, and link, and MUST mark the issue text as content from the issue author.
- **FR-054**: A new comment from an allow-listed actor that starts with the follow-up prefix, on an issue with a live Launch, MUST become a follow-up (FR-030) without the prefix, not a new Launch. Every other comment MUST NOT become a follow-up. This includes the Agent's own replies and the comments that the Intake posted. The prefix is a setting, and its default is `/omp`.
- **FR-055**: Every Launch from a Linear Trigger MUST run in a new worktree on a new branch whose name comes from the issue ID. When that branch exists, the Launch MUST use the next free numeric suffix and MUST NOT change the existing branch or worktree.

### Key Entities

- **Intake**: The single service that receives Triggers and Launch requests, applies the gate, and starts Launches. One instance runs for the user.
- **Trigger**: One event from a source, with a stable identity, actor, source link, and the gate result.
- **Launch**: One request to start a Session, and its result. It has an origin Trigger, project, host, prompt, zmx session name, and state (queued, starting, running, ended, failed, refused). A **live** Launch is one in the state queued, starting, or running.
- **Project mapping**: User configuration that maps a project to a repository path, a default host, allowed hosts, and an omp command with its profile.
- **Source**: An origin of Triggers: the Linear poller or the Launch request interface. Each source can be turned off.
- **Actor allow-list**: The Linear users whose label Triggers the gate accepts.
- **Host slot**: One unit of the per-host Session limit. One slot per host stays free for the user.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From a Launch request to a Session row in Emacs that the user can attach takes zero manual steps and at most 15 seconds on the local machine, or at most 30 seconds on a Configured host.
- **SC-002**: In a test that delivers one Trigger 100 times, including across an Intake restart, exactly one Session starts.
- **SC-003**: After an Intake restart with 10 queued or running Launches, zero Launches are lost, zero start twice, and every listed state matches the live zmx sessions within one check.
- **SC-004**: After an allow-listed user labels an issue, the issue shows the Launch comment within 90 seconds.
- **SC-005**: Requests without the credential and Triggers from actors outside the allow-list start zero Sessions.
- **SC-006**: Across a run that sends more Launches than a host allows, the count of live package Sessions on that host never exceeds its limit minus the reserved slot.
- **SC-007**: With push and pull both on, across 20 Launches, each Emacs adopts each Session exactly once. With push off or failing, a running Emacs that has pull on adopts each new Launch within 10 seconds.
- **SC-008**: The package test gate, the omp test suite, and the Intake test suite pass with zero unexpected results.

## Assumptions

- The feature changes three repositories: a new repository for the Intake, the omp fork (launch command), and this package (public adopt command and optional pull path). Specs 010 and 021 set the precedent for work that spans repositories.
- One user owns every machine. The Intake runs as one instance on one host that the user picks. Most of the time this is the user's Mac, with Emacs on the same machine, no public IP, and NAT in front. Polling works there because it needs only outgoing connections. Polling pauses while the Mac sleeps.
- The user's machines reach each other over a private network. Remote hosts are reached over SSH and are already Configured hosts in Emacs.
- Sessions stay interactive omp Sessions in zmx. The Intake never runs an Agent without a terminal.
- GitHub events, queues, and other programs reach the Intake through the Launch request interface, for example from a small forwarder. A dedicated GitHub source is out of scope.
- A chat app (for example a Mac app) is a client of the Launch request interface. Building that app is out of scope.
- The Agent writes its final reply to Linear with its own Linear access in its own Session. Text injected into an issue can then read or write Linear and send that access out. The user accepts this risk for one user. Moving Linear writes into the Intake is a later change.
- These items move to later features. `ref-docs/intake-service-prior-art.md` keeps the design notes for them.
  - A Session that asks for a new Session on another host through the Intake, with a parent link and a depth limit.
  - Native Linear agent sessions and delegation, with a verified public webhook receiver.
  - Observe mode with proposals for inferred events.
  - Launches of Agents other than omp.
  - A follow-up mode where an Agent inspects the running Session and the follow-up, then picks `queue`, `guide`, or `stop`.
- Remote parity (constitution principle VI): a launched Session on a Configured host behaves like a local one in Emacs. The one difference is the existing rule that Emacs attaches only Configured hosts.
- The Intake does not show launch origin in the Emacs manager in this feature.
