# Feature Specification: Start the Intake from Emacs

**Feature Branch**: `027-intake-from-emacs`

**Created**: 2026-11-09

**Status**: Draft

**Input**: User description: "allow to launch cc-intake in this emacs?"

## Context

The Session Intake (`cci-intake`) is a separate program. Emacs follows it with `claude-code-ide-intake-mode`, and it starts the Master Session through it. Today the user must start the Intake in a terminal before Emacs can use it, and must start it again after each reboot. When the Intake is not running, Intake pull keeps retrying and `claude-code-ide-master` fails. The user wants to start and stop the Intake from the Emacs that uses it.

## Clarifications

### Session 2026-11-09

- Q: When you quit Emacs, should the Intake that Emacs started stop too, or keep running? → A: It stops when Emacs exits. An Intake that must run while Emacs is closed is started outside Emacs.
- Q: When you turn on `claude-code-ide-intake-mode` and no Intake is running, should Emacs start the Intake by itself? → A: Yes, when the Intake command setting is set (the recommendation; the user went to planning without another answer).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Start and stop the Intake from Emacs (Priority: P1)

The user sets the command that starts the Intake on this machine. The user runs one Emacs command to start the Intake and one command to stop it. Emacs shows the Intake output in one buffer. The user sees whether the Intake runs.

**Why this priority**: This is the request. Without it, the user must use a terminal to start the Intake.

**Independent Test**: Set the Intake command setting. Start the Intake from Emacs. `cci projects` answers. Stop it from Emacs. `cci projects` fails to connect, and no Intake process is left.

**Acceptance Scenarios**:

1. **Given** the Intake command setting is set and no Intake answers at the Intake URL, **When** the user runs the start command in Emacs, **Then** the Intake starts on this machine, and Emacs tells the user when the Intake answers.
2. **Given** an Intake that Emacs started, **When** the user runs the stop command, **Then** the Intake process ends, and Emacs tells the user that it stopped.
3. **Given** an Intake that Emacs started, **When** the user runs the restart command, **Then** the Intake stops and starts again, and it reads its configuration again.
4. **Given** an Intake that Emacs started, **When** the user opens the Intake output buffer, **Then** the buffer shows the Intake output since the last start.
5. **Given** the Intake command setting is not set, **When** the user runs the start command in Emacs, **Then** Emacs starts nothing and tells the user which setting to set.

---

### User Story 2 - No second Intake (Priority: P1)

An Intake can already run outside Emacs, for example in a terminal or as a service. Two Intakes on the same configuration would start the same Launches twice. Emacs never starts a second Intake.

**Why this priority**: A second Intake breaks the "exactly once" rule of each Launch. This is a safety rule for User Story 1.

**Independent Test**: Start an Intake in a terminal. Run the start command in Emacs. Emacs starts nothing and says that an Intake already answers.

**Acceptance Scenarios**:

1. **Given** an Intake that answers at the Intake URL and that Emacs did not start, **When** the user runs the start command in Emacs, **Then** Emacs starts nothing and tells the user that an Intake already answers at that URL.
2. **Given** an Intake that Emacs started, **When** the user runs the start command again, **Then** Emacs starts nothing and tells the user that its Intake already runs.

---

### User Story 3 - The Intake starts with Intake pull (Priority: P2)

The user turns on `claude-code-ide-intake-mode`. When the Intake command setting is set and no Intake answers, Emacs starts the Intake first. So one setting in the user's Emacs configuration gives a working Intake after each Emacs start.

**Why this priority**: It removes the manual start after each reboot. User Story 1 works without it.

**Independent Test**: Set the Intake command setting. Make sure no Intake runs. Turn on `claude-code-ide-intake-mode`. The Intake starts, and the mode connects to it.

**Acceptance Scenarios**:

1. **Given** the Intake command setting is set and no Intake answers, **When** the user turns on `claude-code-ide-intake-mode`, **Then** Emacs starts the Intake, and the mode connects to it after it answers.
2. **Given** the Intake command setting is not set, **When** the user turns on `claude-code-ide-intake-mode`, **Then** the mode works as it does today and starts nothing.
3. **Given** an Intake already answers, **When** the user turns on `claude-code-ide-intake-mode`, **Then** Emacs starts nothing, and the mode connects to that Intake.

---

### Edge Cases

- The Intake refuses its configuration and exits at start: Emacs tells the user that the Intake ended at start, with the Intake error line, and keeps the output buffer.
- The Intake that Emacs started ends later without a stop command: Emacs tells the user once that the Intake ended, with its exit status. Emacs does not start it again by itself.
- The Intake does not answer within the start wait: Emacs tells the user that the Intake started but does not answer yet, and points to the output buffer. The process keeps running.
- The user quits Emacs while its Intake runs: Emacs stops the Intake without an extra question. Worker Sessions keep running in zmx. The next Intake start finds them again.
- The user stops the Intake while Launches are starting: the Intake already records each Launch before it acts, so the next start recovers them.
- The user runs the stop command when Emacs did not start the running Intake: Emacs stops nothing and says that it did not start that Intake.
- The Intake URL names another machine: Emacs starts nothing, because it starts the Intake only on this machine.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The package MUST have a user setting for the command that starts the Intake on this machine. The setting MUST be empty by default. The package MUST NOT name a path or a program for it.
- **FR-002**: The package MUST have commands to start, stop, and restart the Intake, and to show the Intake output buffer.
- **FR-003**: Before it starts the Intake, Emacs MUST check whether an Intake answers at the Intake URL. When one answers, Emacs MUST NOT start another.
- **FR-004**: Emacs MUST start the Intake only when the Intake URL names this machine (a loopback address).
- **FR-005**: After a start, Emacs MUST wait for the Intake to answer, up to a fixed time, and then tell the user that it answers, or that it ended, or that it does not answer yet.
- **FR-006**: Emacs MUST keep all Intake output since the last start in one buffer.
- **FR-007**: When the Intake that Emacs started ends without a stop command, Emacs MUST tell the user once, with the exit status and the last error line. Emacs MUST NOT start it again by itself.
- **FR-008**: The stop command MUST end only an Intake that this Emacs started, and it MUST wait until the process has ended.
- **FR-009**: When the Intake command setting is set and no Intake answers, turning on `claude-code-ide-intake-mode` MUST start the Intake first. When the Intake command setting is not set, the mode MUST behave as it does today.
- **FR-010**: When Emacs exits, it MUST stop the Intake that it started, without an extra question.
- **FR-011**: The package documentation MUST show the setting, the commands, and the rule that Emacs never starts a second Intake.

### Key Entities

- **Intake command setting**: the program and arguments that start the Intake on this machine. Emacs runs them in the user's home directory. The user sets the setting in their own Emacs configuration. "The start command" always means the Emacs command that starts the Intake, not this setting.
- **Managed Intake**: the Intake process that this Emacs started. There is at most one. Its output goes to the Intake output buffer.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the Intake command setting set, the user can go from a stopped Intake to a working `cci projects` with one Emacs command, in less than 10 seconds.
- **SC-002**: In 100% of tries, a start command in Emacs while an Intake already answers starts no second Intake.
- **SC-003**: After the stop command, or after Emacs exits, no Intake process that Emacs started is left.
- **SC-004**: After a reboot, the user gets a working Intake and Intake pull by starting Emacs only, with no terminal step.
- **SC-005**: When the Intake refuses its configuration, the user sees the reason in Emacs without opening a terminal.

## Assumptions

- The Intake runs on the same machine as this Emacs. Emacs does not start an Intake on another machine.
- An Intake that Emacs starts lives as long as this Emacs. An Intake that must outlive Emacs is started outside Emacs, as today.
- "Answers" means that the Intake at the Intake URL accepts a connection. Emacs checks this without the token, so the check also works before the token file exists.
- The start wait is about 10 seconds. The Intake usually answers in less than 1 second.
- `claude-code-ide-master` and the other Intake commands do not start the Intake by themselves. Only the start command and `claude-code-ide-intake-mode` start it.
- The Intake itself does not change.
