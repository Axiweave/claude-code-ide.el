---

description: "Implementation tasks for remote project history"
---

# Tasks: Remote Project History

**Input**: Design documents from `specs/012-remote-project-history/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/remote-project-picker.md`, `quickstart.md`

**Tests**: The feature specification requires independently testable user stories. Write each listed ERT regression before its implementation task and confirm that it fails for the intended reason.

**Organization**: Tasks are grouped by user story so each story remains independently testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it changes a different file and has no incomplete dependency.
- **[Story]**: Maps the task to a user story in `spec.md`.
- Every task includes an exact file path.

## Phase 1: Setup (Shared Test Infrastructure)

**Purpose**: Prepare isolated test state for history and persistence behavior.

- [X] T001 Add an isolated remote-repository-history test fixture that restores all changed manager globals in `claude-code-ide-tests.el`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add the shared bounded MRU state and persistence lifecycle required by every story.

**CRITICAL**: Complete this phase before user story work.

- [X] T002 Add failing ERT coverage for per-host MRU ordering, deduplication, the 20-path limit, serialization, missing-field restore, and persistence reset in `claude-code-ide-tests.el`
- [X] T003 Implement the validated per-host MRU helpers and `:remote-repositories` manager-state serialization, restore, empty-state, and reset behavior in `claude-code-ide-manager.el`
- [X] T004 Run the focused foundational ERT tests from `claude-code-ide-tests.el` and confirm all shared MRU and persistence contracts pass

**Checkpoint**: Bounded remote repository history survives the manager persistence lifecycle without remote I/O.

---

## Phase 3: User Story 1 - Reopen a Recent Remote Project (Priority: P1) MVP

**Goal**: Select a recent repository for one host and retain it across an Emacs restart.

**Independent Test**: Accept a remote-open request, simulate persistence reload, and select the remembered repository without entering its path again.

### Tests for User Story 1

- [X] T005 [US1] Add failing ERT coverage for host-scoped remembered selection, most-recent-first candidates, restart-style restore, paths with spaces, and record-after-request acceptance in `claude-code-ide-tests.el`

### Implementation for User Story 1

- [X] T006 [US1] Extend the remote repository reader with host-scoped remembered candidates and direct candidate-to-path mapping in `claude-code-ide-manager.el`
- [X] T007 [US1] Record and save a remote repository only after the remote Worktree request returns an operation ID in `claude-code-ide-manager.el`
- [X] T008 [US1] Run the focused US1 ERT tests from `claude-code-ide-tests.el` and verify remembered selection works after simulated reload

**Checkpoint**: User Story 1 works without manual path entry for a remembered repository.

---

## Phase 4: User Story 2 - Open a New Absolute Path (Priority: P1)

**Goal**: Keep manual absolute-path entry available when the repository is not remembered.

**Independent Test**: Select `Other…`, enter a valid absolute path, and verify that the accepted request records it while invalid or canceled input changes nothing.

### Tests for User Story 2

- [X] T009 [US2] Add failing ERT coverage for the `Other…` choice, empty history, absolute-path validation, cancellation, and refused-request history preservation in `claude-code-ide-tests.el`

### Implementation for User Story 2

- [X] T010 [US2] Add the `Other…` picker sentinel and reuse the validated absolute-path input loop without parsing display text in `claude-code-ide-manager.el`
- [X] T011 [US2] Run the focused US2 ERT tests from `claude-code-ide-tests.el` and verify manual entry and cancellation behavior

**Checkpoint**: User Story 2 accepts new absolute paths without weakening validation or polluting history.

---

## Phase 5: User Story 3 - Choose Another Project from a Remote Row (Priority: P2)

**Goal**: Make explicit remote open choose a host and repository while ordinary open remains contextual.

**Independent Test**: Invoke explicit remote open on a remote Session row and select another host, then verify ordinary open still uses the row context.

### Tests for User Story 3

- [X] T012 [US3] Replace `claude-code-ide-test-remote-worktree-manager-known-context-skips-prompts` with a failing explicit-command prompt regression and preserve `claude-code-ide-test-remote-worktree-manager-open-prefers-rpc-context` in `claude-code-ide-tests.el`

### Implementation for User Story 3

- [X] T013 [US3] Make `claude-code-ide-manager-open-remote` always read a configured host and repository while leaving `claude-code-ide-manager-open` contextual in `claude-code-ide-manager.el`
- [X] T014 [US3] Run the focused US3 ERT tests from `claude-code-ide-tests.el` and verify explicit and contextual command behavior

**Checkpoint**: User Story 3 opens another remote project from any manager row without removing the contextual fast path.

---

## Phase 6: User Story 4 - Keep Invalid History Inert (Priority: P3)

**Goal**: Restore malformed or stale history safely without remote access or lost valid entries.

**Independent Test**: Restore mixed history and verify valid entries normalize locally, malformed entries disappear, and unconfigured-host entries cannot become selectable or trigger requests.

### Tests for User Story 4

- [X] T015 [US4] Add failing ERT coverage for malformed hosts and paths, duplicate and oversized restored lists, unconfigured-host inertness, older state, and zero remote calls during restore in `claude-code-ide-tests.el`

### Implementation for User Story 4

- [X] T016 [US4] Harden remote repository history restoration and current-host picker admission without local file predicates or remote calls in `claude-code-ide-manager.el`
- [X] T017 [US4] Run the focused US4 ERT tests from `claude-code-ide-tests.el` and verify restore remains inert

**Checkpoint**: User Story 4 safely handles untrusted persisted history and changing host configuration.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Align user documentation and prove the complete workflow.

- [X] T018 [P] Document explicit remote project selection, recent repositories, `Other…`, and manager persistence in `README.org`
- [X] T019 [P] Document history safety, no-I/O restore, cancellation, and troubleshooting in `docs/remote.org`
- [X] T020 Run every scenario in `specs/012-remote-project-history/quickstart.md` that the local environment supports and record exact observed outcomes there only if the guide needs correction
- [X] T021 Run `./scripts/compile-and-test.sh` and require zero unexpected ERT results before completion

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Starts immediately.
- **Foundational (Phase 2)**: Depends on T001 and blocks all user stories.
- **User Story 1 (Phase 3)**: Depends on the foundational MRU and persistence lifecycle.
- **User Story 2 (Phase 4)**: Depends on the US1 repository picker seam.
- **User Story 3 (Phase 5)**: Depends on the picker from US1 and US2.
- **User Story 4 (Phase 6)**: Depends on the foundational restore seam. It can run in parallel with US1 through US3 after Phase 2.
- **Polish (Phase 7)**: Depends on all selected user stories.

### User Story Completion Order

```text
Setup → Foundation ─┬→ US1 → US2 → US3 ─┬→ Polish
                    └→ US4 ──────────────┘
```

### User Story Dependencies

- **US1 (P1)**: Uses only the foundational MRU and persistence state.
- **US2 (P1)**: Extends the US1 picker with manual entry.
- **US3 (P2)**: Routes the explicit command through the completed picker. It preserves the existing contextual command.
- **US4 (P3)**: Uses the foundational restore seam and does not depend on picker implementation details.

### Within Each User Story

- Write the story regression first and confirm its intended failure.
- Implement only the behavior required by that story.
- Run the focused story regressions before the checkpoint.
- Do not start final documentation or the full gate until selected stories pass independently.

## Parallel Opportunities

- T015 through T017 can run in parallel with T005 through T014 after T004 because US4 owns the restore-hardening slice. Coordinate edits to `claude-code-ide-manager.el` and `claude-code-ide-tests.el` before concurrent work.
- T018 and T019 can run in parallel after all behavior is stable because they modify different documentation files.
- Focused test commands for completed stories can run independently only when no task is rewriting `claude-code-ide-tests.el`.

## Parallel Example: User Story 1 and User Story 4

```text
Task A: "Implement US1 remembered repository selection in claude-code-ide-manager.el after T005."
Task B: "Implement US4 restore normalization in claude-code-ide-manager.el after T015."
```

These tasks are logically independent but share files. Coordinate their exact function ownership before running them concurrently.

## Parallel Example: Documentation

```text
Task A: "Update remote project history behavior in README.org."
Task B: "Update remote history safety and troubleshooting in docs/remote.org."
```

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational tasks T001 through T004.
2. Complete User Story 1 tasks T005 through T008.
3. Validate that one remembered repository survives simulated reload and can be selected without retyping.
4. Stop here for the smallest useful increment if manual new-path entry can temporarily remain the current raw prompt.

### Incremental Delivery

1. Add US1 for remembered selection and persistence.
2. Add US2 for discoverable manual entry and cancellation safety.
3. Add US3 so explicit remote open can choose another project from a remote row.
4. Add US4 restore hardening before final release.
5. Complete documentation and the full quality gate.

### Minimal Change Discipline

- Keep all production changes in `claude-code-ide-manager.el`.
- Reuse the existing manager persistence lifecycle and remote validators.
- Represent MRU order with list order. Do not add timestamps.
- Do not add a history-management command, remote browser, callback layer, or storage dependency.

## Notes

- `[P]` marks tasks that can safely run concurrently in different files.
- Story labels map directly to `spec.md` user stories.
- No task creates `tasks.md` dependencies outside the files named in the plan.
- Do not commit unless the user asks.

## Phase 8: Convergence

- [X] T022 Restore the validated manual-entry retry loop and cover retry and cancellation behavior per contract: Explicit Remote Open 5 (partial)
- [X] T023 Make persisted history normalization discard arbitrary malformed containers without signaling per FR-013 and US4/AC2 (partial)
- [X] T024 Add focused ERT coverage for restored limits, malformed containers, changed-host picker admission, and disabled history persistence per plan: Tests (partial)

## Phase 9: Free-Input Repository Picker

- [X] T025 Replace the `Other…` sentinel with validated non-candidate `completing-read` input and align tests and feature documentation per FR-006

## Phase 10: Convergence

- [X] T026 Fix the changed-host picker regression to capture repository candidates without matching prompt text and assert the exact host-scoped list per plan: Tests (partial)
