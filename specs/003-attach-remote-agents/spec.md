# Feature Specification: Attach Remote Agents

**Feature Branch**: `main` (unchanged)

**Created**: 2026-09-05

**Status**: Draft

**Input**: User request: "make a spec", based on the confirmed remote-agent design interview. Use local Emacs to access existing agents across personal SSH hosts. Manage them beside local sessions without restarting their processes or requiring remote IDE integration.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Discover and attach an existing remote agent (Priority: P1)

The user selects a configured personal host and discovers its existing zmx sessions. The user attaches an Agent through a terminal in local Emacs. The Agent continues its existing work on the remote host.

**Why this priority**: Remote attachment provides the core benefit without remote process creation or editor integration.

**Independent Test**: Start an Agent inside zmx on a configured host before the test. Discover and attach it from local Emacs. Submit a prompt and observe the response without restarting the Agent.

**Acceptance Scenarios**:

1. **Given** a reachable configured host with an existing Agent, **When** the user requests discovery, **Then** the user can select and attach that Agent. The feature does not contact other hosts automatically.
2. **Given** SSH configuration without automatic terminal allocation, **When** the user attaches, **Then** the terminal accepts interactive input and displays output. The attach request explicitly includes `ssh -t`.
3. **Given** an Agent without a connection to the current editor, **When** the user attaches, **Then** terminal interaction works without MCP or structured Agent state. Attachment does not configure or require local editor endpoints.
4. **Given** a command that discovery cannot recognize, **When** the user requests bulk attach, **Then** the feature skips that session and names it. Individual attach permits explicit identification through the existing Agent selection behavior.
5. **Given** missing project metadata, **When** the user requests bulk attach, **Then** the feature skips that session and explains why. Individual attach permits the user to supply its remote project directory.
6. **Given** no eligible sessions, **When** the user requests discovery, **Then** the feature reports that result without starting an Agent or shell.

---

### User Story 2 - Work across hosts in the existing manager (Priority: P1)

The user switches between local and remote Agents in the existing manager. Host labels distinguish remote projects without a new sidebar design.

**Why this priority**: The user needs one workspace for Agents on multiple machines, not separate management tools for each host.

**Independent Test**: Attach one local Agent and one Agent on each of two remote hosts. Use the same project and zmx session names on both remote hosts. Select each row and confirm that input reaches only the selected Agent.

**Acceptance Scenarios**:

1. **Given** local and remote sessions for `my-app`, **When** the manager displays them, **Then** the remote row includes `[ramhorn] my-app`. The local and remote projects remain distinct.
2. **Given** identical project and zmx session names on two hosts, **When** the user selects either row, **Then** the manager opens the correct attached terminal. Rename, selection, and lifecycle actions do not affect the other host's session.
3. **Given** an already attached remote zmx session, **When** the user selects it again, **Then** the manager reuses its existing Session instead of creating another row.
4. **Given** an unreachable configured host, **When** discovery fails for that host, **Then** the feature names the failed host and explains the failure. Existing local sessions and sessions on other hosts remain usable.

---

### User Story 3 - Distinguish output silence from disconnection (Priority: P1)

The user sees output-idle status while connected. If the connection ends, the manager retains a disconnected row rather than claiming that the Agent has finished.

**Why this priority**: A quiet terminal and an ended connection must not produce the same status or cause accidental process replacement.

**Independent Test**: Attach an Agent, exercise the existing output-idle delay, and then end its SSH connection without stopping the Agent. Refresh the manager and explicitly reattach the same row.

**Acceptance Scenarios**:

1. **Given** a connected remote Agent without structured Agent state, **When** genuine terminal output arrives and later stops, **Then** existing output-activity and output-idle behavior applies. Ghostel redraw-only events do not count as Agent output.
2. **Given** a connected Session, **When** the connection reports that it has ended, **Then** the manager retains its row and marks it disconnected. The feature clears output-idle and working status and does not claim that the Agent stopped.
3. **Given** a disconnected row, **When** the user refreshes or selects it, **Then** the row remains available with an explicit reattach action. Merely displaying or selecting the row does not contact the host.
4. **Given** a disconnected row whose Agent still runs, **When** the user explicitly requests reattach, **Then** the same row opens the existing Agent. The Agent does not restart, and the manager does not add a duplicate row.
5. **Given** a disconnected row whose target no longer exists, **When** the user requests reattach, **Then** the feature reports the missing target. It retains the disconnected row and does not create an Agent, shell, or replacement session.

---

### User Story 4 - Return after an editor restart or change of computer (Priority: P2)

With manager persistence enabled, the user returns to remembered remote sessions after an Emacs restart. Another computer can independently discover and attach the same remote Agent. Each Emacs keeps its own session history.

**Why this priority**: The user can move between computers while the remote Agent continues, without a history synchronization service.

**Independent Test**: Attach a remote Agent and restart Emacs with persistence enabled. Verify the remembered row before requesting any connection. Discover the same Agent from a second Emacs instance with no shared history.

**Acceptance Scenarios**:

1. **Given** a previously attached remote session and enabled persistence, **When** Emacs restarts, **Then** the manager restores a disconnected row without contacting any host. A manager refresh preserves that row and its host, project label, and existing saved presentation choices.
2. **Given** a restored row and a still-running target, **When** the user explicitly requests reattach, **Then** the existing row becomes connected. The Agent continues without a restart.
3. **Given** disabled manager persistence, **When** Emacs restarts, **Then** this feature does not restore saved remote rows. The user can still discover and attach existing remote Agents.
4. **Given** the same host configuration on another computer, **When** the user requests discovery and attach there, **Then** the user reaches the existing Agent. The feature does not copy history between computers or forcibly detach another client.

---

### User Story 5 - Detach or stop with clear consequences (Priority: P1)

The user can close an attached terminal without stopping the remote Agent. An explicit Stop action names the remote target and requires confirmation because it affects every attached client.

**Why this priority**: The distinction protects long-running work and prevents a local terminal action from silently terminating remote work.

**Independent Test**: Attach the same remote Agent from two clients. Close one terminal, cancel a Stop action, and finally confirm Stop for that exact target.

**Acceptance Scenarios**:

1. **Given** an attached remote Agent, **When** the user closes its terminal buffer or exits Emacs, **Then** only that client detaches. The Agent continues, and an open Emacs retains the disconnected row.
2. **Given** a remote session, **When** the user requests Stop, **Then** confirmation names its host and zmx session. The confirmation explains that stopping affects every attached client.
3. **Given** a Stop confirmation, **When** the user cancels, **Then** the feature sends no stop request and the Agent continues.
4. **Given** a confirmed Stop, **When** the host reports success, **Then** the target stops for all clients. Other sessions remain unaffected, and the manager no longer shows the target as connected.
5. **Given** a confirmed Stop, **When** the host cannot confirm success, **Then** the feature reports that it cannot confirm the stop. It does not claim success or retry automatically.

### Edge Cases

- **EC-01 — Unavailable prerequisites**: Authentication failure, an unreachable host, or missing remote zmx produces a host-specific error with a corrective action. Discovery failure must not look like an empty session list.
- **EC-02 — Discovery race**: A target can disappear between discovery and attach. The feature reports the missing target without leaving a running shell, Agent, or replacement session. A short-lived empty zmx session that exits at once is accepted.
- **EC-03 — Remote paths**: A remote project directory need not exist locally. Discovery and attachment must not require a matching local checkout or treat that path as a local project.
- **EC-04 — Missing terminal support**: Remote attachment uses Ghostel only. Missing Ghostel or native support must produce an explicit error before terminal creation. Feature 008 removed the other terminal integrations and their selection-dependent guard.
- **EC-05 — Silent network loss**: Output silence alone does not prove disconnection. Once the connection reports failure, disconnected status replaces output-idle status. Immediate detection of an unreported network failure is not a promise of this feature.
- **EC-06 — Removed host configuration**: A remembered row remains visible if its host leaves the configured list. Reattach requires the user to restore that configuration. The feature does not silently connect through a removed destination.
- **EC-07 — Names and punctuation**: Host, session, and project names must not cause unintended commands or target another session. Unsupported input produces an explicit error before any remote action.
- **EC-08 — Non-agent sessions**: Discovery may expose unrecognized candidates for manual identification, but ordinary shells and arbitrary remote processes are not supported Agent sessions.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST manage only existing Agents inside remote zmx sessions on the user's own machines. It MUST NOT start remote Agents, shells, or replacement sessions.
- **FR-002**: The user MUST control an explicit list of SSH destinations. Discovery and connection attempts MUST require an explicit user action. Startup, restoration, and manager refresh MUST NOT initiate remote connections or scan SSH configuration for additional hosts.
- **FR-003**: Discovery MUST let the user select existing remote sessions for individual or bulk attach. Already attached targets MUST reuse their existing Session.
- **FR-004**: Interactive remote attach MUST explicitly request a terminal with `ssh -t`, independent of SSH configuration defaults.
- **FR-005**: Remote attachment MUST provide terminal interaction without requiring MCP, structured Agent state, or editor tools. It MUST NOT configure local editor endpoints for the remote Agent.
- **FR-006**: Agent recognition MUST use the user's existing Agent configuration and identification behavior. Bulk attach MUST skip and identify unrecognized candidates. Individual attach MUST permit explicit Agent identification.
- **FR-007**: Bulk attach MUST skip and identify candidates without project metadata. Individual attach MUST permit the user to supply the remote project directory. A matching local directory MUST NOT be required.
- **FR-008**: The existing manager MUST display local and remote sessions together. Remote labels MUST include the configured destination, such as `[ramhorn] my-app`.
- **FR-009**: The manager MUST distinguish remote targets by host and zmx session name. Same-named projects on different hosts MUST remain distinct. Selection and lifecycle actions MUST affect only the chosen target.
- **FR-010**: Connected remote Sessions MUST use the existing terminal-output activity and output-idle behavior. Ghostel redraw-only events MUST NOT count as Agent output. Output idle MUST NOT imply reported completion or success.
- **FR-011**: When a connection reports its end, the manager MUST retain a disconnected row and clear output-idle and working status. Refresh and selection MUST preserve that row.
- **FR-012**: Disconnected rows MUST offer explicit reattach. Successful reattach MUST reuse the row and existing remote Agent without restarting the Agent or adding a duplicate.
- **FR-013**: Failed attach or reattach MUST report the unavailable target or host. A failed reattach MUST retain its disconnected row. The feature MUST NOT create a replacement or reconnect automatically.
- **FR-014**: With manager persistence enabled, previously attached remote sessions MUST return as disconnected rows after Emacs restarts. Restoration MUST retain target identity and existing saved presentation choices without contacting hosts.
- **FR-015**: With manager persistence disabled, this feature MUST NOT restore saved remote rows. Each Emacs MUST keep its own history without cross-computer synchronization.
- **FR-016**: Another Emacs instance MUST be able to discover and attach the same remote Agent. Attachment MUST NOT restart the Agent or forcibly detach another client.
- **FR-017**: Closing a terminal buffer or exiting Emacs MUST detach only that client. It MUST NOT stop the remote Agent. An open Emacs MUST retain the disconnected row.
- **FR-018**: Explicit Stop MUST require confirmation naming both the host and zmx session and explaining the effect on all clients. Canceling MUST send no stop request.
- **FR-019**: Confirmed Stop MUST affect only the selected remote target. The feature MUST report success only after the host confirms it. An unconfirmed result MUST remain explicit and MUST NOT trigger an automatic retry.
- **FR-020**: Remote failures MUST identify the affected host and provide a corrective action. Failures MUST NOT prevent the user from operating sessions on other hosts or locally.
- **FR-021**: Missing Ghostel or native support MUST produce an explicit user-visible message at the point of use. The feature MUST NOT silently provide incomplete remote behavior.
- **FR-022**: New discovery, attach, reattach, and Stop requests MUST require a currently configured host. Removing a host MUST NOT erase its remembered rows. Those rows MUST explain that reattach requires the user to restore the host configuration.
- **FR-023**: Names supplied by users or remote hosts MUST NOT cause unintended remote actions or change the selected target. Unsupported names MUST produce an explicit error before remote action.

### Key Entities *(include if feature involves data)*

- **Session**: The Emacs-side representation of an Agent, with its terminal, manager presentation, and observed status. Its identity remains distinct from a project name.
- **Zmx session**: The persistent remote terminal and Agent process that survives client detachment. A remote target belongs to one configured host and has a zmx session name.
- **Remote agent**: An Agent inside a zmx session on another machine owned by the user. The user accesses it through an attached terminal in local Emacs.
- **Disconnected session**: A Session whose connection has ended. It retains enough target information for explicit reattach without asserting whether the Agent still runs.
- **Configured host**: A user-approved SSH destination for remote actions and the source of the host label shown in the manager.
- **Output idle**: An observation that a connected Session has produced no output for the existing idle interval. It is not reported Agent state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a three-host walkthrough, the user can switch among one local and two remote Agents without leaving the editor or restarting an Agent.
- **SC-002**: With identical project and session names on two remote hosts, all selection, detach, and Stop actions affect only the intended target.
- **SC-003**: After a detected connection loss, the session row survives refresh and selection. One explicit reattach action restores access without duplicate rows or restarted work.
- **SC-004**: With persistence enabled, every previously attached remote session returns as disconnected after an editor restart. Restoration makes zero remote connections.
- **SC-005**: Closing one of two attached clients leaves the Agent usable from the other. Canceling Stop causes zero stop requests.
- **SC-006**: Every confirmed Stop identifies its host and session before execution. No failed or unconfirmed Stop appears as successful.
- **SC-007**: Every primary walkthrough works without editor-tool integration. A user can identify the host and connection status of each remote row without consulting a separate terminal.
- **SC-008**: When one configured host is unavailable, the user can still select and operate all already connected sessions elsewhere.
- **SC-009**: With a reachable host and prepared Agent, the user can discover, select, and attach within 60 seconds using only the editor.
- **SC-010**: A user completes five of five primary workflows using editor controls, without separate-terminal commands after prerequisite setup.

## Assumptions

- The user owns the machines and has already configured passwordless SSH, trusted host identities, and access to the intended accounts. This feature does not provision credentials or change SSH security settings.
- Remote hosts already provide a usable zmx installation and existing Agent sessions. Remote process creation and arbitrary-process adoption remain outside scope.
- Remote hosts run stock zmx. The feature never requires a patched or minimum zmx version. The user chose this on 2026-09-05 over a patched attach-only option.
- Emacs runs on the user's current computer. The Agent process stays on its remote host when the user changes computers.
- The configured SSH destination is the host label and identity boundary. Two aliases for the same machine remain distinct destinations. Automatic alias reconciliation is outside scope.
- Existing manager persistence controls remote-session history. No new cross-computer history service or automatic host discovery is required.
- Existing terminal-output idle behavior supplies approximate activity information. This feature does not infer actual Agent completion from silence.
- Existing remote Agent configuration remains unchanged. The feature neither repairs stale editor integrations nor promises editor tools after attachment.
- The 60-second target assumes working authentication and an Agent ready for terminal interaction. It measures discovery through usable attachment, not Agent response-generation time.
- **Deferred by the user**: Text-transfer behavior, including cross-session region sending, file transfer, and path translation. This specification neither adds those features nor requires their removal.
- **Deferred by the user**: A redesigned manager UI. The agreed change uses the existing manager with host-qualified labels.
- Other remote editor features, automatic reconnect, remote Agent launch, host provisioning, orchestration, and history synchronization remain outside scope.
