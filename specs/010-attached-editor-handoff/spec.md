# Feature Specification: Attached-Editor Handoff for Oh My Pi

**Feature Branch**: `main` (unchanged. Feature directory numbering is independent.)

**Created**: 2026-09-13

**Status**: Draft

**Input**: User description: "remote with-editor; omp integration. Now it opens the editor in the remote Emacs when the session was launched by the remote Emacs, which wrapped its own with-editor. Find a way to open in my local Emacs, transparently, to match my local workflow. Modify the omp side: make C-g send an escape sequence to dynamically launch the editor. A restart to pick up the change is not acceptable."

## Clarifications

### Session 2026-09-13

- Q: When the user finishes an edit in the attached Emacs, how should the edited text get back to the Agent? → A: By file. The Agent keeps its file on its host. The local Emacs edits that file through the existing approved remote file access, then signals finish or cancel. The buffer keeps the file's extension so its own major mode (for example Markdown for `.md`) applies.
- Q: Which Agent processes must gain the new behavior without a restart? → A: Processes started after the upgrade. Each pre-upgrade process needs one restart. After that, switching the attached Emacs never needs a restart or a setting.
- Q: When the same Session is visible in two Emacs instances at once, which one should answer the editor request? → A: The one that initiated it, identified by a client nonce. Each Emacs sends its own random nonce with the editor keystroke. The Agent puts that nonce in the request. Only the Emacs whose nonce matches opens the buffer.
- Q: Which Ghostel input modes does the handoff cover? → A: Ghostel terminal-input modes (char and semi-char), where `C-g` and Return go to the terminal. Copy-mode `C-g` keeps leaving copy mode. Line-mode Return keeps its own send, so a `/todo edit` submitted from line mode falls back to the external editor. Line mode is a later upgrade.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Edit a Prompt in the Emacs That Is Attached Now (Priority: P1)

A user attaches from a local Emacs to an Oh My Pi Session that another Emacs created on a remote host. The user presses the external-editor key (`C-g`) inside the Session. The prompt text opens in the local Emacs, the one whose window shows the Session. The user edits, confirms, and the edited text returns to the Session composer. A cancel returns the composer unchanged.

**Why this priority**: This is the reported failure. Today the prompt opens in the Emacs that created the Session, which the user cannot see.

**Independent Test**: Create a Session from a remote Emacs. Attach to it from a local Emacs. Press `C-g` in the composer with some text. Confirm the prompt buffer appears in the local Emacs and the confirmed edit appears in the composer.

**Acceptance Scenarios**:

1. **Given** a Session created by Emacs A and currently attached in Emacs B, **When** the user presses `C-g` in Emacs B, **Then** the prompt buffer opens in Emacs B and not in Emacs A.
2. **Given** the prompt buffer is open in Emacs B, **When** the user confirms the edit, **Then** the composer in the Session shows the edited text and the Session returns to normal input.
3. **Given** the prompt buffer is open in Emacs B, **When** the user cancels the edit, **Then** the composer keeps its previous text and the Session returns to normal input.
4. **Given** the same Session later attached in Emacs A again, **When** the user presses `C-g` in Emacs A, **Then** the prompt buffer opens in Emacs A. No setting or restart is needed between the two attachments.

---

### User Story 2 - Keep the Local Workflow Unchanged (Priority: P2)

A user runs a local Oh My Pi Session in the same Emacs that created it. Pressing `C-g` opens the prompt buffer in the current window the same way it does today, with the same finish and cancel keys and the same window placement.

**Why this priority**: The remote fix must not change the local habit. Local behavior is the reference for remote parity.

**Independent Test**: Start a local Session, press `C-g`, confirm the prompt buffer appears in the current window and the confirmed edit reaches the composer.

**Acceptance Scenarios**:

1. **Given** a local Session created and attached in the same Emacs, **When** the user presses `C-g`, **Then** the prompt buffer opens in the current window with the existing finish and cancel keys.
2. **Given** a local Session, **When** the user confirms or cancels, **Then** the composer result matches today's behavior.
3. **Given** the same Session viewed in two Emacs windows of one Emacs, **When** the user presses `C-g`, **Then** exactly one prompt buffer opens.

---

### User Story 3 - Fall Back Outside Emacs (Priority: P3)

A user attaches to the same Session from a plain terminal, or no Emacs is attached at the moment of `C-g`. The Session opens the user's configured external editor as it does today. The Session never hangs waiting for an editor that does not exist.

**Why this priority**: The Session is a shared terminal process. It must stay usable from every client.

**Independent Test**: Attach to a Session from a plain terminal with an external editor configured. Press `C-g`. Confirm the configured editor opens. Repeat with no editor configured and confirm a visible warning.

**Acceptance Scenarios**:

1. **Given** a Session attached only in a plain terminal with an external editor configured, **When** the user presses `C-g`, **Then** the configured external editor opens within about one second.
2. **Given** a Session attached only in a plain terminal with no external editor configured, **When** the user presses `C-g`, **Then** the Session shows the existing "no editor configured" warning and stays responsive.
3. **Given** a Session with no attached client, **When** an editor request is made, **Then** the Session falls back to the configured external editor and does not wait indefinitely for an Emacs answer.

---

### User Story 4 - Other Prompt Editors Follow the Same Path (Priority: P4)

A user opens the plan editor, the plan annotation editor, or the todo editor from the Session in a Ghostel terminal-input mode. Each opens in the attached Emacs the same way the composer prompt does.

**Why this priority**: These share the same external-editor entry in the Agent. One behavior for all of them avoids a second workflow.

**Independent Test**: Trigger each editor entry from a remotely attached Emacs and confirm the buffer opens in that Emacs.

**Acceptance Scenarios**:

1. **Given** a remotely attached Emacs, **When** the user opens the todo editor, **Then** the todo text opens in that Emacs and the confirmed edit updates the todos.
2. **Given** a remotely attached Emacs, **When** the user opens the plan editor, **Then** the plan opens in that Emacs with its original file extension.

### Edge Cases

- The prompt text is long, for example a pasted multi-page document. Content travels by file (see Clarifications), never through the terminal, so the file system is the only limit. Prompts of at least 64 KB MUST round-trip without truncation or corruption. No size check and no over-limit error exist.
- The prompt text contains quotes, backslashes, tabs, non-ASCII characters, and blank lines. All must round-trip exactly. The Agent's existing single trailing-newline trim applies on both the handoff and the fallback path, exactly as today.
- The user closes the prompt buffer without confirming or canceling. The Session must not block forever. It must accept a later confirm or cancel or a cancel from the Session itself.
- The user presses `C-g` twice before answering the first request. Only one prompt buffer opens per request, and stale answers are ignored.
- Two Emacs instances show the same Session. Only the instance whose nonce is in the request opens a buffer. The other one ignores the request.
- The editor keystroke comes from a plain terminal, so the request carries no nonce. Every Emacs ignores it and the Agent falls back to the external editor.
- A command-driven editor entry such as `/todo edit` carries no editor keystroke. The Emacs sends its nonce together with the Return that submits the command, so the request opens in the Emacs that submitted the command. A plain terminal that submits the command gets no nonce and the Agent falls back.
- The user presses `C-g` in Ghostel copy mode. That key leaves copy mode, as it always did. The handoff applies to `C-g` and Return sent to the terminal from Ghostel char or semi-char mode. Ghostel line mode is not covered: a `/todo edit` submitted from line mode falls back to the external editor.
- A request carries a nonce that no attached Emacs holds, for example after that Emacs detached. Nobody answers, and the Agent falls back after the fixed wait.
- The attached Emacs disconnects while the prompt buffer is open. The Session returns to normal input when the user interrupts it.
- The Emacs that receives the request is not this package's Session owner, for example a plain terminal buffer in Emacs. The request is ignored and the Session falls back to the external editor.
- An older Agent version that does not send the request keeps the existing external-editor behavior in every client.
- An Agent process that started before the Agent upgrade runs old code and keeps the old behavior until that one process restarts. Every process started after the upgrade has the behavior at once, in every client, with no per-Session environment change.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Agent MUST decide where to open the editor at the moment of the request, based on the client attached at that moment, not on settings frozen when the Session was created.
- **FR-002**: An Emacs Session buffer of this package MUST send a per-client random nonce together with the editor keystroke when that keystroke goes to the terminal from a Ghostel terminal-input mode. The Agent MUST remember the most recent nonce received on its input and MUST include it in the next editor request. The Agent MUST offer that request to the attached terminal client before it starts the configured external editor.
- **FR-003**: An attached Emacs that owns the Session and holds the request's nonce MUST accept the request, open the Agent's file on the Agent host through the existing approved remote file access, and route the buffer with the existing prompt-window rules. An Emacs without a matching nonce MUST ignore the request. The buffer MUST keep the file's extension so its own major mode applies, for example Markdown for `.md`.
- **FR-004**: The prompt buffer MUST use the existing finish and cancel keys of the local workflow.
- **FR-005**: On finish, the Emacs MUST save the file and signal finish, and the Agent MUST read the saved file as the edited text. On cancel, the Emacs MUST signal cancel and the Agent MUST keep its previous text.
- **FR-006**: When no attached client accepts the request within a short, fixed wait, the Agent MUST fall back to the configured external editor, or show the existing warning when none is configured.
- **FR-007**: The saved file content MUST reach the Agent byte-exactly for all characters, including quotes, control characters, and non-ASCII text, apart from the Agent's existing single trailing-newline trim, which stays identical on the handoff and the fallback path.
- **FR-008**: The Agent MUST tie each request to a unique identifier and ignore answers that do not match the pending request.
- **FR-009**: The Agent MUST stay interruptible while a request is pending. A user interrupt in the Session MUST cancel the pending request.
- **FR-010**: The package MUST accept a request only in a buffer that is a live owned Session of this package.
- **FR-011**: In a Ghostel terminal-input mode, the behavior MUST apply to every external-editor entry of the Agent: composer prompt, plan edit, plan annotation, todo edit, and the hook instructions editor. Ghostel line mode and copy mode keep their own `Return` and `C-g`.
- **FR-012**: The local workflow, Claude Code, and Codex editor behavior MUST remain unchanged.
- **FR-013**: The behavior MUST require no new environment variables and no per-Session configuration. An Agent process that carries the updated code MUST need no restart to serve any client that attaches later. A pre-upgrade process is out of scope until it restarts.
- **FR-014**: When the attached Emacs has no approved file access to the Agent host, it MUST decline the request so the Agent falls back to the configured external editor, and it MUST tell the user why.

### Key Entities *(include if data involved)*

- **Client Nonce**: A random value that one Emacs Session buffer generates for itself. It travels with the editor keystroke and identifies the initiator of a request.
- **Editor Request**: One request from the Agent to the attached clients. Carries a unique request identifier, the initiator's client nonce, and the path of the Agent's file on the Agent host, including its extension.
- **Editor Answer**: The client's reply to a request. One of acknowledge, finish, or cancel. Carries the request identifier.
- **Prompt Buffer**: The editable buffer in Emacs that visits the Agent's file until the user finishes or cancels.
- **Attached Client**: The terminal program that shows the Session at the moment of the request. It may be an Emacs of this package, another Emacs, or a plain terminal.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In the reported topology (created by remote Emacs, attached in local Emacs), 100% of `C-g` presses sent to the terminal from a Ghostel terminal-input mode open the prompt buffer in the local Emacs and zero open in the remote Emacs.
- **SC-002**: Switching the attached Emacs and pressing `C-g` again opens the buffer in the new Emacs with zero settings changes and zero Session restarts.
- **SC-003**: Prompts up to 64 KB with mixed characters round-trip with zero differences apart from the Agent's existing single trailing-newline trim, on both the handoff and the fallback path.
- **SC-004**: With no accepting client, the external editor or the warning appears within one second of `C-g`.
- **SC-005**: All existing local editor acceptance cases behave exactly as before the change.
- **SC-006**: The package test gate and the Agent test suite pass with zero unexpected results.

## Assumptions

- The Agent is Oh My Pi. Claude Code and Codex keep their current editor mechanism because they have no client request channel.
- A running Agent process cannot pick up new code. Per Clarification 2, one restart per pre-upgrade process is the accepted one-time cost. After it, no restart and no setting is ever needed.
- The Session terminal is Ghostel, per the constitution. A terminal client without this package's handler is a plain terminal for this feature.
- The Session multiplexer forwards terminal output and input between the Agent and the attached client unchanged. This was verified for the output direction.
- The "short, fixed wait" for an acceptance is on the order of half a second, enough to cover remote connection latency.
- The prompt buffer edits the Agent's own file on the Agent host. For a local Session this is a plain local file. For a remote Session it uses the existing approved remote file access. Prompt-buffer patterns and window routing must match the file's path on the Agent host, with or without a remote prefix.
- "Session owner" means this package's live Session record for the buffer that receives the request.
- Two parts change: the Agent (Oh My Pi) and this package. The Agent part lands first, so the package part can be verified against it.
- This specification defines behavior only. Implementation belongs to the planning and implementation phases.
