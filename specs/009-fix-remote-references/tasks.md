---
description: "Implementation tasks for remote current-file references"
---

# Tasks: Fix Remote File References

**Input**: Design documents from `specs/009-fix-remote-references/`.

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [reference contract](contracts/current-file-reference.md), and [quickstart.md](quickstart.md).

**Tests**: Constitution II requires ERT coverage for new logic. The approved plan also requires command-level regression tests. These tasks include only observable regression and compatibility coverage, not a new test framework.

**Organization**: Tasks follow the two prioritized user stories. Both use the same formatter and test file, so their mutations must remain serial.

## Format: `[ID] [P?] [Story] Description`

- `[P]` identifies different-file tasks that can run together after their stated prerequisites.
- `[US1]` and `[US2]` map tasks to the specification’s user stories.
- All paths are relative to the repository root unless explicitly absolute.
- Leave task checkboxes unchecked until implementation and required verification are complete.

## Path Conventions

- Runtime changes belong in `claude-code-ide.el`.
- Regression tests belong in `claude-code-ide-tests.el`.
- Reuse `claude-code-ide-remote-worktree.el` and `claude-code-ide-zmx.el` unchanged.
- Update existing user documentation in `README.org`, not a new `README.md`.
- Keep the current branch. Do not commit, create a worktree, install dependencies, or change host approvals.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Ground implementation in the existing command and formatter without creating infrastructure.

- [X] T001 Confirm current formatter callers and source-context behavior in `claude-code-ide.el` against `specs/009-fix-remote-references/plan.md` and the existing reference tests in `claude-code-ide-tests.el`.

T001 must identify `claude-code-ide-send-current-file` as the only remote-aware caller. Confirm that `claude-code-ide-send-file` retains the omitted/default argument policy. Use an Elisp language server for references if one is available. Otherwise, use the repository search tools.

**Checkpoint**: The implementer knows the current source locations and can preserve unrelated user changes.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Confirm that the existing foundation supports both stories.

No new foundation tasks are needed. T001 and the approved research establish the prerequisites:

- The Session already supplies a host and a bare Session directory.
- The RPC parser already supplies exact approved destination identity and a host-local path without remote I/O.
- The formatter already owns relative-versus-absolute path selection.
- The command test family already supports temporary buffers and captured terminal delivery.

Do not add a Session schema, path module, parser, settings, database, fixture framework, or Agent adapter.

**Checkpoint**: After T001, US1 can start. Shared safety checks belong in US1’s formatter implementation, not a later unsafe cutover.

## Phase 3: User Story 1 - Send a Relative Remote Reference (Priority: P1)

**Goal**: Send the reported remote file as `@packages/core/lib/executor.ts#L316` through the existing transient `@` action.

**Independent Test**: With source `/rpc:v12mac:/Users/yufu/v12x/packages/core/lib/executor.ts`, select line 316 and target a Session on `v12mac` at `/Users/yufu/v12x`. The real command must deliver the expected reference body, with existing insertion whitespace. Existing no-selection and range-selection coverage must remain valid.

### Tests for User Story 1

- [X] T002 [US1] Add a failing selected-line remote command regression to `claude-code-ide-tests.el` using the real RPC parser and a configured test destination.

For T002, call `claude-code-ide-send-current-file`, not only the formatter. Use a synthetic source buffer, a temporary Session buffer, and an isolated Session registry. Capture the actual terminal string. Reuse existing selection test conventions. Do not connect to a remote host or mock the path result. Clear synthetic filenames and restore buffers and state on failure. Run this regression before the source change and record its failure.

### Implementation for User Story 1

- [X] T003 [US1] Extend `claude-code-ide--file-reference-path` in `claude-code-ide.el` with lazy remote-aware conversion, exact destination checks, lexical containment, and unchanged local/default behavior.
- [X] T004 [US1] Enable remote-aware conversion only in `claude-code-ide-send-current-file` in `claude-code-ide.el`, preserving source resolution, selection suffixes, and reference delivery.
- [X] T005 [US1] Run the new regression and existing current-file selection tests in `claude-code-ide-tests.el`, confirming exact reported output and unchanged local formatting.

T003 implements the private interface from the plan:

```elisp
(claude-code-ide--file-reference-path file &optional target-buffer remote-aware)
```

Required behavior for T003:

1. Keep the omitted/default argument behavior unchanged for the file-picker caller.
2. Detect a remote source or remote target before loading any remote module.
3. Preserve ordinary local `@` dependency behavior and existing local project fallback.
4. Load the existing remote-worktree module optionally only when remote conversion needs it.
5. Add a cross-file declaration for `claude-code-ide-remote-worktree-target-for-file`.
6. Reuse that parser without moving, renaming, or duplicating it.
7. Compare its exact destination with the live target Session host before removing remote qualification.
8. Reject incompatible, unsupported, incomplete, or invalid remote context before reference delivery.
9. Require a nonempty, bare absolute Session directory.
10. Compute remote relative paths lexically with filesystem handlers disabled and `/` as the default directory.
11. Return a relative path inside the directory, or the host-local absolute path outside it.
12. Treat both `..` and a `../` prefix as outside-directory results.

Do not use filesystem predicates, resolve symlinks, inspect SSH configuration, or start a connection. Do not use terminal `default-directory` as the Session directory. Update the changed formatter and current-file docstrings in their implementation tasks.

**Checkpoint**: US1 works independently. Basic context rejection is already present, so the first usable increment cannot send a guessed cross-host reference.

## Phase 4: User Story 2 - Keep References Correct for the Target Session (Priority: P2)

**Goal**: Preserve file identity across target directories, outside-directory files, incompatible contexts, and local workflows.

**Independent Test**: Send the same source to a nested target directory and observe `@core/lib/executor.ts`. Send a same-host outside file and observe its bare absolute path. For a host mismatch or missing remote context, observe `user-error` and zero prompt insertion or terminal delivery. Local commands and excluded file-send actions retain their existing outputs.

### Tests for User Story 2

- [X] T006 [US2] Add missing context-rejection regressions to `claude-code-ide-tests.el` for exact destination mismatch, local/remote mismatch, unknown target, invalid directory, and unsupported remote route.
- [X] T007 [US2] Add missing containment and compatibility regressions to `claude-code-ide-tests.el` for nested bases, outside files, sibling prefixes, lazy local loading, and the unchanged file-picker policy.

T006 must assert error category and absence of both delivery forms, not exact error text. A visible prompt buffer cannot supply a missing remote Target Session. Include an exact-destination distinction such as `v12mac` versus `user@v12mac` where it adds coverage beyond a different-host case.

T007 must exercise distinct risks rather than add duplicate success rows. Preserve existing local, Evil, Emacs-region, file-browser, Session-buffer, and `#` command tests. Use existing coverage when it already proves the contract. Verify that local current-file references do not request the remote module. Guard against filesystem dispatch during bare-path conversion where practical. The unchanged file-picker test must exercise the public picker command rather than assert that a flag was omitted.

### Implementation and Validation for User Story 2

- [X] T008 [US2] Run the US2 regressions in `claude-code-ide-tests.el` and correct any uncovered formatter behavior in `claude-code-ide.el` without changing excluded command contracts.

US2 uses the complete formatter from US1. Do not add a second implementation if its acceptance cases already pass. If a new regression reveals a gap, capture the failure before correcting it. After correction, rerun both story test groups.

**Checkpoint**: Both stories pass independently through their command-level checks. The `#`, `f`, `F`, `h`, project-send, and MCP at-mention contracts remain outside this change.

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Complete documentation and integrated verification after both story checks pass.

- [X] T009 [P] Update relevant existing reference guidance in `README.org` for target-relative remote `@` paths, exact destination requirements, and explicit context errors.
- [X] T010 [P] Align `specs/009-fix-remote-references/quickstart.md` with implemented regression names and validated commands without claiming unrun live results.
- [X] T011 Run `scripts/format-and-clean.sh claude-code-ide.el claude-code-ide-tests.el` and then `scripts/compile-and-test.sh` after integration.
- [X] T012 Reload changed `claude-code-ide.el` through `emacsclient` and exercise the live transient scenario in `specs/009-fix-remote-references/quickstart.md` with the intended target explicitly authorized.
- [X] T013 Record actual focused, complete-gate, and live results in `specs/009-fix-remote-references/quickstart.md`, with any unavailable live prerequisite stated explicitly.

Implementation evidence appears in `quickstart.md`. The live check used the existing remote Source File and Session with a temporary local prompt destination.
It exercised the interactive current-file action without sending text to the Agent terminal or submitting a prompt.

T009 and T010 start only after T008 passes. If `README.org` has no relevant text, add a short explanation to its existing usage section. Do not create another documentation file or change unrelated guidance.

For T011, run the formatter and complete gate once after integration. If either reveals an in-scope defect, correct it and rerun the affected verification. Preserve unrelated user edits.

For T012, use the existing Emacs server and configured remote resources. Inspect the inserted reference before prompt submission. Do not press Enter to submit an Agent prompt. Do not create Sessions, approve hosts, or install optional packages for validation without user authorization.

If a required live prerequisite is unavailable, record the exact blocker and completed automated evidence. Leave T012 incomplete rather than claim end-to-end success. T013 may record that blocker, but it does not remove it.

## Dependencies & Execution Order

### Phase Dependencies

```text
Setup T001
    -> Existing foundation confirmed
    -> US1 T002 -> T003 -> T004 -> T005
    -> US2 T006 -> T007 -> T008
    -> Documentation T009 and T010 concurrently
    -> Integrated gate T011
    -> Live verification T012
    -> Evidence T013
```

### User Story Dependencies

- US1 depends on T001 and the existing foundation only.
- US2 depends on US1’s formatter and current-file integration. Its acceptance checks remain independently runnable.
- The stories intentionally serialize because both mutate `claude-code-ide.el` and `claude-code-ide-tests.el`.
- T009 and T010 depend on T008 but not on each other.
- T011 depends on both documentation tasks and all implementation tasks.
- T012 requires T011 success and an authorized live target.
- T013 follows the live attempt and must distinguish success from a recorded blocker.

### Within Each User Story

- Write the bug regression before the implementation and observe its failure.
- Keep new tests deterministic, isolated, and safe for the complete suite.
- Validate the public command rather than private wiring or source text.
- Finish the story’s checks before the next mutation phase.

### Parallel Opportunities

Only T009 and T010 carry `[P]`. They own different documentation files after behavior stabilizes. Do not run builds or tests while concurrent workers still edit files. One integration owner runs T011 after they finish.

No runtime task pair is independent enough to justify concurrent mutation or extra coordination.

## Parallel Example: User Story 1

Use serial execution:

```text
T002: Write and run the failing command regression in claude-code-ide-tests.el.
T003: Implement conversion in claude-code-ide.el.
T004: Enable the current-file caller in claude-code-ide.el.
T005: Run the story checks in claude-code-ide-tests.el.
```

The regression must precede implementation. The two source tasks share one file, so no safe implementation parallelism exists here.

## Parallel Example: User Story 2

Use serial execution:

```text
T006: Add context rejection coverage in claude-code-ide-tests.el.
T007: Add missing containment and compatibility coverage in claude-code-ide-tests.el.
T008: Validate both stories and correct uncovered behavior in claude-code-ide.el.
```

T006 and T007 share the test file. Do not assign them to concurrent writers.

After US2, the real parallel pair is:

```text
T009: Update README.org.
T010: Update specs/009-fix-remote-references/quickstart.md.
```

## Requirements and Design Mapping

| Requirement or design element | Tasks | Observable evidence |
| --- | --- | --- |
| FR-001, FR-002: relative remote path without RPC prefix | T002–T005 | Exact reported reference body |
| FR-003: receiving Session directory | T003, T007, T008 | Nested target gives `core/lib/executor.ts` |
| FR-004: existing marker and selection suffix | T002, T004, T005 | Selected line 316 and existing selection tests |
| FR-005, FR-006: outside-directory and containment | T003, T007, T008 | Bare absolute outside path and sibling-prefix rejection |
| FR-007, FR-008: incompatible or incomplete context | T003, T006, T008 | Error with no delivery |
| FR-009: local and source-context compatibility | T004, T005, T007, T008 | Existing command outputs and lazy local dependency behavior |
| FR-010: shared Agent workflow | T003, T004, T011, T012 | Shared command path and intended live Agent reference |
| Source File and selection | T002, T004, T005 | Real command uses existing source-context resolver |
| Target Session host and bare directory | T003, T006, T007 | Exact identity checks and target-relative output |
| File Reference and insertion contract | T002, T004–T008 | Existing whitespace, suffix, prompt, and terminal behavior |
| SC-001 through SC-005 | T005, T008, T011–T013 | Focused tests, complete gate, and recorded live evidence |

## Implementation Strategy

### MVP First (User Story 1)

1. Complete T001 and confirm the existing foundation.
2. Complete T002 through T005 for the exact reported reference.
3. Demonstrate US1 with synthetic buffers and captured delivery.
4. Continue through US2 and final verification before declaring the feature complete.

US1 is the smallest useful demonstration, not permission to omit US2 or shared safety checks.

### Incremental Delivery

1. Establish the failing command regression.
2. Add the smallest scoped formatter change and current-file integration.
3. Prove host, directory, and compatibility behavior through US2.
4. Update the two independent documentation files.
5. Run integrated and live verification.
6. Report only observed results and remaining blockers.

### Parallel Team Strategy

Use one implementation owner for both runtime files. After T008, two documentation workers may own T009 and T010 independently. They must skip formatters, linters, builds, and tests. The implementation owner performs final verification after both changes are complete.

## Notes

- No task authorizes a commit or a new branch.
- No task changes Session metadata ownership or creates filesystem mappings.
- Existing test coverage should remain when it protects behavior. Do not add tests for private flags, source text, or exact error wording.
- Remote parser loading remains lazy. Local `@` use must not gain a dependency on the remote-worktree module.
- Do not mark implementation complete based on the planning probes alone.
