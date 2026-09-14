# Feature Specification: Fix Remote Session Toggle

**Feature Branch**: `main` (unchanged. Feature directory numbering is independent.)

**Created**: 2026-09-14

**Status**: Draft

**Input**: User description: "claude-code-ide-toggle does not work when attaching a remote one; idea?"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Toggle the Attached Remote Session (Priority: P1)

A user attaches an existing Agent on a remote host. The user invokes the standard session toggle from that Agent Session, its managed remote project view, or its remote Magit buffer. The command hides or restores the matching attached Session, just as it does for a local Session.

**Why this priority**: The standard toggle is a primary navigation action. Failure forces remote users into a separate workflow and breaks local and remote parity.

**Independent Test**: Attach a remote Agent whose project directory text also exists locally or on another host. Invoke the toggle from its terminal, managed project view, and remote Magit buffer. Confirm that each invocation affects only the matching remote host.

**Acceptance Scenarios**:

1. **Given** a visible attached remote Session, **When** the user invokes the standard toggle from its terminal, **Then** the command hides that Session without reporting that no Session exists.
2. **Given** a hidden attached remote Session, **When** the user invokes the standard toggle from its managed remote project view, **Then** the command restores that same Session and its saved layout.
3. **Given** local and remote Sessions with the same project directory text, **When** the user toggles from the remote context, **Then** only the Session on the matching remote host changes visibility.
4. **Given** an attached remote Session without optional remote project access, **When** the user invokes the toggle from its terminal, **Then** terminal visibility still toggles normally.
5. **Given** a remote Magit buffer for an attached Session's host and project path, **When** the user invokes the toggle, **Then** the matching host-specific Session changes visibility.

---

### User Story 2 - Preserve Existing Local Toggle Behavior (Priority: P2)

A user continues to use the standard toggle for local Sessions without any new prompt or workflow.

**Why this priority**: Remote parity must not change a stable local navigation action.

**Independent Test**: Invoke the toggle from a local project buffer and a local Agent Session. Confirm that the existing Session hides and restores with no remote selection prompt.

**Acceptance Scenarios**:

1. **Given** a local project with one active Session, **When** the user invokes the toggle from its project buffer, **Then** the existing local Session changes visibility.
2. **Given** a local Agent Session, **When** the user invokes the toggle from its terminal, **Then** the command affects that Session exactly as before.
3. **Given** no Session for the current local project, **When** the user invokes the toggle, **Then** the command retains the existing explicit no-session error.

### Edge Cases

- A local Session and a remote Session can use identical project directory text. The host identity must prevent cross-session selection.
- Two remote hosts can use identical project directory and Session names. The current remote context must select the correct host.
- A remembered remote target can be disconnected and have no live terminal. The toggle must not create, attach, or reconnect it.
- The active remote terminal can exist without remote project access. Terminal attachment remains sufficient context for the toggle.
- A managed remote project view can remain visible after its terminal hides. A later toggle must restore the associated terminal layout.
- A remote Magit buffer can identify a Session by host and project path when no exact managed-view ownership exists.
- A remote context with no associated live Session must report an explicit no-session result and must not select a same-named local Session.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The standard session toggle MUST support attached remote Sessions wherever the corresponding local workflow supports local Sessions.
- **FR-002**: When invoked from a remote Agent terminal, the command MUST use that terminal's owning Session before any project-directory fallback.
- **FR-003**: When invoked from a managed remote project view, the command MUST use the Session associated with that view, including its host identity.
- **FR-003A**: When invoked from a remote Magit buffer, the command MUST select a live Session by exact remote host and project path.
- **FR-004**: The command MUST distinguish Sessions by remote host and Session identity, not by project directory text alone.
- **FR-005**: Hiding and restoring a remote Session MUST preserve the existing saved layout and focus behavior used by the managed view.
- **FR-006**: The toggle MUST work for an attached remote terminal when optional remote project access is disabled or unavailable.
- **FR-007**: The toggle MUST NOT initiate remote discovery, attachment, reattachment, Agent creation, or network access.
- **FR-008**: A disconnected remembered target without a live terminal MUST remain disconnected. The command MUST report that no live Session can be toggled.
- **FR-009**: A remote context without an associated live Session MUST NOT fall back to a local Session with matching directory text.
- **FR-010**: Existing local toggle behavior, messages, layout restoration, and focus behavior MUST remain unchanged.
- **FR-011**: When no applicable live Session exists, the command MUST provide an explicit user-visible explanation.

### Key Entities *(include if feature involves data)*

- **Session**: An Agent connection owned by the editor, with a terminal, identity, project directory, visibility, and saved layout.
- **Remote Session**: A Session associated with a specific approved host and an existing remote Agent target.
- **Remote Context**: The active remote terminal, managed project view, or remote Magit buffer that identifies the intended Session and host.
- **Remembered Target**: A disconnected remote entry retained for explicit reattachment. It is not a live Session for toggle purposes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users hide and restore an attached remote Session with one invocation per state change and zero Session-selection prompts.
- **SC-002**: In all same-directory tests across one local and two remote hosts, the toggle affects only the Session associated with the active context.
- **SC-003**: All remote terminal toggle scenarios complete without remote discovery, reconnection, or Agent restart.
- **SC-004**: Existing local toggle scenarios produce unchanged visible results and unchanged error results.
- **SC-005**: A user completes ten consecutive hide-and-restore cycles for a remote Session without a wrong target, duplicate Session, or lost layout.
- **SC-006**: All unavailable-session scenarios show an explicit result within one second and leave every other Session unchanged.

## Assumptions

- “Attaching remote one” means attaching an existing remote Agent Session through the project's supported remote attachment workflow.
- The standard toggle is `claude-code-ide-toggle`, and the user expects the same action for local and remote Sessions.
- A live remote terminal or its managed project view provides enough existing context to identify the owning Session.
- This feature fixes visibility and navigation only. It does not add attachment, automatic reconnection, discovery, or remote project access.
- Existing explicit host approval and Session ownership rules remain unchanged.
- A disconnected remembered target requires the existing explicit reattach action before it can be toggled.
