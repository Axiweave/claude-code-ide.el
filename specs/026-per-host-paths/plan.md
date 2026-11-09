# Implementation Plan: Per-Host Project Paths

**Branch**: `026-per-host-paths` | **Date**: 2026-11-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/026-per-host-paths/spec.md`

## Summary

In the Intake configuration, the project keys `path`, `omp`, and `launch_session` each take one value for all hosts, or a table keyed by host with an optional `default` entry. The Intake resolves these values once, when it loads the configuration. Each project then has one record for each of its hosts: `on[host] = { path, omp, launch_session }`. The runtime never sees the `default` entry or the two value forms.

These places read the record for the Launch host:
- A Launch request takes the path from `on[host]`.
- A Linear Launch takes it from `on[default_host]`.
- A Launch start takes the commands from `on[host]`.

The master keeps one record. Its `[master]` table already has the same three fields, so the start code uses one shape for both.

`GET /v1/projects` replaces the string field `path` with `paths`, an object keyed by host. `cci projects` prints that answer unchanged. Emacs does not change. See `research.md` D1–D8.

## Technical Context

**Language/Version**: TypeScript on Bun 1.4 (the Intake only).

**Primary Dependencies**: None added. `Bun.TOML` already parses inline tables and arrays.

**Storage**: No schema change. A Launch already stores `dir` when the Intake records the Launch (FR-006).

**Testing**:
- Intake `bun test`. The new cases go into the bad-configuration table in `test/config.test.ts`.
- A seeded property test checks the resolution against a small reference function, and it prints its seed.
- Launch tests check the path and the commands for each host through `FakeZmx` (`test/launches.test.ts` or `test/http.test.ts`).
- The package gate `./scripts/compile-and-test.sh` must still pass. No Elisp changes.

**Target Platform**: The Intake on macOS. Workers on macOS (`local`) and Linux (`v12dev`).

**Project Type**: One repository changes: the Intake daemon (`~/agents/cci-intake`). The spec lives in the package repository, as in 024 and 025.

**Performance Goals**: None new. The Intake resolves the values once, at load.

**Constraints**:
- A configuration error stops the Intake at start, with the project, the key, and the host in the message (FR-003).
- One value (a string, or an array for a command) keeps today's behavior (FR-008).

**Scale/Scope**: A few projects, each with one to three hosts.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Note |
|---|---|---|
| I. Shared core, thin adapters | Pass | No package code changes. Project paths and omp commands stay user configuration in the Intake. |
| II. Batch-verifiable gate | Pass | No Elisp changes. `./scripts/compile-and-test.sh` must still pass. The Intake adds `bun test` cases. |
| III. Optional dependencies | Pass | No new dependency. |
| IV. Ghostel only | Pass | No terminal change. |
| V. Simplicity | Pass | There is one resolution function at load, and the runtime gets one record shape for each host. The master and the projects share that shape. This removes the master/project branch for the commands at Launch start. |
| VI. Local/remote parity | Pass | This feature adds parity. The same project now runs on a local host and a remote host. There is no new required difference. |

Re-check after Phase 1: still Pass. There is no Complexity Tracking entry.

## Project Structure

### Documentation (this feature)

```text
specs/026-per-host-paths/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── intake-config.md
│   └── intake-http.md
├── checklists/requirements.md
└── tasks.md             # /speckit.tasks output
```

### Source Code (INTAKE = ~/agents/cci-intake)

```text
INTAKE/src/config.ts       # perHost() resolution, Project.on, refuse [hosts.default]
INTAKE/src/launches.ts     # requestLaunch dir = on[host].path; start uses on[host] or master
INTAKE/src/linear.ts       # dir = on[default_host].path
INTAKE/src/http.ts         # GET /v1/projects: paths object instead of path
INTAKE/test/helpers.ts     # testConfig() builds Project.on
INTAKE/test/config.test.ts # per-host forms, default entry, refusals, seeded property test
INTAKE/test/*.test.ts      # fixtures that set path or omp on a Project
INTAKE/README.md           # config example with two hosts, paths field
```

**Structure Decision**: Only the Intake changes. The package keeps the spec and gets no code change, because Emacs reads the Session directory from the started Session and not from the project configuration.

## Complexity Tracking

No violations.
