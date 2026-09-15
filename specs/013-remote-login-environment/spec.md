# Feature Specification: Remote Login Environment

**Feature Branch**: `main` (unchanged)

**Created**: 2026-09-14

**Status**: Draft

**Input**: User request: Make fresh remote Agent launches use the same environment as the user's normal remote login workflow. Keep this behavior explicit per host because interactive startup can add output, errors, and delay.

## Clarifications

### Session 2026-09-14

- Q: How should each remote host define the login environment used for fresh Agent launches? → A: Configure a shell path and argument list for each host.
- Q: How can a host control startup branches such as automatic tmux entry? → A: Configure literal `NAME=VALUE` environment assignments for fresh launches.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Launch with the normal remote environment (Priority: P1)

The user starts a fresh Agent on a configured remote host. The Agent receives the commands, paths, variables, locale, and working directory available in the user's normal interactive login workflow.

**Why this priority**: Environment parity is the requested benefit. Without it, tools available in a normal remote terminal can be missing from the Agent Session.

**Independent Test**: Configure one host for login-environment launch. Compare command lookup, `PATH`, one selected variable, locale, umask, and working directory between a fresh Agent and a normal interactive login.

**Acceptance Scenarios**:

1. **Given** a configured host whose normal interactive login adds a private executable directory, **When** the user starts a fresh remote Agent, **Then** the Agent can resolve executables from that directory.
2. **Given** a selected remote project directory, **When** the user starts a fresh remote Agent, **Then** the Agent starts in that exact directory after login initialization completes.
3. **Given** an Agent command with spaces or punctuation in its executable or arguments, **When** the user starts it through the login environment, **Then** it receives each original argument unchanged.
4. **Given** a normal interactive login, **When** the user compares it with a fresh Agent launch, **Then** command lookup, `PATH`, one selected variable, locale, umask, and working directory match.

---

### User Story 2 - Choose parity only for intended hosts (Priority: P1)

The user enables login-environment launch for each intended remote host. Other hosts continue to use the current direct launch behavior.

**Why this priority**: Interactive startup can be slow or noisy. A host-specific choice preserves current behavior where parity is unnecessary.

**Independent Test**: Configure one of two approved hosts for login-environment launch. Start a fresh Agent on each host and confirm that only the selected host loads its normal login environment.

**Acceptance Scenarios**:

1. **Given** a host with no login-environment preference, **When** the user starts a fresh remote Agent, **Then** the existing direct launch behavior remains unchanged.
2. **Given** a host with an explicit shell path and ordered argument list, **When** the user starts a fresh remote Agent, **Then** that host uses those exact login settings.
3. **Given** two configured names that reach the same machine, **When** only one name enables login-environment launch, **Then** the other name keeps direct launch behavior.
4. **Given** an existing remote Agent, **When** the user attaches or reattaches it, **Then** the feature does not restart it or change its environment.

---

### User Story 3 - Diagnose startup problems without fallback (Priority: P2)

The user receives the remote startup output and a clear failure when login initialization cannot start the Agent. The package does not silently retry with a different environment.

**Why this priority**: A fallback could start work with an unexpected environment and hide broken shell configuration.

**Independent Test**: Configure a host whose login initialization emits output and another whose initialization fails. Confirm that output stays visible and failure does not create a replacement Agent.

**Acceptance Scenarios**:

1. **Given** login initialization that emits warnings, **When** the user starts a fresh Agent, **Then** the Session shows those warnings before Agent output.
2. **Given** a missing configured shell or failed login initialization, **When** the user starts a fresh Agent, **Then** the launch fails explicitly without a direct-launch retry.
3. **Given** failed login initialization before Agent startup, **When** the failure completes, **Then** no Agent starts and no replacement ordinary shell remains.
4. **Given** one host with broken login initialization, **When** its launch fails, **Then** existing local and remote Sessions remain usable.

### Edge Cases

- **EC-01 — Interactive startup output**: Prompts, plugin warnings, banners, and errors remain visible. The package does not suppress or interpret them as Agent state.
- **EC-02 — Slow startup**: Login initialization can add delay. Existing launch readiness rules still decide whether startup succeeded.
- **EC-03 — Missing shell**: A missing, non-executable, or unsupported configured shell causes an actionable error for the selected host.
- **EC-04 — Failed initialization**: A failed initialization prevents Agent startup and does not trigger a fallback.
- **EC-05 — Literal values**: Project paths, target names, executable names, and arguments with spaces, quotes, dollar signs, or command-like text remain literal.
- **EC-06 — Environment-owned command lookup**: Direct sibling launch resolves both zmx and the Agent in the selected environment. Managed Worktree launch keeps its verified zmx bootstrap outside that environment, then initializes the environment before Agent resolution and execution.
- **EC-07 — Existing targets**: Attach, reattach, detach, and Stop behavior remain unchanged because they do not create a fresh Agent.
- **EC-08 — Host identity**: Preferences use the exact approved host name. The feature does not resolve aliases or copy preferences between names.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The user MUST be able to configure an explicit shell executable path and ordered argument list independently for each approved remote host.
- **FR-002**: A host without this preference MUST retain the current direct fresh-launch behavior.
- **FR-003**: A selected host MUST use its configured shell path and arguments exactly, with each value kept literal.
- **FR-004**: Those shell settings MUST produce the user's normal interactive login environment before Agent resolution and execution. Direct sibling launch MUST also initialize it before persistent target creation. Managed Worktree launch MAY create its verified target bootstrap first because its ownership protocol requires that order.
- **FR-005**: The fresh Agent MUST start in the exact remote directory selected by the user.
- **FR-006**: The persistent target name, Agent executable, and every Agent argument MUST retain their literal values through login initialization.
- **FR-007**: A fresh launch MUST create a new target identity even when the login environment contains identity values from an existing target.
- **FR-008**: A missing configured login environment or failed initialization MUST produce a host-specific error and MUST NOT retry through direct launch.
- **FR-009**: Startup output from the user's login environment MUST remain visible in the Session.
- **FR-010**: The feature MUST NOT interpret login startup output as structured Agent status.
- **FR-011**: A failed launch MUST NOT leave a replacement Agent or ordinary shell running under the requested target.
- **FR-012**: Login-environment preferences MUST apply only to fresh remote Agent creation. Existing attach, reattach, detach, and Stop behavior MUST remain unchanged.
- **FR-013**: The same host preference MUST apply consistently to every supported workflow that creates a fresh remote Agent.
- **FR-014**: Exact approved host names MUST remain the preference boundary. The feature MUST NOT discover hosts, resolve aliases, or copy settings automatically.
- **FR-015**: Failures on one host MUST NOT prevent use of existing Sessions or launches on other hosts.
- **FR-016**: The feature MUST retain existing host approval, authentication, host-key checking, connection limits, and safe target ownership behavior.
- **FR-017**: Parity validation MUST compare command lookup, `PATH`, one user-selected variable, locale, umask, and working directory with a normal interactive login on the same host.
- **FR-018**: A configured host MAY define ordered literal environment assignments. The package MUST apply them before selected shell startup and fresh Agent execution.

### Key Entities *(include if feature involves data)*

- **Remote launch environment preference**: A host-specific shell executable path and ordered argument list used during fresh Agent creation. Absence means direct launch.
- **Configured host**: An exact, user-approved remote destination and the boundary for launch preferences and errors.
- **Fresh remote Agent launch**: A request that creates one new persistent target and starts an Agent in a selected remote directory.
- **Login environment**: The commands, paths, variables, locale, umask, startup output, and startup result produced by the user's normal login workflow.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On each parity-enabled host, command lookup, `PATH`, one user-selected variable, locale, and umask match a normal interactive login. Both comparisons use the same selected working directory.
- **SC-002**: In five launches that use directories and arguments containing spaces and punctuation, all five use the intended directory and preserve every argument.
- **SC-003**: In a two-host comparison, the preference affects every fresh launch on the selected host and zero fresh launches on the other host.
- **SC-004**: For a missing login environment and a failed initialization, both attempts identify the selected host and leave zero replacement Agents or shells.
- **SC-005**: Existing attach, reattach, detach, and Stop walkthroughs produce no observable behavior change.
- **SC-006**: A user can enable parity for one host and complete a successful fresh launch within two minutes after prerequisite login setup.
- **SC-007**: All startup warnings and errors visible during the normal login workflow remain available during a parity launch.

## Assumptions

- The user owns the remote hosts and already configured authentication, trusted host identities, the login environment, and its startup files.
- The user explicitly selects the environment that represents the normal workflow for each host. The package does not infer it.
- Interactive startup files can emit output and add delay. Environment parity takes precedence over a silent launch where the user enables it.
- The package does not repair login configuration, plugin warnings, or startup errors.
- Existing direct launch remains the default because it is quieter and has fewer environment-dependent behaviors.
- The `ramhorn` observation establishes the motivating case. Direct launch and non-interactive login omit `/home/yufu/.cargo/bin`; interactive login includes it but emits plugin warnings and one startup error.
- Provisioning commands, changing remote startup files, and synchronizing environment settings between hosts remain outside scope.
- Managed Worktree launch must create its verified target bootstrap before login initialization. Environment parity applies before Agent resolution and execution.
