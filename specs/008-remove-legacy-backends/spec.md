# Feature Specification: Ghostel-Only Terminal Support

**Feature Branch**: `main`

**Created**: 2026-09-12

**Status**: Draft

**Input**: User description:

> now as said; remove eat and vterm support and related stuff from code

Additional user requirement:

> and make sure README and all places refer to it removed; and add this to distinction in README to originl repo

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Keep the Existing Ghostel Workflow (Priority: P1)

As a user, I want Ghostel to be the only terminal choice without losing my existing Agent workflow.
The removal must simplify terminal support, not change which Agents I can use or how I manage Sessions.

**Why this priority**: Removing alternative terminals is useful only if the remaining terminal preserves the working product.

**Independent Test**: With Ghostel available and both removed terminals absent, exercise the existing Session workflow for every supported Agent.
Repeat existing remote attachment checks on an approved host.

**Acceptance Scenarios**:

1. **Given** Ghostel is available and neither removed terminal is installed.
   **When** the user starts, continues, or resumes a supported Agent through an existing entry point.
   **Then** the Agent uses Ghostel with its existing command, directory, and Session identity rules.
   No terminal selection is required.
2. **Given** an active Ghostel Agent Session.
   **When** the user sends text, submits input, interrupts the Agent, scrolls output, or uses an existing clipboard capability.
   **Then** each operation retains its current behavior and Agent-specific capability limits.
   Activity tracking and notifications continue to identify the correct Session.
3. **Given** an existing managed Session and any of the six layout presets.
   **When** the user switches Sessions, restores a saved layout, or explicitly resets the layout.
   **Then** the Agent, companion placement, selected window, and live companion-shell reuse retain their existing behavior.
4. **Given** an existing persistent Agent session, either local or on an approved remote host.
   **When** the user attaches, detaches, reconnects, or explicitly stops it through the existing workflow.
   **Then** Ghostel preserves the current identity, confirmation, and ownership rules.
   Detach does not become Stop, and attachment does not start a replacement Agent.
5. **Given** remote project access is disabled or its companion preparation fails.
   **When** the user accesses an otherwise available remote Agent terminal.
   **Then** terminal access remains independent of optional project views.
   The removal does not approve a host, create an extra connection, or substitute a local terminal for a remote one.

---

### User Story 2 - Remove the Old Terminal Support Completely (Priority: P1)

As a maintainer, I want the removed terminals and their supporting machinery gone, rather than hidden behind unused settings.
As a user, I want one clear terminal requirement and a useful explanation when it is unavailable.

**Why this priority**: Retained compatibility paths would preserve the maintenance burden that this removal is intended to eliminate.

**Independent Test**: Review the complete repository removal inventory and exercise startup with Ghostel available, unavailable, and unable to start.

**Acceptance Scenarios**:

1. **Given** the completed removal.
   **When** a maintainer checks runtime behavior, settings, tests, dependency setup, and automation.
   **Then** none retain support, installation instructions, dependency discovery, or compatibility paths for either removed terminal.
   Backend-specific workarounds and obsolete terminal-choice settings are absent.
2. **Given** an old configuration still assigns a removed terminal preference.
   **When** the user loads the package and starts a new Session with Ghostel available.
   **Then** the obsolete preference has no effect on terminal choice.
   The package neither loads a removed terminal nor preserves a compatibility alias for that preference.
3. **Given** Ghostel or its required native support is unavailable.
   **When** the package loads or the user requests a terminal operation.
   **Then** package loading and non-terminal functions remain available.
   The terminal operation explains the missing support and the corrective action without installing software or choosing another terminal.
4. **Given** Ghostel cannot start in the requested Session directory.
   **When** the user requests a new terminal.
   **Then** the failure does not report a successful Session, start in another directory, or stop an existing Session.
5. **Given** the user also uses unrelated terminal buffers or separately installed terminal packages.
   **When** this package loads or performs Session management.
   **Then** it does not adopt, modify, kill, or uninstall those unrelated terminals.
   A terminal buffer alone does not establish ownership as an Agent Session.

---

### User Story 3 - Read One Consistent Support Policy Everywhere (Priority: P1)

As a user or contributor, I want every repository reference to describe the same Ghostel-only product.
The README must make this terminal policy visible as a deliberate difference from the original repository.

**Why this priority**: Old requirements, examples, and support promises would send users toward functionality that no longer exists.

**Independent Test**: Review the README and a repository-wide reference inventory, including less-visible documentation, automation, and prior feature documents.

**Acceptance Scenarios**:

1. **Given** the updated README.
   **When** a reader checks its comparison with the original repository.
   **Then** that comparison explicitly identifies Ghostel-only terminal support as a distinction of this fork.
   The original repository attribution remains intact.
2. **Given** the updated repository.
   **When** a reader follows its requirements, installation guidance, configuration examples, feature descriptions, or troubleshooting instructions.
   **Then** none recommend, advertise, configure, or explain operation of a removed terminal.
   All terminal guidance consistently describes Ghostel.
3. **Given** older feature documents, maintainer instructions, governance documents, comments, or backlog items mention the removed support.
   **When** the removal is reviewed.
   **Then** those references are included in the cleanup rather than excluded because they are outside runtime code or the README.
   Only explicit records of this removal may name the retired products as historical context.
4. **Given** the current constitution still requires multiple terminal backends.
   **When** the Ghostel-only implementation is authorized.
   **Then** the project first amends that conflicting requirement through its governance process and aligns related guidance.
   This feature specification alone does not override the constitution.

### Edge Cases

- An old global or per-Agent terminal preference remains in a user's configuration.
  It must not select a removed terminal or revive a compatibility path.
- Ghostel is missing, its native support is unavailable, or startup fails.
  Preserve package loading and existing Sessions, and explain the failure at the requested terminal operation.
- A saved layout refers to a terminal buffer that no longer exists after an editor restart.
  Use existing missing-buffer recovery without restoring a removed terminal or falsely reporting a live Agent.
- A user has an ordinary shell beside an Agent or uses another terminal package outside this integration.
  Preserve the distinction between an owned Agent Session and an unrelated terminal.
- A remote host is unapproved, unavailable, or unsupported by the existing Ghostel remote workflow.
  Preserve current admission checks and explanations, without a local fallback or automatic installation.
- Removing an old terminal workaround must not remove the corresponding behavior that Ghostel still needs.
  This includes focus, resizing, scrolling, input, activity tracking, and process cleanup.
- A reference appears in a prior feature document, hidden automation file, test helper, or dependency script.
  Include it in the cleanup rather than limiting the search to visible source files.
- A text search matches an unrelated word rather than a terminal product or identifier.
  Do not remove unrelated text, legal notices, or other product capabilities merely to eliminate a substring.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Ghostel MUST be the only supported terminal runtime for this package's Agent Sessions and terminal companions.
  This applies to every supported Agent and every existing local or remote terminal entry point.
- **FR-002**: The package MUST remove EAT and vterm support rather than disable it.
  Removal MUST cover their terminal creation, recognition, input, display, hooks, callbacks, cleanup behavior, compatibility aliases, and backend-specific workarounds.
- **FR-003**: The package MUST remove terminal-choice settings and per-Agent terminal overrides that exist solely to choose among these terminal backends.
  Legacy assignments MUST NOT control new terminal creation or cause removed support to load.
  No compatibility alias or fallback to a removed terminal may remain.
- **FR-004**: Existing Ghostel Session operations MUST retain their observable behavior.
  This includes launch, continue, resume, text and clipboard input, supported image paste, submission, interruption, scrolling, resizing, focus, activity tracking, and notifications.
  Existing Agent capability limits MUST remain unchanged.
- **FR-005**: Local persistent-session adoption and remote attachment MUST retain their existing Session identity, process ownership, detach, reconnect, and explicit Stop rules.
  The removal MUST NOT start replacement Agents or terminate unrelated processes.
- **FR-006**: The six existing layout presets, saved-layout precedence, selected-window restoration, and companion-shell lifecycle MUST remain unchanged.
  Generic Agent popup placement and manager sidebar behavior MUST remain unchanged.
- **FR-007**: Ghostel MUST remain an optional dependency for package loading, compilation, automated verification, and non-terminal operations.
  A terminal operation that lacks Ghostel or its native support MUST give an actionable explanation without automatic installation or terminal substitution.
- **FR-008**: Terminal startup failures MUST preserve existing Sessions and report the actual failure.
  The package MUST NOT report a successful Session or silently start in an unrelated directory or host.
- **FR-009**: Remote admission, disabled project-access behavior, and separation between terminal attachment and optional project views MUST remain unchanged.
  The removal MUST NOT expand remote access or Agent capabilities.
- **FR-010**: Tests, test helpers, mocks, dependency discovery, installation setup, and automation MUST no longer implement or require either removed terminal.
  Coverage of surviving Ghostel behavior MUST remain meaningful, including failures when optional terminal support is absent.
- **FR-011**: The cleanup MUST cover every maintained repository location that refers to the removed terminal support.
  This includes the README, other documentation, configuration examples, comments, maintainer guidance, governance, backlog items, and prior feature specifications, plans, tasks, and checklists.
  No document may continue to promise, recommend, configure, or validate the removed support.
- **FR-012**: The README MUST explicitly list Ghostel-only terminal support among this fork's distinctions from the original repository.
  Its overview, requirements, installation, feature descriptions, configuration guidance, and troubleshooting MUST agree with that distinction.
  Original repository attribution MUST remain intact.
- **FR-013**: Remaining references to the retired terminal products MUST be limited to explicit removal records, including this specification and the required governance amendment record.
  Each such reference MUST describe the removal, not preserve a setup example, callable compatibility path, or ongoing support obligation.
- **FR-014**: The project MUST amend the constitution's conflicting terminal-support requirement before authorizing the removal implementation.
  Related verification and optional-dependency wording MUST reflect the new policy without weakening those safeguards or unrelated governance principles.
- **FR-015**: The removal MUST preserve shared behavior across supported Agents and MUST NOT add Agent-specific terminal policy.
  It MUST NOT uninstall external packages, rewrite Git history, or change unrelated terminal workflows outside this package.

### Key Entities

- **Agent Session**: An existing managed Agent, with its identity, host, directory, terminal, and lifecycle ownership.
- **Terminal runtime**: The terminal product used to display and interact with an Agent or ordinary companion shell.
  Ghostel is the sole supported runtime after this removal.
- **Companion shell**: An ordinary Ghostel shell associated with a Session layout, distinct from the managed Agent and its lifecycle.
- **Removal record**: A document that explicitly records the retirement of old support rather than instructing users to use it.
  It is not an alternative source of current support policy.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every supported Agent completes the existing launch and interaction acceptance scenarios using the sole supported terminal, with zero terminal-choice steps.
- **SC-002**: All six layout presets pass their existing placement, focus, restoration, and companion-reuse checks without restarting a live Agent or companion shell.
- **SC-003**: Every tested missing-support or startup-failure case gives an actionable explanation and preserves existing Sessions.
  No case automatically installs software or substitutes another host, directory, or terminal.
- **SC-004**: A repository-wide review finds zero remaining support paths, dependencies, active examples, or support promises for the retired terminals.
  Every residual product reference belongs to an explicit removal record.
- **SC-005**: A reader can identify the sole supported terminal from both the README requirements and the original-repository comparison.
  A complete documentation review finds zero contradictory terminal-support instructions.
- **SC-006**: Existing local and approved remote lifecycle acceptance scenarios pass with no new connections, lost Session ownership, or changed Stop confirmations.
- **SC-007**: The required automated quality gate passes without either retired terminal installed.
  Package loading and the terminal-unavailable checks also pass without the remaining optional terminal installed.

## Assumptions

- This command creates the specification and quality checklist, not the removal implementation or its implementation plan.
- The request defines a clean cutover to Ghostel, not a deprecation period or a new extensible terminal selection system.
- Existing Ghostel behavior is the reference for retained functionality.
  The removal does not add features that Ghostel does not currently provide or broaden existing remote capabilities.
- A supported upgrade may require restarting Emacs.
  Automatic conversion of already-running retired-terminal buffers is not part of this removal, and the package must not destroy those buffers or processes.
- Repository-wide cleanup includes prior feature documents and hidden project automation.
  It does not edit external repositories, installed terminal packages, unrelated Spacemacs configuration, legal text, or immutable Git history.
- Naming the retired products in this specification is necessary to define the removal scope and preserve the original request.
  Such removal records are the only exception to removing their repository references.
- Constitution version 2.0.0 establishes Ghostel-only terminal support under Principle IV.
  The 2026-09-12 amendment also aligns Principles II and III while preserving batch verification and optional dependencies.
  The governance prerequisite in FR-014 is complete.
  Implementation planning must evaluate the amended constitution before authorizing the removal.
