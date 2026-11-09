# Feature Specification: Per-Host Project Paths

**Feature Branch**: `026-per-host-paths`

**Created**: 2026-11-09

**Status**: Draft

**Input**: User description: "We should allow the path to be different across hosts. We should be able to do that."

## Context

A project in the Session Intake configuration names its hosts, for example this MacBook (`local`) and `v12dev`. Today a project has one checkout path and one omp command for all of its hosts. The same repository usually has a different path on each machine (`/Users/fuyu0425/src/app` on the MacBook, `/home/yufu/src/app` on v12dev). The omp program also has a different path on each machine. So a project can only work on one host, and the user must add one project for each host. The Master Session must then choose between two project names for the same work.

## Clarifications

### Session 2026-11-09

- Q: How do you want to write a value for each host in a project's config? → A: The same key takes a table keyed by host, for example `path = { local = "/Users/me/app", v12dev = "/home/yufu/app" }`, and the same form for `omp` and `launch_session`.
- Q: Must a table keyed by host name every host of the project, or can it fall back to a default value? → A: A table can have a `default` entry. A project host that the table does not name uses the `default` entry, for example `path = { default = "/srv/app", v12dev = "/home/yufu/app" }`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One project, a different checkout on each host (Priority: P1)

The user configures one project with two hosts. The user gives the checkout path for each host. When the user asks the Master Session for work in that project on a named host, the Worker Session starts in the checkout of that host.

**Why this priority**: This is the request. Without it, one project cannot run on two machines.

**Independent Test**: Configure one project with `local` and `v12dev` and a different path for each. Start one Launch with each host. Each Worker Session starts in a worktree of the checkout on its own host.

**Acceptance Scenarios**:

1. **Given** a project with the hosts `local` and `v12dev` and a path for each host, **When** a Launch names the host `v12dev`, **Then** the Worker Session starts on v12dev in a new worktree of the v12dev path.
2. **Given** the same project, **When** a Launch names no host, **Then** the Worker Session starts on the default host in a worktree of the path for the default host.
3. **Given** the same project, **When** a Launch asks for the main checkout on `local`, **Then** the Worker Session starts in the `local` path itself.

---

### User Story 2 - A different omp command on each host (Priority: P1)

The omp program and the `launch-session` command have a different path on each machine. The user gives them for each host, as for the checkout path.

**Why this priority**: A per-host checkout path alone does not work when the omp command is wrong on one host. Both are necessary for one Launch to start.

**Independent Test**: Configure a project whose omp command differs for `local` and `v12dev`. Start one Launch on each host. Each host runs its own omp command.

**Acceptance Scenarios**:

1. **Given** a project with an omp command for each host, **When** a Launch starts on v12dev, **Then** the Intake runs the v12dev command, and never the `local` command.
2. **Given** a project with one omp command for all hosts, **When** a Launch starts on any of its hosts, **Then** the Intake runs that one command.

---

### User Story 3 - The Master Session sees each host's path (Priority: P2)

When the Master Session lists the projects, it sees each host of a project and the checkout path on that host. So it can tell the user where the work will run before it starts a Launch.

**Why this priority**: This helps the user and the master, but Launches work without it.

**Independent Test**: List the projects through `cci projects`. A project with two hosts shows one path for each host.

**Acceptance Scenarios**:

1. **Given** a project with a different path for each host, **When** the master lists the projects, **Then** the answer shows each host with its own path.

---

### Edge Cases

- A per-host value names a host that is not in the project's hosts: the Intake refuses to start, and its message names the project, the key, and the host.
- A per-host table does not name one of the project's hosts and has no `default` entry: the Intake refuses to start, and its message names the missing host.
- A per-host table does not name one of the project's hosts but has a `default` entry: that host uses the `default` value.
- A host in the `[hosts]` table is named `default`: the Intake refuses to start, because `default` is the name of the fallback entry in a per-host table.
- A per-host omp command whose program is not omp, on any host or in the `default` entry: the Intake refuses to start, as it does today for one command.
- A path is the same on two hosts: the user can give one value for all hosts, the same value for each host, or a `default` entry. All three work.
- A Linear issue starts a Launch: it uses the default host, so it uses the path and the omp command of the default host.
- A Launch that was recorded before the configuration changed: it keeps the path that it was recorded with.
- The Master Session itself: it always runs on `local`, and this feature does not change it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The project `path` MUST accept either one path (a string) for all of the project's hosts or a table keyed by host with one path for each host, for example `path = { local = "/Users/me/app", v12dev = "/home/yufu/app" }`.
- **FR-002**: The project `omp` and `launch_session` commands MUST each accept either one command (an array of strings) for all of the project's hosts or a table keyed by host with one command for each host, for example `omp = { local = ["/Users/me/.bun/bin/omp"], v12dev = ["/home/yufu/.bun/bin/omp"] }`.
- **FR-003**: A table keyed by host MAY have a `default` entry. A project host that the table does not name MUST use the `default` entry. The table MUST NOT name a host that is not in the project's hosts. When a project host has neither its own entry nor a `default` entry, the Intake MUST refuse to start. The refusal message MUST name the project, the key, and the host that is missing or extra. The Intake MUST refuse a `[hosts]` entry named `default`.
- **FR-004**: Every command for each host MUST pass the same checks as one command today (not empty, and the program is omp).
- **FR-005**: A Launch MUST use the path, the omp command, and the `launch-session` command of the host that it runs on, for every source: the HTTP API, `cci`, and Linear.
- **FR-006**: A Launch MUST record the path that it was started with. A later configuration change MUST NOT change the path of a recorded Launch.
- **FR-007**: The project list (`GET /v1/projects`, `cci projects`) MUST show, for each project, every host with the checkout path for that host.
- **FR-008**: A project that gives one path and one command for all hosts MUST behave as it does today.
- **FR-009**: The Intake README and the configuration example MUST show a project with two hosts and a different path and omp command for each host.

### Key Entities

- **Project**: a named repository. It has a list of hosts, a default host, and, for each host, a checkout path, an omp command, and a `launch-session` command.
- **Launch**: one request to start a Worker Session. It records its host and the checkout path that the Intake chose for that host.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The user can run the same project on the MacBook and on v12dev with one project entry, and each Launch starts in the right checkout on its host in 100% of tries.
- **SC-002**: A configuration that names a wrong or missing host in a per-host value never starts the Intake, and the message names the project, the key, and the host.
- **SC-003**: A configuration that worked before this feature still starts, and its Launches start in the same paths.
- **SC-004**: The Master Session can tell the user the host and the path of a Launch before it starts the Launch, from one project list call.

## Assumptions

- The host names are the keys of the `[hosts]` table in the Intake configuration, as today.
- The `[master]` table keeps one path and one command, because the Master Session always runs on `local`.
- Only the Intake changes. Emacs gets the Session directory from the started Session, so Emacs does not read project paths.
- The project description, the default host, and the Linear filters stay the same for all hosts of a project.
- The Intake reads its configuration only at start, as today. A change needs an Intake restart.
