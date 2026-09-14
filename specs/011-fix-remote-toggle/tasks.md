---

description: "Implementation tasks for remote Session toggle resolution"
---

# Tasks: Fix Remote Session Toggle

**Input**: Design documents from `specs/011-fix-remote-toggle/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/session-toggle.md`, `quickstart.md`

**Tests**: ERT regression tasks are required by the project constitution and the implementation plan.

**Organization**: Tasks are grouped by user story. The smallest complete change implements User Story 1 first and then proves local compatibility through User Story 2.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it touches a different file and has no incomplete dependency.
- **[Story]**: Maps the task to its user story.
- Every task names an exact file path.

## Phase 1: Setup

**Purpose**: Record the current behavior before code changes.

- [X] T001 Run the existing focused toggle ERT command from `specs/011-fix-remote-toggle/quickstart.md` and record the baseline result

**Checkpoint**: The current focused tests run, and the reported remote failure remains the behavior to fix.

---

## Phase 2: Foundational

**Purpose**: Reuse the existing Session registry and manager layout state.

No foundational code is required. The existing Session accessors, active Session key, layout table, and window-toggle helper supply the needed seams.

**Checkpoint**: Start User Story 1 without a new module, dependency, state field, or transport path.

---

## Phase 3: User Story 1 - Toggle the Attached Remote Session (Priority: P1) MVP

**Goal**: Toggle the exact attached remote Session from its terminal or managed project view without selecting another host or making a remote request.

**Independent Test**: Register colliding local and remote Sessions. Invoke the public command from the remote terminal and managed view. Confirm that only the exact remote Session reaches the existing window-toggle helper.

### Tests for User Story 1

> Write these tests first and confirm that the relevant cases fail before implementation.

- [X] T002 [US1] Add a failing public-command ERT test for a remote terminal colliding with a local Session and two remote hosts in `claude-code-ide-tests.el`
- [X] T003 [US1] Add failing public-command ERT tests for exact managed-view ownership, unrelated RPC buffers, and disconnected targets in `claude-code-ide-tests.el`

### Implementation for User Story 1

- [X] T004 [US1] Add the constant-size active-layout project-view Session accessor in `claude-code-ide-manager.el`
- [X] T005 [US1] Add the manager accessor declaration and implement exact terminal, exact managed-view, and remote-no-fallback resolution in `claude-code-ide.el`

**Checkpoint**: User Story 1 passes its focused ERT cases. Toggle performs no discovery, attachment, reattachment, Agent start, or network access.

---

## Phase 4: User Story 2 - Preserve Existing Local Toggle Behavior (Priority: P2)

**Goal**: Keep local terminal ownership, local project fallback, layout behavior, focus behavior, and no-session errors unchanged.

**Independent Test**: Invoke the public command from a local Session terminal, a local project buffer, and a local project without a Session. Compare all visible results with the existing contract.

### Tests for User Story 2

- [X] T006 [US2] Add public-command ERT regressions for local terminal ownership, local project fallback, and the no-session error in `claude-code-ide-tests.el`


**Checkpoint**: User Stories 1 and 2 pass independently. Local callers receive no new prompt or remote behavior.

---

## Phase 5: Polish & Cross-Cutting Verification

**Purpose**: Prove the complete change and load it into the active editor.

- [X] T007 Run all focused toggle ERT scenarios in `claude-code-ide-tests.el`
- [X] T008 Run `scripts/compile-and-test.sh` and require successful byte compilation with zero unexpected ERT results
- [X] T009 Reload `claude-code-ide-manager.el` and `claude-code-ide.el` with `emacsclient`, then execute the live scenarios in `specs/011-fix-remote-toggle/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Starts immediately.
- **Foundational (Phase 2)**: Confirms that no shared infrastructure work exists.
- **User Story 1 (Phase 3)**: Starts after the baseline. T002 and T003 must fail before T004 and T005.
- **User Story 2 (Phase 4)**: Starts after T005 because it verifies compatibility of the completed toggle path.
- **Polish (Phase 5)**: Starts after both user stories pass.

### User Story Dependencies

```text
Setup
  └── User Story 1 (P1, MVP)
        └── User Story 2 (P2 compatibility proof)
              └── Full verification and live validation
```

- **User Story 1**: Delivers the remote toggle fix.
- **User Story 2**: Depends on the User Story 1 implementation because it proves that change preserves local behavior.

### Within User Story 1

1. T002 adds terminal and host-collision failures.
2. T003 adds managed-view and unavailable-context failures.
3. T004 adds the manager-owned view accessor.
4. T005 integrates exact Session resolution into the public command.

### Within User Story 2

T006 supplies the independent compatibility proof. User Story 1 already preserves the existing local fallback in `claude-code-ide.el`.

### Parallel Opportunities

No implementation tasks are safely parallel. The regression tests share `claude-code-ide-tests.el`, and the core command depends on the manager accessor. Keep this small fix sequential to avoid same-file conflicts.

## Parallel Example: User Story 1

No parallel batch is recommended. Execute T002 through T005 in order so the regressions fail before the implementation changes.

## Parallel Example: User Story 2

No parallel batch is recommended. Execute T006 after T005 so it verifies the completed public command.

## Implementation Strategy

### MVP First

1. Complete T001.
2. Complete T002 and T003.
3. Complete T004 and T005.
4. Run the User Story 1 focused tests.
5. Stop here if only the reported remote failure needs demonstration.

### Incremental Delivery

1. Deliver User Story 1 as the remote toggle fix.
2. Add User Story 2 as the local compatibility proof.
3. Run the focused and complete repository gates.
4. Reload the changed files and execute the live validation guide.

## Notes

- Keep remote Session directories as bare metadata.
- Do not change `claude-code-ide--get-session-buffer` for this feature.
- Do not add a hard require, state table, remote request, or new command.
- Do not pin exact error wording in tests.
- Do not commit unless the user explicitly requests it.
