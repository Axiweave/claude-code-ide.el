---
description: "Executable tasks for the Ghostel-only terminal cutover"
---

# Tasks: Ghostel-Only Terminal Support

**Input**: Design documents in `specs/008-remove-legacy-backends/`.
**Branch**: `main`.
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/elisp-surface.md](contracts/elisp-surface.md), and [quickstart.md](quickstart.md).
**Governance**: [Constitution 2.0.0](../../.specify/memory/constitution.md). The required policy amendment is complete.

**Tests**: FR-010 and SC-007 explicitly require meaningful test coverage and dependency-isolated verification.
Use the existing ERT suite and interface mocks.
Add regressions only for observable failure, ownership, or transition behavior.
Delete obsolete source-text and forwarding-only assertions rather than repinning them.

**Organization**: All three user stories have priority P1.
US1 preserves the working Ghostel product. US2 completes runtime retirement and failure isolation. US3 aligns maintained documentation.
US2 follows US1 because it deletes symbols whose package and parent callers US1 migrates.
US3 can proceed independently after the foundation, within its named file ownership.

## Format and Path Conventions

Every task uses `- [ ] Tnnn [P?] [USn?] Description with file path`.
`[P]` marks a disjoint-file task within a ready execution wave, not permission to bypass dependencies.
Story labels appear only in user-story phases.
Paths in task descriptions are relative to the package repository root.
Resolve them to absolute paths for filesystem operations.

The only parent-repository edit targets are `../../lisp/pkgs/pkg-claude-code-ide.el` and `../../tests/pkg-claude-code-ide-test.el`.
Preserve unrelated changes, installed packages, terminal workflows, and Git history.
Work on the current branch without commits unless the user authorizes them.

This document is an explicit removal record under FR-013.
Retired product names identify deletion targets, not supported APIs or setup instructions.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the existing file boundary and verification inputs without creating a new project or dependency layer.

- [X] T001 Record maintained-file scope and existing-work preservation using `.gitignore` and `specs/008-remove-legacy-backends/quickstart.md` section 9.
- [X] T002 Prepare isolated dependency-absence and dependency-present verification inputs using `scripts/compile-and-test.sh` and `specs/008-remove-legacy-backends/quickstart.md` sections 1–3.

**T001 completion**: Inventory tracked package files, hidden automation, prior feature artifacts, and explicitly maintained untracked specs.
Record relevant parent changes before editing the two named consumers.
Classify ignored `refs/`, `ref-docs/`, and `.omp/` separately as reference material, external checkouts, or local tool state.
Exclude those contents from cleanup and zero-support counts.
An ignore rule does not exempt an already tracked maintained file.

**T002 completion**: Record required library paths, available optional integrations, and native/approved-remote prerequisites.
Use caller-supplied `EMACSLOADPATH`, not machine-specific paths committed to the runner.
Neither batch environment may discover a real terminal library.
The optional-absence lane also excludes Magit and other optional providers.
Do not install dependencies or approve hosts to create a passing environment.

**Checkpoint**: Scope and verification inputs are explicit. No new runtime dependencies, storage, or scaffold is needed.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the shared availability boundary used by every terminal entrypoint.
This phase blocks all user-story implementation.

- [X] T003 Add shared Ghostel library/native preflight regressions and migrate ensure-helper fixtures in `claude-code-ide-tests.el`.
- [X] T004 Unify Ghostel preflight and constructor-wide no-install bindings in `claude-code-ide-session.el` and `claude-code-ide.el`.

**T003 completion**: Test absent library, absent native support, actionable failure, and unchanged global installation preference.
Use existing Ghostel interface mocks without a native module.
New regression cases must fail on the relevant old behavior before T004 and pass after it.
Do not force an already valid preservation test to fail artificially.

**T004 completion**: Implement `claude-code-ide-session--ensure-ghostel ()` as the sole library/native preflight.
Replace `claude-code-ide--terminal-ensure-backend` and migrate every call and fixture without an alias.
Unify soft loading and the companion's existing `ghostel--new` check.
Bind `ghostel-module-auto-install` to nil through both preflight and actual constructor execution.
Run preflight before MCP startup or terminal creation while preserving existing remote admission and disconnected-target semantics.
Package loading and non-terminal operations remain independent of Ghostel.

The authoritative interface is contract C1. Session fields and persisted layouts remain unchanged.
One integration owner controls both files in T004.
Run the focused preflight checks after that owner's edits settle.

**Checkpoint**: All terminal entrypoints share real, non-installing library/native checks. No new compatibility path exists.

## Phase 3: User Story 1 — Keep the Existing Ghostel Workflow (Priority: P1)

**Goal**: Preserve all supported Agent, input, layout, companion, activity, and persistent-session behavior with direct Ghostel paths.

**Independent Test**: With Ghostel available and retired terminals absent, exercise all five Agents and six layouts.
Verify local persistence and approved remote attachment without identity changes or replacement processes.
Use quickstart sections 5–8 and contracts C1–C4/C6.

### Tests for User Story 1

- [X] T005 [P] [US1] Migrate launch, environment, input, resize, activity, and ownership fixtures to Ghostel behavior in `claude-code-ide-tests.el`.
- [X] T006 [P] [US1] Replace backend-resolver fixtures with actual mode-boundary tests in `../../tests/pkg-claude-code-ide-test.el`.

**Test wave completion**: Preserve behavior checks and remove assertions for branches that this story deletes.
T005 includes CLI command/environment identity, OMP graphical/TUI image protocol, raw input versus paste, clipboard capability limits, and both output paths.
T006 covers page navigation, End, Plan Review pass-through, copy-mode transitions, visible-only recentering, and file-reference input.
The two tasks own different files and can run together.
Run new targeted regressions after both writers finish and before the implementation wave.

### Implementation for User Story 1

- [X] T007 [P] [US1] Use direct Ghostel Agent construction with live-process registration and rollback ordering in `claude-code-ide.el`.
- [X] T008 [P] [US1] Use direct Ghostel setup, input, and safe companion construction in `claude-code-ide-session.el`.
- [X] T009 [P] [US1] Retain both Ghostel output observers and focus tracking while removing retired observer paths in `claude-code-ide-session-idle.el`.
- [X] T010 [P] [US1] Migrate five resolver callers and remove terminal-choice assignments and the dead workaround in `../../lisp/pkgs/pkg-claude-code-ide.el`.
- [X] T011 [US1] Remove backend-dependent resize dispatch while preserving Ghostel reflow and observer lifetime in `claude-code-ide.el`.
- [X] T012 [US1] Preserve layout, companion, stale-request, and persistent-session invariants through migrated regressions in `claude-code-ide-tests.el`.

**T007 completion**: Keep the factory signature and `(buffer . process)` result.
Use `ghostel-exec`, which returns the lifecycle process, with existing shell arguments, directory, environment, and zmx wrapping.
Preserve CLI type and command builders.
Remove only OMP's backend condition while retaining `kitty` in graphical Emacs and `off` in terminal Emacs.
Keep Pi unchanged.

Validate the returned buffer and live process before active Session registration.
Preserve setup timing, then install ownership-bound callbacks and recheck liveness after the initialization delay.
Display and report success only after validation.
Roll back only failed-request resources while preserving existing Sessions and persistent Agents.
Keep remote admission, identity checks, and terminal/project-view independence.
A remembered disconnected remote target is not a successful active attachment.

**T008 completion**: Keep raw/paste distinctions, submission, Escape, Ctrl-C, Ctrl-G, clipboard behavior, and existing image limits.
Keep successful-input activity timing, idempotent setup, Session predicates, and surviving generic input aliases.
Require actual Ghostel mode at terminal-operation boundaries without inventing pre-registration state.
Keep `ghostel-create` for companions and confirm their buffer-local live process before return.
Preserve a live ordinary shell after partial failure or superseded publication.
Clean only the failed request's dead partial buffer.

**T009 completion**: Preserve observers on both `ghostel--filter` and `ghostel--events-filter`.
Keep focus-driven activity, notifications, and exact Session ownership.
Delete retired observer registration and cleanup, not the shared activity model.

**T010 completion**: Use actual Ghostel mode checks in page-up, page-down, End, and both Evil state hooks.
Preserve unrelated-buffer fallback, copy-mode behavior, CLI distinctions, and visible-window-only recentering.
Keep the current `magit-left` preference and generic popup side/width settings.
Do not change unrelated parent terminal configuration.

**T011 completion**: Delete backend resize selection and capability predicates, not the generic reflow option.
Remove backend arguments from resize install/remove helpers and update every caller.
Target `ghostel--adjust-size` directly with idempotent first-Session/last-Session lifetime.
Preserve the working-state observer, copy-mode guard, reflow filter, and exact Ghostel cursor behavior.
T011 follows T007 because both edit the core file.

**T012 completion**: Preserve exact Session-ID companion ownership and captured-request validation.
Cover all six presets, saved-layout precedence, selected-window restoration, live shell reuse, exited-shell replacement, and same-directory siblings.
Preserve local adoption, detach versus Stop, reconnect identity, and remote project-access independence.
Keep `claude-code-ide-manager.el` and `claude-code-ide-zmx.el` unchanged unless a concrete removed caller requires migration.
No new layout schema or Session field is permitted.

### Independent Validation for User Story 1

- [X] T013 [US1] Run surviving focused ERT checks in `claude-code-ide-tests.el` and `../../tests/pkg-claude-code-ide-test.el` after the implementation wave settles.
- [X] T014 [US1] Verify every native Agent workflow and record observations in `specs/008-remove-legacy-backends/quickstart.md` section 6.
- [X] T015 [US1] Verify all six native layout presets and companion lifecycle cases in `specs/008-remove-legacy-backends/quickstart.md` section 7.
- [X] T016 [US1] Verify local persistence and approved remote lifecycle behavior in `specs/008-remove-legacy-backends/quickstart.md` section 8.

**Checkpoint**: The surviving Ghostel workflow has independent behavior evidence.
This is the first internal validation increment, not permission to ship an incomplete retirement.
Unavailable native or approved-remote prerequisites must remain explicit blockers, not mock-based passes.

## Phase 4: User Story 2 — Remove the Old Terminal Support Completely (Priority: P1)

**Goal**: Remove all remaining terminal-selection machinery and retired support without weakening optional loading, failure isolation, or upgrade safety.

**Independent Test**: Inspect runtime, tests, and automation for zero retired support paths.
Exercise absent library/native support, failed construction, stale buffers, and legacy preferences while preserving existing Sessions.
Use quickstart sections 2–4/9 and contract C5.

**Dependency**: US1 caller migration precedes this phase. Its core, Session, and test files overlap this story's files.

### Tests for User Story 2

- [X] T017 [US2] Add startup-failure, inert-preference, stale-buffer, and registration-rollback regressions in `claude-code-ide-tests.el`.

**T017 completion**: Cover failure before creation, missing/dead constructor results, and failure after registration.
Assert no false success, wrong directory/host, or damage to existing Sessions.
Assert no MCP/terminal startup on missing native support.
Verify that old preferences cannot affect new creation.
Use an unsupported-mode fixture for stale-buffer rejection rather than recreating a retired terminal mock.
Test rejection of setup/input/reload cleanup without adoption, reconfiguration, or process termination.

### Implementation for User Story 2

- [X] T018 [P] [US2] Delete remaining terminal selectors, caches, settings, render state, and retired cleanup from `claude-code-ide.el`.
- [X] T019 [P] [US2] Delete remaining retired declarations, helpers, hooks, and aliases from `claude-code-ide-session.el` while enforcing safe mode rejection.
- [X] T020 [P] [US2] Remove retired dependency discovery from `scripts/compile-and-test.sh` and preserve terminal-free verification in `.github/workflows/test.yml`.
- [X] T021 [US2] Remove retired mocks and isolate every optional native integration in `claude-code-ide-tests.el`.

**T018/T019 completion**: Delete every remaining target in contract C5 and the setup inventory.
This includes global/per-Agent preferences, current-backend resolvers, buffer-local cache, process lookup, retired render queues/timers, and obsolete terminal aliases.
Remove stale terminal-choice readers in every maintained caller.
Keep meaningful Ghostel behavior and generic popup, initialization-delay, reflow, zmx, and Agent settings.
No constant-return resolver, obsolete-variable compatibility declaration, or fallback dispatcher may remain.

Old terminal buffers that survive reload must not receive Ghostel operations or destructive cleanup.
Explain the restart requirement at unsupported terminal use.
Do not hot-convert buffers, uninstall terminal packages, or change the user's global Ghostel preferences.
Retain generic send/keybinding aliases whose targets still exist.

**T020 completion**: Remove the runner's `emacs-libvterm` discovery and any other discovered retired-terminal installation or load-path setup.
Preserve the existing CI platform matrix and batch/native-compilation commands.
Do not add Ghostel installation, a new test framework, or machine-specific dependency paths.
Leave the workflow file unchanged if its current terminal-free setup already satisfies the contract.

**T021 completion**: Remove retired provided features, declarations, fixtures, and remaining selection/renderer tests.
Keep low-level Ghostel mocks and active optional-absence behavior checks.
Audit every native Magit submodule require, including the unavailable-project-view test's unconditional `magit-status` require.
Mock provider interfaces where tests check package behavior.
Guard only genuine native-integration tests with explicit absence skips, then require their execution in the dependency-present lane.
The full suite must load without optional packages. Blanket skips and fake provider success are not acceptable.

### Independent Validation for User Story 2

- [X] T022 [US2] Exercise dependency absence, native failure, startup rollback, and stale-buffer rejection through `specs/008-remove-legacy-backends/quickstart.md` sections 2–4.
- [X] T023 [US2] Record zero retired runtime/test/automation support paths using `specs/008-remove-legacy-backends/quickstart.md` section 9.

T022 runs the standalone terminal-library absence and package-load probes plus focused failure regressions.
The final full-suite executions belong to T035 after every writer finishes.
T023 includes declarations, imports, hooks, aliases, callbacks, dependency discovery, and both named parent consumers.
Product names in explicit removal records remain permitted. Ignored/external material does not enter this acceptance count.

**Checkpoint**: New Sessions ignore old preferences, unavailable support fails safely, and runtime retirement is complete.
Both dependency environments remain mandatory for final acceptance.

## Phase 5: User Story 3 — Read One Consistent Support Policy Everywhere (Priority: P1)

**Goal**: Make every maintained support statement agree with Ghostel-only behavior and preserve truthful attribution and historical evidence.

**Independent Test**: Read the README comparison and requirements, then classify every maintained documentation reference.
Find no active retired-terminal setup, dependency, configuration, operation, or support promise.
Use quickstart section 9 and contract C7.
No source-text assertion tests are needed for this documentation story.

### Implementation for User Story 3

- [X] T024 [P] [US3] Add the Ghostel-only fork distinction and align every terminal section in `README.org` while preserving original attribution.
- [X] T025 [P] [US3] Remove obsolete terminal-choice guidance and align supported workflows in `docs/remote.org` and `docs/zmx.org`.
- [X] T026 [P] [US3] Remove retired-support claims from `specs/001-zmx-sessions/plan.md`, `specs/001-zmx-sessions/quickstart.md`, `specs/001-zmx-sessions/research.md`, and `specs/001-zmx-sessions/spec.md`.
- [X] T027 [P] [US3] Remove retired-support claims from `specs/003-attach-remote-agents/plan.md`, `specs/003-attach-remote-agents/quickstart.md`, `specs/003-attach-remote-agents/spec.md`, and `specs/003-attach-remote-agents/tasks.md`.
- [X] T028 [P] [US3] Remove obsolete guidance and native acceptance rows from `specs/004-grouped-global-view/plan.md` and `specs/004-grouped-global-view/quickstart.md`.
- [X] T029 [P] [US3] Remove retired-support claims from `specs/006-sidebar-detail-view/plan.md` and `specs/006-sidebar-detail-view/research.md`.
- [X] T030 [P] [US3] Remove retired-support claims from `specs/007-add-layout-presets/plan.md`, `specs/007-add-layout-presets/quickstart.md`, and `specs/007-add-layout-presets/tasks.md`.
- [X] T031 [P] [US3] Remove obsolete terminal wording in `claude-code-ide-transient.el` and retire only the matching removal item in `TODOs.org`.
- [X] T032 [US3] Align remaining maintained guidance and inventoried references, including `AGENTS.md`, `CONTEXT.md`, and `.specify/memory/constitution.md`.

**T024 completion**: Add the distinction to the existing fork-comparison list, not a competing section.
Align overview, features, prerequisites, installation, configuration, key guidance, and troubleshooting.
Preserve the original repository link and attribution.

**T025–T031 completion**: Prior feature documents have no blanket historical exemption.
Remove obsolete setup examples, promises, and acceptance rows, or mark the affected rows as superseded by feature 008.
Do not rename an old native terminal result into a Ghostel pass.
Preserve unrelated timestamps, task IDs, evidence, legal text, and product capabilities.
Review lexical matches instead of deleting unrelated words containing a terminal substring.

**T032 completion**: Review all remaining files from T001, including hidden tracked automation and prior checklists.
Edit only actual stale support references outside the already owned files.
Keep the approved constitution version and completed amendment intact.
Retain correct maintainer/domain guidance unchanged.
Record each retained product reference as an explicit removal record, including these feature 008 artifacts.
Do not edit ignored reference roots or other external repositories.

### Independent Validation for User Story 3

- [X] T033 [US3] Verify README consistency and classify all remaining maintained-document references in `specs/008-remove-legacy-backends/quickstart.md` section 9.

**Checkpoint**: The README distinction is clear, attribution remains intact, and all maintained guidance agrees.
The documentation inventory is independently reviewable without native terminal access.
The final combined inventory also requires US2's runtime result.

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Verify the integrated cutover and remove only artifacts created by verification.
This phase adds no speculative features, abstractions, or unrelated cleanup.

- [X] T034 Format changed package Elisp with `scripts/format-and-clean.sh` after all implementation writers finish.
- [X] T035 Run `scripts/compile-and-test.sh` in both isolated dependency environments and the focused `../../tests/pkg-claude-code-ide-test.el` suite.
- [X] T036 Verify integrated acceptance and record every FR/SC outcome in `specs/008-remove-legacy-backends/quickstart.md`.
- [X] T037 Remove only created verification artifacts and record the safe reload/restart handoff in `specs/008-remove-legacy-backends/quickstart.md` section 10.

**Final status — 2026-09-13**: 37 of 37 tasks are complete.
The renewed native verification ran Pi on Node 25.9.0 and used the user-approved Claude Code and Codex trust prompts.
Pi's expired OpenAI OAuth login is the only external gap. It is outside the terminal cutover and was left unchanged.
The final `quickstart.md` matrix records 44 passed outcomes.

**T034 completion**: Preserve unrelated work if the formatter touches files outside the change.
Treat unexpected indentation as a syntax defect, not a style preference.
Apply the parent repository's existing formatting convention only to its two changed consumers.

**T035 completion**: Require successful byte compilation and full ERT results with optional dependencies absent.
Repeat with native optional integration dependencies available and verify that their integration tests actually execute.
Run the existing native-compilation option where available, without a real terminal dependency.
Record commands, load paths, Emacs version, results, and skips separately for each environment.
Do not use the planning baseline's test count as a required count after deletions.
Fix new failures rather than hiding them with skips or warning suppression.

**T036 completion**: Confirm all fifteen requirements, seven success criteria, fourteen acceptance scenarios, and eight edge cases.
Run native Agent, six-layout, and approved-remote checks against the final combined code.
Earlier story evidence is not a substitute if later edits changed the exercised behavior.
Require zero active retired support across the combined maintained-file inventory.
A batch mock pass does not prove native rendering or remote behavior.
Record unavailable external prerequisites as blockers and leave dependent tasks incomplete.

**T037 completion**: Restore test-only preferences and remove only temporary files or directories created by this work.
Use `emacsclient` for applicable Elisp reloads, or use the documented restart boundary for the clean cutover.
Preserve pre-existing terminal buffers and processes during that handoff.
Confirm exact disposable targets before any Stop action.
Do not commit, uninstall packages, or rewrite Git history.

## Dependencies & Execution Order

### Phase Dependencies

```text
Setup T001–T002
  └─ Foundation T003 → T004
       ├─ US1 T005–T016 → US2 T017–T023 ─┐
       └─ US3 T024–T033 ─────────────────┤
                                        └─ Final T034–T037
```

US2's dependency on US1 is necessary for complete caller migration, not a new architecture layer.
US3 can run alongside US1 or US2 because its initial tasks own different files.
US3's final documentation check does not claim that runtime retirement has already passed.

### Within Each User Story

- US1 test wave: T005 and T006 run together after T004.
- US1 implementation wave: T007–T010 run together after the test wave settles.
- T011 follows T007 because both edit `claude-code-ide.el`.
- T012 follows T005 and the implementation wave because it edits the package test file.
- T013 follows T011–T012. T014–T016 then run sequentially in the disposable native environment.
- US2 starts after US1. T017 precedes the T018–T020 implementation wave.
- T021 follows T017–T020 because the suite must match the final removed surface.
- T022 follows T021. T023 follows the runtime changes and failure checks.
- US3 T024–T031 run together after the foundation.
- T032 follows T024–T031 and consumes only remaining inventory targets.
- T033 follows T032. T034 waits for all three story checkpoints.
- Final execution is T034 → T035 → T036 → T037.

New regressions precede their implementation and demonstrate the relevant failure where the old behavior is incorrect.
Existing preservation checks can already pass. Do not create artificial failures to satisfy a test-first label.
Models and interfaces remain existing code, so this plan needs no model-generation, endpoint, or database tasks.

### File Ownership and Validation

One integration owner controls `claude-code-ide.el` across T004, T007, T011, and T018.
Serialize all edits to `claude-code-ide-tests.el` across T003, T005, T012, T017, and T021.
Apply the same rule to the Session module and the parent tests.

Parallel writers must skip formatting, linters, builds, and test execution while siblings edit.
The integration owner runs focused checks only after each wave settles.
Run the complete formatter and quality gates after integration, not inside parallel workers.
Treat `quickstart.md` as a shared evidence file with one writer.
Schedule native verification serially so Sessions, frames, and preferences do not interfere.

## Parallel Example: User Story 1

After T004, run T005 and T006 together. They edit different test files.
After their focused regression checkpoint, run this disjoint implementation wave:

| Task | Exclusive write ownership | Shared contract |
| --- | --- | --- |
| T007 | `claude-code-ide.el` | C1 factory result, preflight, and registration order |
| T008 | `claude-code-ide-session.el` | C1–C2 setup/input and companion behavior |
| T009 | `claude-code-ide-session-idle.el` | C3 dual output paths and focus |
| T010 | `../../lisp/pkgs/pkg-claude-code-ide.el` | C6 actual mode guards and preserved settings |

T011 cannot overlap T007. T012 cannot overlap another package-test writer.

## Parallel Example: User Story 2

After T017, run T018, T019, and T020 together:

| Task | Exclusive write ownership | Shared contract |
| --- | --- | --- |
| T018 | `claude-code-ide.el` | C5 removed selectors/state and safe ownership |
| T019 | `claude-code-ide-session.el` | C5 removed helpers/aliases and unsupported-mode boundary |
| T020 | `scripts/compile-and-test.sh`, `.github/workflows/test.yml` | No retired dependency discovery or installation |

T021 then integrates the final test surface. Do not run the full suite during this edit wave.

## Parallel Example: User Story 3

After T004, run T024–T031 with one owner per task.
The tasks own README, terminal guides, separate prior-spec directories, and the transient/backlog pair respectively.
They share only the removal-record rule and original-attribution requirement.
T032 integrates remaining maintained guidance after those owners finish.
T033 alone writes the documentation inventory evidence.

## Requirement and Contract Coverage

| Requirement or contract | Task ownership |
| --- | --- |
| FR-001, C1 construction | T004, T007–T008, T014–T016 |
| FR-002, C5 retired implementation | T007–T009, T018–T021, T023 |
| FR-003, C5 removed preference surface | T010, T017–T019, T023 |
| FR-004, C2–C3 | T005–T009, T011, T013–T014 |
| FR-005, C4 persistent ownership | T007, T012–T013, T016 |
| FR-006, C4 layouts | T006, T010, T012–T013, T015 |
| FR-007, C1 availability | T002–T004, T017, T021–T022, T035 |
| FR-008, C1 rollback | T003–T004, T007–T008, T017–T019, T022 |
| FR-009, C4 remote boundaries | T007, T012, T016–T017, T022 |
| FR-010, C7 verification | T003, T005–T006, T012–T013, T017, T020–T023, T035 |
| FR-011, C7 maintained-file scope | T001, T024–T033 |
| FR-012, C7 README distinction | T024, T033 |
| FR-013, C7 removal records | T001, T023, T026–T033, T036 |
| FR-014, constitution | T001 and the already completed constitution 2.0.0 amendment |
| FR-015, C6 and upgrade boundary | T007–T010, T017–T019, T023, T037 |

The existing Agent Session, attachment, companion, saved-layout, and pending-request entities belong to US1.
Their optional-support, removed-state, and upgrade boundaries belong to US2.
The removal-record classification belongs to US3.
Research R1–R5/R8–R9 guide the foundation and runtime tasks. R6 guides test isolation. R7 guides documentation scope.

## Implementation Strategy

### MVP First

Use Setup, Foundation, and US1 as the first independently testable behavior increment.
US1 demonstrates that the surviving Ghostel workflow still works.
It is not a shippable partial removal.
The smallest shippable scope includes US1, US2, US3, and final verification because all three stories are P1 requirements.

### Incremental Delivery

1. Complete scope and dependency preparation.
2. Establish the shared preflight and verify its boundary failures.
3. Migrate and validate the surviving Ghostel workflow.
4. Remove remaining policy, dead support, and test dependencies.
5. Align all maintained documentation without changing external/local reference material.
6. Verify the integrated cutover before reporting completion.

### Parallel Team Strategy

Use the file-ownership waves above rather than assigning overlapping core or test files to separate workers.
Let documentation owners work alongside the runtime owner after the foundation.
Keep integration checks and native verification with one owner.
Story checkpoints support independent validation, not early release or silent scope reduction.

## Notes

All tasks remain unchecked until implementation evidence satisfies their completion criteria.
Planning-time compilation and tests do not complete any implementation task.
No runtime code, task implementation, or commit is part of this task-generation command.
