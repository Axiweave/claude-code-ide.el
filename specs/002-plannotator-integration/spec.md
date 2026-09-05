# Feature Specification: Plannotator review integration

**Feature Branch**: `002-plannotator-integration`

**Created**: 2026-09-04

**Status**: Draft

**Input**: User description: "Integrate Plannotator plan review, code review, and document annotation with claude-code-ide.el through the integration route: Emacs owns the agent session and browser dispatch, Plannotator owns the review UI and feedback loop. Optionally show review state in the manager sidebar."

Grounding documents: `ref-docs/plannotator-functionality-gap.md` (research report, local and uncommitted) and `CONTEXT.md` (glossary). Terms below (Session, Agent, Agent state) follow the glossary. "Review" means one Plannotator plan review, code review, or annotation surface, opened once and closed once.

## Clarifications

### Session 2026-09-04

- Q: Should the Plannotator integration be on or off by default when the package loads? → A: Off by default; the user enables it once with one setting.
- Q: Which user stories are in scope for this feature's first delivery? → A: Stories 1 and 2. Story 3 (start a review from Emacs) is deferred to a later feature.
- Q: When the user's own shell environment already sets a Plannotator browser or project-root value, should the Emacs integration override it? → A: Emacs overrides. When the setting is on, Emacs always wins for Sessions it starts.
- Q: When several Emacs instances run at once, which one should receive the review page for a Session? → A: The Emacs that started the Session. Emacs records its own server identity into the Session so the hand-off targets that instance; if that instance is gone, Plannotator's fallback applies.
- Q: When the integration is on and no Emacs server runs at Session start, what should Emacs do? → A: Warn and continue. Emacs shows a one-time warning that reviews will use Plannotator's fallback until the server runs; it does not start the server itself.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Review opens in the user's Emacs-configured browser (Priority: P1)

A user has installed the Plannotator plugin for their Agent. They start an Agent Session from Emacs. When the Agent reaches a plan gate, or the user runs a Plannotator review command inside the Agent terminal, the review page opens in the browser the user configured in Emacs, instead of a browser Plannotator guesses on its own. The user annotates in Plannotator, submits, and the Agent receives the feedback exactly as it does without Emacs.

**Why this priority**: This is the core value. It gives Emacs control of where the review appears without changing the review or feedback loop, and it needs the least new behavior.

**Independent Test**: Start an Agent Session from Emacs, trigger a review, and verify the page opens through the Emacs browser setting. Then submit feedback and verify the Agent receives it.

**Acceptance Scenarios**:

1. **Given** a Session started from Emacs and Emacs is running, **When** a review starts, **Then** the review page opens through the user's Emacs browser setting.
2. **Given** a Session started from Emacs, **When** the user submits approval or annotations in the review page, **Then** the Agent receives the decision through its existing Plannotator plugin with no involvement from Emacs.
3. **Given** a Session started from Emacs and Emacs has since exited, **When** a review starts in that Session, **Then** Plannotator's own fallback still shows the review address in the terminal, and the Agent is never left waiting with no address.
4. **Given** a Session started from Emacs, **When** a review starts, **Then** Plannotator resolves the project root to the Session's project directory and labels the review with the Session's Agent type.
5. **Given** the integration setting is off, **When** a Session starts, **Then** behavior is unchanged from today: Plannotator uses its own browser selection.

---

### User Story 2 - Manager shows that a review is waiting (Priority: P2)

While a review is open, the manager sidebar marks the owning Session as waiting for input, the same way an Agent that asks a question is marked. When the review closes, the marker clears.

**Why this priority**: A user who runs several Agents needs to know which Session is blocked on a review. It builds on Story 1 and adds a second signal path.

**Independent Test**: Start a review in one of two Sessions and verify only that Session shows the waiting marker. Close the review and verify the marker clears.

**Acceptance Scenarios**:

1. **Given** two live Sessions, **When** a review starts in one, **Then** only that Session shows the waiting marker in the manager.
2. **Given** a Session with the waiting marker, **When** the review process ends normally, **Then** the marker clears within a few seconds.
3. **Given** a Session with the waiting marker, **When** the review process is killed without a normal exit, **Then** the marker still clears within a short period after the process is gone.
4. **Given** a Session with the waiting marker and no review-completion signal can be found, **When** the user runs the clear-review-state command, **Then** the marker clears.
5. **Given** two reviews run back to back in one Session, **When** the second starts, **Then** the marker returns, even when the second review uses the same address as the first.

---

### Out of Scope - Start a review from Emacs

An Emacs command that types the Agent-specific Plannotator review or annotate command into the Session terminal is deferred to a later feature (Clarifications, 2026-09-04). Users type the command in the terminal themselves; the rest of the flow is Story 1.

---

### Edge Cases

- Emacs is running but cannot open a browser (no display, browser function errors): Plannotator's fallback prints the address, and the Session still works.
- The review process starts before the manager can learn its identity: the waiting marker appears immediately and identity is retried for a short period.
- The review-state file grows across many reviews in one long Session: only new entries are processed, never the whole file again.
- The Plannotator state directory is relocated by the user: completion detection follows the relocated directory.
- A Session is reattached from another Emacs instance or after an Emacs restart: the hand-off still targets the Emacs that originally started the Session. When that instance is gone, Plannotator's fallback prints the address. Per `CONTEXT.md`, environment fixed at zmx-creation time is an accepted limitation.
- Several Emacs instances run at once: each Session's review opens in the instance that started it, never in another.
- The Emacs server is not running when a Session starts: Emacs warns once, does not start the server, and reviews use Plannotator's fallback until the server runs.
- The user's shell already sets Plannotator values: for Sessions Emacs starts with the integration on, the Emacs values replace them.
- The user closes the browser tab without submitting: the marker stays until the review process ends or the user clears it.
- Two Sessions share a project directory: each Session gets its own review-state file and its own marker.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Users MUST be able to turn the Plannotator integration on and off with one setting. The setting is off by default; off means no change from today.
- **FR-002**: When the integration is on, every Session Emacs starts MUST direct Plannotator to open reviews through the user's Emacs browser setting. Emacs-supplied Plannotator values take precedence over any value already present in the user's environment.
- **FR-003**: The browser hand-off MUST fail in a way Plannotator detects, so that Plannotator's own fallback shows the review address when Emacs cannot open it. The integration MUST NOT use any option that suppresses that fallback.
- **FR-004**: The browser hand-off MUST NOT allow the review address to execute as code inside Emacs.
- **FR-004a**: The browser hand-off MUST target the Emacs instance that started the Session, even when several Emacs instances run at once. When that instance no longer runs, the hand-off MUST fail so Plannotator's fallback applies (FR-003).
- **FR-004b**: When the integration is on and the Emacs server is not running at Session start, Emacs MUST show a warning once per Emacs session that reviews will use Plannotator's fallback, and MUST NOT start the server itself.
- **FR-005**: When the integration is on, Emacs MUST tell Plannotator the Session's project directory and the Session's Agent type using only values Plannotator recognizes; an Agent with no recognized value sends none.
- **FR-006**: Emacs MUST NOT read, parse, or relay Plannotator's decision output; the Agent's existing Plannotator plugin remains the only feedback path.
- **FR-007**: Emacs MUST NOT store annotations, render review documents, or compute diffs for Plannotator.
- **FR-008**: When the integration is on, Emacs MUST give each Session its own review-state location, and MUST remove it when the Session ends.
- **FR-009**: When a review starts in a Session, the manager MUST show that Session as waiting for input, using the existing Agent state mechanism.
- **FR-010**: Emacs MUST detect review completion from Plannotator's own session registry, matched by the review address port, and clear the waiting state when the review process is gone.
- **FR-011**: Completion detection MUST tolerate a review process that ends without cleaning its registry entry, and MUST tolerate the registry entry appearing after the review starts.
- **FR-012**: When completion cannot be detected, Emacs MUST leave the waiting state in place and MUST offer a command that clears it.
- **FR-013**: Review-state monitoring MUST process only new entries and MUST NOT ignore a repeat of an earlier entry.
- **FR-014**: All new behavior MUST work with no optional package installed and MUST be verifiable without a display.

### Key Entities

- **Review**: One Plannotator surface (plan review, code review, annotation) tied to one Session; has an address, a port, a start time, and an end.
- **Review-state location**: A per-Session record where Plannotator announces each Review start; holds one entry per Review with address, port, and remote flag.
- **Plannotator session registry entry**: Plannotator's own record of a live Review process; holds process id, port, address, mode, and project; removed on normal exit.
- **Session**: Existing Emacs-side object; gains a link to its review-state location and the port of its current Review.
- **Agent state**: Existing per-Session state; the Review integration sets `needs-input` on Review start and clears it on Review end.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the integration on, 100% of reviews started in an Emacs-owned Session open through the Emacs browser setting while Emacs runs.
- **SC-002**: With Emacs gone, 100% of reviews still show an address in the terminal, and no Agent waits with no address.
- **SC-003**: The waiting marker appears within 2 seconds of a review start and clears within 10 seconds of a normal review exit.
- **SC-004**: After a killed review process, the marker clears within 60 seconds.
- **SC-005**: Feedback reaches the Agent with zero change in content or timing compared to running Plannotator without Emacs.
- **SC-006**: Turning the integration off restores today's behavior with no residual environment or state.
- **SC-007**: The full batch quality gate passes with no optional package installed.

## Assumptions

- The user installs and configures the Plannotator plugin for each Agent outside this package; this package owns none of that setup.
- Plannotator honors a browser override that runs an executable with the address as one argument, falls back on failure, appends a start entry to a host-named file, and keeps a per-process session registry under its state directory. The research report records the source evidence.
- Plannotator recognizes Agent identifiers for Claude Code, Codex, OpenCode, Pi, and Oh My Pi.
- The Agent's own hook or plugin process, not Emacs, consumes Plannotator's decision output.
- Story 2 completion detection is best effort by design; the manual clear command is the guaranteed path.
- The waiting marker reuses the existing `needs-input` Agent state and the existing manager attention rendering; no new sidebar state is added.
- Remote and SSH sessions are out of scope; the review address is assumed reachable from the Emacs host.
