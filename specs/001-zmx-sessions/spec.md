# Feature Specification: zmx-backed persistent agent sessions

**Feature Branch**: `001-zmx-sessions`

**Created**: 2026-08-28

**Status**: Draft

**Input**: User description: "zmx-backed persistent agent sessions: launch agents under zmx, detach/reattach from Emacs or terminal, adopt externally launched sessions"

Grounding documents: `docs/adr/0001-zmx-backed-agent-sessions.md` (decision record) and `CONTEXT.md` (glossary). Terms below (Session, Zmx session, Attach, Detach, Adoption, Agent) follow the glossary.

## Clarifications

### Session 2026-08-28

- Q: When session start offers existing zmx sessions to reattach (FR-006), should the list exclude zmx sessions that already have a live attached buffer in this Emacs instance? → A: Yes, exclude them from the start-time offer; `claude-code-ide-attach` still lists all.
- Q: When the user starts a session with the continue or resume flag while zmx mode is on and eligible zmx sessions exist, should Emacs still show the reattach offer, or always create a new zmx session? → A: Skip the offer; continue/resume always creates a new zmx session with the flagged command.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Agent survives Emacs (Priority: P1)

A user enables `claude-code-ide-use-zmx` and starts an agent in a project. The agent process runs inside a zmx session named `cci-<agent>-<project>-<id-short>`. The user quits Emacs, opens a plain terminal, runs `zmx attach <name>`, and continues the same agent conversation.

**Why this priority**: This is the core value: the agent process outlives Emacs and is reachable from any terminal.

**Independent Test**: Start a session with zmx mode on, kill the Emacs buffer, verify with `zmx list` that the session is alive, and attach from a terminal.

**Acceptance Scenarios**:

1. **Given** `claude-code-ide-use-zmx` is non-nil, **When** the user starts an agent session, **Then** the terminal buffer runs `zmx attach <name> <agent-cmd>` and `zmx list` shows the session.
2. **Given** a running zmx-backed session, **When** the user kills the terminal buffer or exits Emacs, **Then** the zmx session and agent process keep running, with no prompt.
3. **Given** `claude-code-ide-use-zmx` is nil, **When** the user starts an agent session, **Then** behavior is unchanged from today (no zmx involvement).

---

### User Story 2 - Reattach after Emacs restart (Priority: P2)

After an Emacs restart, the user starts an agent in the same project. Zmx sessions matching `cci-<agent>-<project>-*` exist. Emacs offers them via completing-read, with a "create new" option. Choosing one reattaches; choosing "create new" starts a fresh zmx session.

**Why this priority**: Reattach from inside Emacs is the payoff of persistence for the primary (Emacs-first) workflow.

**Independent Test**: Start a zmx-backed session, restart Emacs, start again in the same project, and pick the offered session.

**Acceptance Scenarios**:

1. **Given** matching zmx sessions exist for the project and agent and are not already attached in this Emacs instance, **When** the user starts a session, **Then** a completing-read offers each match plus "create new".
2. **Given** no matching zmx sessions exist, **When** the user starts a session, **Then** a new zmx session is created without a prompt.
3. **Given** eligible zmx sessions exist, **When** the user starts a session with the continue or resume flag, **Then** no offer appears and a new zmx session runs the flagged command.
4. **Given** the user reattaches, **When** the buffer opens, **Then** the Session gets a fresh session-id and idle tracking works on the attached output.

---

### User Story 3 - Adopt a terminal-launched session (Priority: P3)

The user launches an agent in a plain terminal under zmx, detaches, and later runs `M-x claude-code-ide-attach` in Emacs. A completing-read lists zmx sessions annotated with working directory and command. Adoption creates a full Session: buffer, idle tracking, and manager visibility.

**Why this priority**: This is the "vice versa" direction. It depends on the attach plumbing from stories 1-2.

**Independent Test**: `zmx attach test-session omp` in a terminal, detach, then adopt it via `claude-code-ide-attach` in Emacs.

**Acceptance Scenarios**:

1. **Given** zmx sessions exist, **When** the user runs `claude-code-ide-attach`, **Then** a completing-read lists them with cwd and command annotations from `zmx list`.
2. **Given** the user selects a session, **When** its `cmd` matches a configured agent CLI path, **Then** the CLI type is inferred, the directory comes from `start_dir`, and a Session with a fresh session-id opens.
3. **Given** the `cmd` matches no configured agent, **When** adoption proceeds, **Then** Emacs prompts the user for the CLI type.

---

### User Story 4 - Explicit stop kills the zmx session (Priority: P4)

The user runs the stop command on a zmx-backed session. Emacs prompts yes/no, naming the zmx session, then runs `zmx kill`.

**Why this priority**: Without it, zmx sessions accumulate forever. Small and independent.

**Acceptance Scenarios**:

1. **Given** a zmx-backed Session, **When** the user runs `claude-code-ide-stop` and confirms, **Then** `zmx kill <name>` runs and the session disappears from `zmx list`.
2. **Given** the same prompt, **When** the user declines, **Then** nothing is killed.

---

### Edge Cases

- zmx binary missing: signal `user-error` naming `zmx` at the point of use (session start with zmx mode on, attach, stop). Package must load, byte-compile, and pass tests without zmx installed.
- Project names with characters invalid in zmx session names: sanitize the `<project>` component (lowercase, non-alphanumerics to `-`).
- Selected zmx session dies between `zmx list` and attach: the attach command fails in the terminal buffer; surface the zmx error, do not crash.
- Two Emacs instances (or Emacs plus terminal) attached to the same zmx session: allowed; zmx owns input leadership; no Emacs-side locking.
- Stale environment: MCP/SSE ports are frozen at zmx-session creation. Attaching from a different Emacs instance or terminal keeps the old environment, and port-based integrations break. Documented, not worked around (ADR 0001).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A boolean defcustom `claude-code-ide-use-zmx` (default nil) MUST gate all zmx behavior. Nil MUST preserve current behavior exactly.
- **FR-002**: With zmx mode on, session start MUST wrap the built agent command as `zmx attach <name> <cmd>` for every agent and every terminal backend (vterm, eat, ghostel).
- **FR-003**: Zmx session names MUST follow `<prefix><agent>-<project>-<id-short>`, with the prefix in defcustom `claude-code-ide-zmx-session-prefix` (default `cci-`). One zmx name maps to one agent process.
- **FR-004**: Killing the terminal buffer, closing its window, or exiting Emacs MUST detach without killing the zmx session and without prompting.
- **FR-005**: `claude-code-ide-stop` on a zmx-backed session MUST prompt yes/no naming the zmx session, then run `zmx kill <name>` on confirmation.
- **FR-006**: On plain session start with zmx mode on, existing zmx sessions matching `<prefix><agent>-<project>-*` MUST be offered via completing-read with a "create new" option. Sessions that already have a live attached buffer in this Emacs instance MUST be excluded from this offer (they remain listed by `claude-code-ide-attach`). No eligible matches MUST mean no prompt. A start with the continue or resume flag MUST skip the offer and create a new zmx session running the flagged command.
- **FR-007**: A new command `claude-code-ide-attach` MUST list zmx sessions from `zmx list` (annotated with `start_dir` and `cmd`) and adopt the selection into a full Session.
- **FR-008**: Adoption MUST mint a fresh session-id, take the directory from `start_dir`, and infer the CLI type by matching `cmd` against configured agent CLI paths, prompting on no match or ambiguity.
- **FR-009**: A missing zmx executable MUST raise a `user-error` naming zmx at the point of use. Loading, byte-compiling, and testing the package MUST NOT require zmx.
- **FR-010**: Zmx control operations (`list`, `kill`) MUST run as subprocess calls in a dedicated adapter within the session layer, with no dependency on `refs/emacs-term-sessions`.

### Key Entities

- **Session**: Emacs-side object keyed by session-id (glossary). Gains an optional zmx-name attribute linking it to a Zmx session.
- **Zmx session**: backend-owned persistent PTY (glossary). Identified by name; `zmx list` exposes `name`, `pid`, `clients`, `created`, `start_dir`, `cmd`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With zmx mode on, an agent started in Emacs remains attachable from a plain terminal after the Emacs process exits.
- **SC-002**: With zmx mode off, the full existing ERT suite passes unchanged.
- **SC-003**: `./scripts/compile-and-test.sh` passes with zmx not installed; zmx subprocess calls are mocked in tests like other optional dependencies.
- **SC-004**: A user can complete the round trip — start in terminal, detach, adopt in Emacs, detach, reattach in terminal — using only `claude-code-ide-attach` and standard zmx commands.
- **SC-005**: Stopping a zmx-backed session from Emacs removes it from `zmx list`.

## Assumptions

- zmx is installed and on `exec-path` wherever zmx mode is used. Local sessions only; TRAMP/remote zmx is out of scope for this feature.
- Per ADR 0001: environment is frozen at zmx-session creation; stale MCP/SSE ports after cross-environment attach are accepted.
- Transient toggle and manager-sidebar zmx section are follow-ups, out of scope here.
- `refs/emacs-term-sessions` stays a local, uncommitted reference implementation.
- The `zmx list` key=value output format (tab-separated, `--short` optional) matches the format the reference implementation parses.
