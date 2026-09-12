# Feature Specification: Predefined Manager Layouts

**Feature Branch**: `main`

**Created**: 2026-09-12

**Status**: Draft

**Input**: User description:

> now we can set the non-agent window to custom function (Default
> to magit status); and choose to on the left or right.
>
> now extend it to support pre-defined layout system, and our current two as
> default options; and the current left magit-status one still be the default
> layout.
>
> then add two new layout.
>
> left ghostel terminal (shell) and right agent.
> and vice versa.

**Additional user request**: Add `Dired left` (`Dired | Agent`) and `Dired right` (`Agent | Dired`) as built-in presets.

## Clarifications

### Session 2026-09-12

- Q: If a user already puts Git on the right, what should happen before they choose a new preset? → A: Ignore the old side preference. Use `Magit left` until the user selects another preset. Saved layouts remain unchanged.
- Q: When two Agent Sessions use the same project directory, should each have its own companion shell? → A: Each Session that uses a shell preset has its own shell, even in the same directory.
- Q: When an Agent Session ends or is removed, what should happen to its companion shell? → A: Keep the shell open. The user closes it separately.
- Q: If you return to a saved layout after its shell has exited, should it start a new shell automatically? → A: Show the exited shell's output and explain that a layout reset starts a new shell. Do not start a replacement automatically.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose the Familiar Content Layouts (Priority: P1)

As a user, I want to select a named layout instead of coordinating separate content and position settings.
The existing Magit-left arrangement must remain the default.
I must also retain my existing custom-content choice.
I also want to browse the Session directory in Dired on either side of the Agent.

**Why this priority**: The new selection system must preserve the current workflow and its custom-content capability.

**Independent Test**: Open a new managed Session with default settings, then apply each Magit preset with a recognizable custom view.
Repeat these checks for each supported Agent.
Apply both Dired presets and verify their directory and orientation with a different custom-content choice configured.

**Acceptance Scenarios**:

1. **Given** unchanged layout and content settings.
   **When** the user opens a new managed Session.
   **Then** Magit status appears on the left and the Agent appears on the right.
   The Agent window receives focus, and the manager sidebar remains in its usual position.
2. **Given** a user-selected custom view.
   **When** the user selects `Magit left` and resets the layout.
   **Then** that custom view appears on the left and the Agent appears on the right.
3. **Given** the same custom view.
   **When** the user selects `Magit right` and resets the layout.
   **Then** the Agent appears on the left and that custom view appears on the right.
4. **Given** a named preset selection.
   **When** the user opens a Session without a saved layout.
   **Then** the preset determines both the companion content and its side without a separate side setting.
5. **Given** a manager action that requests continued manager focus.
   **When** that action builds a preset layout.
   **Then** the manager keeps keyboard focus while the preset places the two content windows correctly.
6. **Given** an old preference that places Git on the right and no explicit preset selection.
   **When** the manager builds a new default layout or the user resets a layout.
   **Then** the layout uses `Magit left`, regardless of the old side preference.
   Returning to a Session still restores its saved arrangement when restoration succeeds.
7. **Given** an active Session and a custom-content choice other than Dired.
   **When** the user selects `Dired left` and resets the layout.
   **Then** Dired shows the Session directory on the left and the same Agent appears on the right.
8. **Given** the same Session and custom-content choice.
   **When** the user selects `Dired right` and resets the layout.
   **Then** the same Agent appears on the left and Dired shows the Session directory on the right.

---

### User Story 2 - Work Beside an Ordinary Shell (Priority: P1)

As a user, I want an interactive shell beside the Agent so I can run project commands without replacing the Agent.
I want to choose which side contains the shell.

**Why this priority**: The two shell presets provide the new arrangements requested by this feature.

**Independent Test**: Apply each shell preset and run a command that reports the shell's directory.

**Acceptance Scenarios**:

1. **Given** an active Session and available Ghostel support.
   **When** the user selects `Shell left` and resets the layout.
   **Then** an ordinary Ghostel shell appears on the left and the same Agent appears on the right.
2. **Given** an active Session and available Ghostel support.
   **When** the user selects `Shell right` and resets the layout.
   **Then** the same Agent appears on the left and an ordinary Ghostel shell appears on the right.
3. **Given** a newly created companion shell.
   **When** the user checks its directory.
   **Then** the shell reports the Session directory, including the selected Worktree rather than another checkout.
4. **Given** either shell preset.
   **When** the user enters a shell command.
   **Then** the shell shows the command output while the Agent remains available beside it.
   The companion shell does not appear as an additional Agent Session.
5. **Given** custom content settings and an Agent that uses another supported terminal.
   **When** the user applies a shell preset with Ghostel available.
   **Then** the companion is a Ghostel shell, not the custom view.
   The Agent keeps its existing terminal.
6. **Given** two Sessions in the same directory on the same host.
   **When** the user applies a shell preset to each Session and changes one shell's directory or runs a command.
   **Then** the other Session's shell keeps its own directory, command, and output.

---

### User Story 3 - Preserve Saved Work and Reset Deliberately (Priority: P2)

As a user, I want my saved window arrangement to remain intact when I change the default preset.
I want the existing reset action to apply the selected preset without restarting the Agent or a live companion shell.

**Why this priority**: A layout preference must not discard an active workflow or interrupt a running command.

**Independent Test**: Save a modified arrangement, change the preset, revisit the Session, and then use the reset action.

**Acceptance Scenarios**:

1. **Given** a saved window arrangement and a newly selected default preset.
   **When** the user revisits that Session.
   **Then** the saved arrangement and its selected window return without applying the new preset.
2. **Given** the same Session.
   **When** the user explicitly resets its layout.
   **Then** the selected preset replaces the saved arrangement.
   The Agent remains the same running Agent.
3. **Given** a saved shell layout with a running command or visible output.
   **When** the user switches away and returns.
   **Then** the same live shell returns with its command, output, and current directory intact.
4. **Given** a live companion shell and the mirrored shell preset.
   **When** the user resets the layout.
   **Then** the same shell moves to the requested side without restarting or opening another shell.
5. **Given** a companion shell whose process has exited or whose buffer the user has killed.
   **When** the user explicitly resets to a shell preset.
   **Then** a new shell starts in the Session directory.
   The Agent remains available.
6. **Given** a Session with a live companion shell that has a running command or visible output.
   **When** the Agent Session ends or the user removes it.
   **Then** the shell remains open as an ordinary terminal with its command, output, and current directory intact.
   The user can continue using the shell and close it separately.
7. **Given** a saved layout whose companion shell has exited but whose output remains available.
   **When** the user returns to that Session.
   **Then** the layout shows the old output without starting a replacement shell.
   The system explains that an explicit reset to a shell preset starts a replacement.
8. **Given** a saved layout whose companion shell the user has closed.
   **When** the user returns to that Session.
   **Then** the Agent remains usable, no replacement shell starts, and the system explains how to reset to a shell preset.

---

### User Story 4 - Use Presets Without Weakening Remote Access Rules (Priority: P2)

As a user with approved remote project access, I want the same preset arrangements beside a remote Agent.
If a companion cannot open, I must retain access to the Agent and understand the failure.

**Why this priority**: The project requires local and remote workflow parity without changing host approval or dependency requirements.

**Independent Test**: Apply the presets to an approved remote Session, then repeat with remote project access disabled or unavailable.

**Acceptance Scenarios**:

1. **Given** an approved remote Session with project access enabled and the required companion support available.
   **When** the user applies each of the six presets.
   **Then** each arrangement matches its local counterpart.
   For a shell preset, a new companion shell starts on the remote host in the Session directory.
   Each Magit preset shows its configured content view for the remote Session directory.
   Each Dired preset shows the Session directory on the remote host, not a local directory.
   Remote companions may appear after preparation because remote access takes time.
   The Agent remains usable during preparation, and the preset determines the companion's side when it appears.
2. **Given** a remote Session with project access disabled.
   **When** the user opens that Session.
   **Then** the existing terminal-only workflow remains unchanged.
   A preset does not enable project access or open an additional connection.
3. **Given** enabled remote project access that fails or an unsupported remote shell environment.
   **When** the user requests the affected preset.
   **Then** the system explains why the companion is unavailable and leaves the Agent usable.
   It does not substitute a local shell.

### Edge Cases

- Magit is unavailable, or the custom-content choice fails or produces no usable view.
  Preserve the existing directory-browser fallback for Magit presets.
- Ghostel or its required native support is unavailable, or shell startup fails.
  Report the missing support or startup failure without installing software or silently selecting another preset.
  Keep the Agent usable.
- The Session directory no longer exists or cannot be accessed.
  Explain the directory problem instead of showing Dired or starting a shell in an unrelated directory.
  Keep the Agent usable.
- The saved companion shell has exited or the user has closed it.
  Returning to the Session must not start a replacement shell automatically.
  Show its old output when available and explain that an explicit reset to a shell preset starts a replacement.
  Keep the Agent usable without presenting an exited shell as live.
- The window is too narrow for two content windows.
  Report that the split cannot fit and keep the Agent usable.
- The preset value does not identify an available preset.
  Reject it with an explanation rather than silently choosing another arrangement. Keep the Agent usable.
- Remote shell support requires a supported remote operating system.
  Ghostel's existing remote shell support excludes Windows hosts because it requires POSIX shell facilities.
- Two Sessions use the same directory, different Worktrees, or different hosts.
  When companion shells are present, Sessions must never share them.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide these six built-in presets:

  | Preset | Left content window | Right content window |
  | --- | --- | --- |
  | Magit left | Custom content, defaulting to Magit status | Agent |
  | Magit right | Agent | Custom content, defaulting to Magit status |
  | Shell left | Ordinary Ghostel shell | Agent |
  | Shell right | Agent | Ordinary Ghostel shell |
  | Dired left | Dired showing the Session directory | Agent |
  | Dired right | Agent | Dired showing the Session directory |

  Left and right describe the two content windows, not the manager sidebar.
  These labels identify the arrangements without prescribing a selection interface.
- **FR-002**: Users MUST be able to choose one named preset as the manager's default layout through the existing preference workflow.
  One selection MUST determine both the companion type and its side.
  An invalid selection MUST produce an explanation rather than silently select a different preset.
  An invalid selection MUST leave the Agent usable.
  The old separate side preference MUST NOT control new default layouts or explicit resets.
- **FR-003**: `Magit left` MUST remain the default preset.
  Without a custom-content override, it MUST show Magit status left of the Agent.
- **FR-004**: For this feature, both Magit presets MUST retain the existing custom-content capability for the Session directory as temporary compatibility.
  Changing orientation MUST NOT replace the user's custom-content choice.
- **FR-005**: Each shell preset MUST provide an ordinary interactive Ghostel shell that uses the user's existing shell preferences.
  The shell MUST remain separate from the Agent and MUST NOT create an additional managed Agent Session.
  The Agent's terminal choice MUST remain unchanged.
- **FR-006**: A new companion shell MUST start in the Session directory on the Session's host.
  It MUST NOT start in another Worktree or substitute a local directory for a remote directory.
  An inaccessible directory MUST produce an explanation and leave the Agent usable.
- **FR-007**: The selected preset MUST apply when the manager builds a new default layout or the user explicitly resets a layout.
  A normal return to a Session MUST retain its saved arrangement and selected window when restoration succeeds.
  Returning to a saved layout with an exited or missing companion shell MUST NOT start a replacement shell automatically.
  The system MUST show the old output when available and explain how to start a replacement with an explicit shell-preset reset.
  The Agent MUST remain usable.
  A missing or exited companion shell alone MUST NOT trigger fallback to a new default layout.
  Restore the remaining layout and keep the Agent visible when the old shell window cannot return.
- **FR-008**: If a saved layout contains a live companion shell, restoration MUST reuse that shell.
  An explicit reset to a shell preset MUST also reuse the Session's live companion shell when one exists.
  These actions MUST preserve that shell's running command, output, and current directory.
  If no live companion shell exists, an explicit reset to a shell preset MUST create a replacement in the Session directory.
  Sessions MUST NOT share a companion shell, even when they use the same directory on the same host.
  Commands, output, and directory changes in one companion shell MUST NOT affect another Session's companion shell.
- **FR-009**: Applying a preset MUST preserve the Agent and the manager sidebar.
  A newly built layout MUST select the Agent window unless the invoking action requests continued manager focus.
- **FR-010**: Magit presets MUST preserve the existing directory-browser fallback when Magit or the chosen custom content is unavailable.
- **FR-011**: Missing Ghostel support or shell startup failure MUST produce an actionable explanation and leave the Agent usable.
  The system MUST NOT silently substitute another companion or install software.
  Magit and Dired presets MUST NOT introduce a Ghostel dependency.
- **FR-012**: A failed window split MUST produce an explanation and leave the Agent usable.
- **FR-013**: Approved remote Sessions with project access enabled MUST use the same preset arrangements and saved-layout rules as local Sessions.
  Shell companions MUST use existing supported remote shell access.
  An unavailable companion MUST NOT prevent terminal attachment or cause a local-shell substitution.
  Remote companion preparation may finish after terminal attachment because remote access takes time.
  The Agent MUST remain usable during preparation. The selected preset MUST determine the eventual companion type and side.
- **FR-014**: Preset selection MUST NOT approve a host, enable disabled remote project access, or install remote software.
  Remote Sessions with project access disabled MUST retain their existing terminal-only behavior.
  Disabled access means the user has not enabled project access for that host.
  Enabled access that fails MUST produce an explanation. Disabled access MUST preserve the existing terminal-only workflow.
- **FR-015**: Presets MUST apply to supported Agents through the shared manager workflow, not through Agent-specific layout choices.
- **FR-016**: Both Dired presets MUST show the Session directory in Dired on the Session's host, regardless of the custom-content setting.
  They MUST leave the custom-content setting unchanged.
  They MUST NOT require Magit or replace a remote directory with a local directory.
  An inaccessible directory MUST produce an explanation and leave the Agent usable.
- **FR-017**: When an Agent Session ends or is removed, its live companion shell MUST remain open as an ordinary terminal.
  The system MUST NOT terminate or restart the shell or its running command because the Session ended.
  The shell MUST retain its output and current directory. The user closes it separately.
  A temporary disconnection alone MUST NOT end the companion relationship while the same Session remains available for reattachment.
  Shell survival applies within the running Emacs instance, not across Emacs shutdown.

### Key Entities

- **Layout preset**: A named arrangement that determines the companion type and the relative positions of the companion and Agent.
- **Session**: The managed Agent's existing state, including its Session directory, host, terminal, and saved window arrangement.
- **Companion**: The custom view, Dired view, or ordinary shell displayed beside the Agent.
  A companion shell is not an Agent Session.
  Each companion shell belongs to exactly one Session, not to a shared directory or Worktree.
  After its Session ends or is removed, the shell remains an ordinary terminal and no longer serves as that Session's companion.
  A shell is live while its process runs. It is exited when that process has ended.
  A killed shell buffer is missing. Closing only its window does not end a live shell.
- **Saved layout**: A Session's user-adjusted window arrangement and selected window.
  It takes precedence over the default preset until the user resets it or restoration fails.
  An exited or missing companion shell alone is not a reason to replace the saved layout with the default preset.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All six presets display the specified left and right content in every acceptance run on supported local and remote environments.
- **SC-002**: Every default-settings acceptance run displays the existing project status view left of the Agent.
- **SC-003**: A user can select any of the six arrangements with one preset choice and apply it with one existing reset action.
  No separate content-side choice or manual window rearrangement is necessary.
- **SC-004**: Both shell arrangements let the user run a command in the Session directory and see its output beside the same Agent.
  Both arrangements pass this check.
- **SC-005**: Every successful saved-layout restoration preserves the selected window and running Agent.
  If that layout contains a live companion shell, restoration preserves the same shell and its running command, output, and current directory.
  Every successful explicit reset displays the selected preset without restarting the Agent or any existing live companion shell.
  Every Session-end acceptance run with a live companion shell leaves that shell usable with its command, output, and current directory intact.
  Returning to an exited or missing saved companion shell starts no replacement process and explains the explicit reset action.
- **SC-006**: Every missing-support, startup-failure, invalid-directory, invalid-preset, or split-failure acceptance run leaves the Agent usable and explains the problem.
- **SC-007**: Custom content appears correctly in both orientations without changing the user's custom-content choice.
  Both orientations pass this check when the companion shell feature is unavailable.
- **SC-008**: Both Dired arrangements show the correct Session directory beside the same Agent, regardless of the custom-content choice.
  Both arrangements pass with Magit and companion-shell support unavailable.

## Assumptions

- This feature extends the existing manager preference and reset workflow.
  It does not add a general layout editor or require a new preset-selection menu.
- The shipped preset set contains six choices.
  For this feature, the custom-content setting remains available within the two Magit presets as temporary compatibility.
  The long-term goal is to remove that setting and let users define a custom layout as a whole.
  A custom layout will define the full arrangement, not only the content of the non-Agent window.
  Whole-layout customization and removal of the original custom-content system belong to a later feature.
- The old separate side preference no longer controls new default layouts or explicit resets.
  Without an explicit preset choice, these actions use `Magit left`.
  Existing saved layouts retain their positions until reset or restoration failure.
  An exited or missing companion shell alone does not trigger default-layout fallback.
- A companion shell follows ordinary Ghostel shell preferences.
  This feature does not add command execution on the user's behalf or persistence across editor restarts.
  Output availability after shell exit follows the user's Ghostel exit preference.
  If Ghostel kills the exited shell's buffer, the missing-shell behavior applies.
- Live shell reuse protects an existing Session's work.
  Shells belong to individual Sessions and remain distinct even when their hosts and directories match.
- Remote project access and host approval remain prerequisites for remote companion layouts.
  Existing supported remote shell environments define shell availability.
- Magit and Dired presets do not introduce a companion-shell dependency.
  Existing Agent terminal requirements remain unchanged.
