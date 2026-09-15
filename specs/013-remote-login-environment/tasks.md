---

description: "Implementation tasks for remote login environment"
---

# Tasks: Remote Login Environment

**Input**: Design documents from `specs/013-remote-login-environment/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [remote-launch-config.md](contracts/remote-launch-config.md), [quickstart.md](quickstart.md)

**Tests**: The constitution and implementation plan require focused ERT regressions before implementation and the complete batch gate afterward.

**Organization**: Tasks are grouped by user story. Each story ends with an independent behavior check.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: This task can run in parallel with adjacent marked tasks because it uses different files.
- **[Story]**: The user story from `spec.md`.
- Every task names its target file or validation file.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Reuse the existing package, ERT suite, SSH transport, and remote Worktree runner.

No project initialization or dependency task is required.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the shared host configuration and command seam used by every user story.

**Critical**: Complete this phase before any user story.

- [X] T001 Add failing ERT coverage for valid and invalid shell pairs, copied argument lists, and literal wrapper ordering in `claude-code-ide-tests.el`
- [X] T002 Extend `claude-code-ide-remote-launch-config`, `claude-code-ide-zmx--remote-launch-spec`, and the shared login-command builder in `claude-code-ide-zmx.el`

**Checkpoint**: The package can validate and represent one optional shell preference per exact host without making a remote request.

---

## Phase 3: User Story 1 - Launch with the normal remote environment (Priority: P1) MVP

**Goal**: Give direct sibling and managed Worktree Agents the configured login environment, exact directory, and literal Agent arguments.

**Independent Test**: Configure `ramhorn` with `/usr/bin/zsh` and `("-lic")`. Compare command lookup, `PATH`, one selected variable, locale, umask, and working directory with a normal interactive login from the same directory.

### Tests for User Story 1

- [X] T003 [US1] Add failing `claude-code-ide-test-remote-login-environment-user-story-1-*` ERT cases for sibling command framing, post-startup zmx identity clearing, and hostile literals in `claude-code-ide-tests.el`
- [X] T004 [US1] Add failing `claude-code-ide-test-remote-login-environment-user-story-1-*` ERT cases for Worktree resolution, isolated stdout, directory restoration, and unchanged runner arguments in `claude-code-ide-tests.el`

### Implementation for User Story 1

- [X] T005 [P] [US1] Extend `claude-code-ide-zmx--remote-create-command` and its fresh sibling caller to apply the shell pair in `claude-code-ide-zmx.el` and `claude-code-ide.el`
- [X] T006 [P] [US1] Add shell-aware Agent resolution and generated bootstrap wrapping while preserving the runner protocol in `claude-code-ide-remote-worktree.el`
- [X] T007 [US1] Run the `remote-login-environment.*user-story-1` ERT selector from `claude-code-ide-tests.el` and confirm all selected tests pass

**Checkpoint**: Each fresh-launch workflow supplies the selected environment before Agent resolution and execution.

---

## Phase 4: User Story 2 - Choose parity only for intended hosts (Priority: P1)

**Goal**: Apply the shell preference only to its exact host while preserving direct and existing-target behavior elsewhere.

**Independent Test**: Configure one of two approved hosts. Confirm only that host uses the shell path and arguments. Confirm attach and reattach do not read the preference.

### Tests for User Story 2

- [X] T008 [US2] Add failing `claude-code-ide-test-remote-login-environment-user-story-2-*` ERT cases for exact-host isolation, byte-compatible direct commands, Worktree launch invalidation, and unchanged attach paths in `claude-code-ide-tests.el`

### Implementation for User Story 2

- [X] T009 [US2] Make `claude-code-ide--create-remote-session` pass shell fields only to fresh creation, keep `claude-code-ide-zmx--remote-attach-command` and `claude-code-ide--reattach-remote-session` direct, and make `claude-code-ide-remote-worktree--launch-selection` capture shell fields in `claude-code-ide.el`, `claude-code-ide-zmx.el`, and `claude-code-ide-remote-worktree.el`
- [X] T010 [US2] Run the `remote-login-environment.*user-story-2` ERT selector from `claude-code-ide-tests.el` and confirm all selected tests pass


---

## Phase 5: User Story 3 - Diagnose startup problems without fallback (Priority: P2)

**Goal**: Keep startup output visible and fail explicitly without a direct retry or replacement Agent.

**Independent Test**: Exercise a missing shell and failed startup in both fresh-launch workflows. Confirm host-qualified failures, visible output, no direct fallback, and no replacement Agent or ordinary shell.

### Tests for User Story 3

- [X] T011 [US3] Add failing `claude-code-ide-test-remote-login-environment-user-story-3-*` ERT cases for missing shells, failed startup, visible output, sibling rollback, Worktree refusal, and no direct fallback in `claude-code-ide-tests.el`

### Implementation for User Story 3

- [X] T012 [US3] Make `claude-code-ide--create-remote-session` rollback shell startup exits and make `claude-code-ide-remote-worktree--prepare-launch` report host-qualified shell failures before dispatch without direct retry in `claude-code-ide.el` and `claude-code-ide-remote-worktree.el`
- [X] T013 [US3] Run the `remote-login-environment.*user-story-3` ERT selector from `claude-code-ide-tests.el` and confirm all selected tests pass


---

## Phase 6: Polish and Cross-Cutting Concerns

**Purpose**: Document the interface, run all gates, and prove the real remote workflow.

- [X] T014 [P] Document `:shell`, `:shell-args`, direct defaults, and the `ramhorn` zsh example in `README.org`
- [X] T015 [P] Document startup output, failure guidance, and Worktree bootstrap ordering in `docs/remote.org`
- [X] T016 Format `claude-code-ide-zmx.el`, `claude-code-ide.el`, `claude-code-ide-remote-worktree.el`, and `claude-code-ide-tests.el` with `scripts/format-and-clean.sh`
- [X] T017 Run the complete `remote-login-environment` ERT selector from `claude-code-ide-tests.el`
- [X] T018 Run the required repository gate with `scripts/compile-and-test.sh`
- [X] T019 Reload changed Emacs Lisp with `emacsclient` and complete the sibling and Worktree parity scenarios in `specs/013-remote-login-environment/quickstart.md`
- [X] T020 Add ERT coverage for copied, literal, unique launch environment assignments in `claude-code-ide-tests.el`
- [X] T021 Validate optional `:environment` entries and reserve zmx identity names in `claude-code-ide-zmx.el`
- [X] T022 Apply environment assignments before sibling and Worktree shell startup and Agent execution in `claude-code-ide-zmx.el`, `claude-code-ide.el`, and `claude-code-ide-remote-worktree.el`
- [X] T023 Document launch environment assignments and the `SKIP_TMUX=1` example in `README.org`, `docs/remote.org`, and feature artifacts
- [X] T024 Rerun the focused ERT selector and required repository gate

- [X] T025 Defer Worktree launch-setting validation until a fresh Agent branch is selected
- [X] T026 Apply each environment assignment once before each configured shell startup
- [X] T027 Resolve an existing Worktree Agent from that Worktree's directory
- [X] T028 Prove existing Worktree open and reattach bypass malformed fresh-launch settings
- [X] T029 Correct protocol environment documentation and rerun focused and repository gates

---

## Dependencies and Execution Order
### Phase Dependencies

```text
Phase 1: Setup
    ↓
Phase 2: Foundation
    ↓
Phase 3: User Story 1 (MVP)
    ├───────────────┐
    ↓               ↓
Phase 4: US2    Phase 5: US3
    └───────┬───────┘
            ↓
Phase 6: Polish and complete validation
```

- **Setup** has no implementation work.
- **Foundation** blocks every user story.
- **User Story 1** supplies the two fresh-launch paths required by User Stories 2 and 3.
- **User Stories 2 and 3** are behaviorally independent after User Story 1. Serialize them in one checkout because both edit `claude-code-ide-tests.el` and launch files.
- **Polish** starts after all selected stories pass their focused checks.

### User Story Dependencies

- **User Story 1 (P1)** depends only on Foundation.
- **User Story 2 (P1)** depends on User Story 1 command integration. It does not depend on User Story 3.
- **User Story 3 (P2)** depends on User Story 1 command integration. It does not depend on User Story 2 behavior.

### Within Each User Story

1. Add the story's failing behavior tests.
2. Confirm each new test can fail on its named regression.
3. Implement the smallest source change that satisfies those tests.
4. Run the story selector and require at least one selected test.
5. Continue only after the story checkpoint passes.

## Parallel Opportunities

- T005 and T006 can run in parallel after T003 and T004 because they edit separate source paths.
- T014 and T015 can run in parallel after all user stories.
- User Stories 2 and 3 have no safe same-checkout parallelism because they share test and launch files.

## Parallel Example: User Story 1

```text
Task: "T005 Extend direct sibling creation in claude-code-ide-zmx.el and claude-code-ide.el"
Task: "T006 Extend Worktree preparation and bootstrap in claude-code-ide-remote-worktree.el"
```

Run these tasks together only after T003 and T004 establish their failing behavior checks.

## Parallel Example: User Story 2

No safe same-story parallel pair exists. T008 defines the exact-host and compatibility checks that T009 must satisfy.

## Parallel Example: User Story 3

No safe same-story parallel pair exists. T011 defines the failure and output checks that T012 must satisfy.

## Implementation Strategy

### MVP First

1. Complete Foundation.
2. Complete User Story 1.
3. Run T007.
4. Perform Quickstart Scenario 1 on `ramhorn`.
5. Stop if environment parity is not proven.

The MVP is User Story 1. It provides the requested environment parity for both fresh-launch workflows.

### Incremental Delivery

1. Add exact-host opt-in and direct defaults through User Story 2.
2. Add explicit failure and diagnostic behavior through User Story 3.
3. Update both user documents.
4. Run focused ERT, the full gate, and live validation.

### Parallel Team Strategy

1. Complete T001 and T002 in one shared foundation.
2. Assign T005 to the direct sibling path.
3. Assign T006 to the Worktree path.
4. Integrate both after their independent test groups exist.
5. Serialize User Stories 2 and 3 to avoid same-file edits.

## Notes

- `[P]` means different files and no dependency on another incomplete marked task.
- Story labels map every implementation task to its acceptance flow.
- The Worktree runner protocol remains unchanged.
- Direct behavior is a compatibility contract, not a fallback.
- Use `emacsclient` for the live Emacs reload.
- Do not create `tasks.md` work for speculative shell discovery or a new shell adapter.
