---

description: "Implementation tasks for opt-in remote RPC Project views"
---

# Tasks: Opt-in Remote RPC Magit View

**Input**: Design documents from `/specs/005-remote-rpc-magit/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: The constitution requires ERT coverage for all new logic. Write each story test first and confirm that it fails for the expected missing behavior.

**Organization**: Tasks follow user stories so each story has an independent test and delivery checkpoint.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: The task uses a different file and does not depend on unfinished work.
- **[Story]**: The task maps to a user story from `spec.md`.
- Every task names its target file.

---

## Phase 1: Setup

**Purpose**: Add the one planned module without changing runtime behavior.

- [X] T001 Create the GPL header, lexical binding, feature group, and `provide` form in `claude-code-ide-remote-project.el`

**Checkpoint**: The empty module loads without RPC, Magit, Dired, or remote access.

---

## Phase 2: Foundational

**Purpose**: Build the shared attempt, connection, and view primitives required by every story.

**Critical**: Complete this phase before user-story work.

### Foundation tests

- [X] T002 Add failing ERT coverage for Session-keyed intents, attempt freshness, private abandonment, and per-view creation admission in `claude-code-ide-tests.el`
- [X] T003 Add failing ERT coverage for no-provision connection guards, authentication retry admission, worker timer ownership, transport unlock, and current-response health in `claude-code-ide-tests.el`

### Foundation implementation

- [X] T004 Implement Session intents, attempt tokens, view records, attachment checks, and the non-`error` non-`quit` abandonment condition in `claude-code-ide-remote-project.el`
- [X] T005 Implement capability checks plus scoped guards for `tramp-rpc--connect`, `tramp-rpc--establish-controlmaster`, and `tramp-rpc--start-server-process` in `claude-code-ide-remote-project.el`
- [X] T006 Implement worker-local authentication timers, strict noninteractive SSH bindings, native startup checkpoints, and owned stdout/stderr unlock in `claude-code-ide-remote-project.el`
- [X] T007 Implement the 30-second health deadline, uncached `process-file` health request, route-aware ownership, and cancellable Worktree identity resolution in `claude-code-ide-remote-project.el`

**Checkpoint**: The shared primitives pass T002–T003 without loading optional packages on unused paths.

---

## Phase 3: User Story 1 - Preserve existing work unless enabled (Priority: P1)

**Goal**: Keep local and disabled-host behavior unchanged. Make both per-host choices independent and disabled by default.

**Independent Test**: Attach local, disabled remote, unapproved, and enabled Sessions. Only the explicitly approved enabled host may request preparation. Preference changes alone do nothing.

### Tests for User Story 1

- [X] T008 [US1] Add failing ERT cases for disabled defaults, exact-host approval, local Sessions, preference changes, optional-package absence, and cleanup independence in `claude-code-ide-tests.el`

### Implementation for User Story 1

- [X] T009 [P] [US1] Define `claude-code-ide-remote-project-view-hosts` and `claude-code-ide-remote-project-cleanup-hosts` with nil defaults in `claude-code-ide-manager.el`
- [X] T010 [US1] Add soft feature loading and exact-host admission at first managed display without remote work on rejected paths in `claude-code-ide-manager.el`
- [X] T011 [P] [US1] Qualify the enabled first-managed-display exception in the remote-host option docstring in `claude-code-ide-zmx.el`

**Checkpoint**: User Story 1 passes independently with optional RPC and Magit packages unavailable.

---

## Phase 4: User Story 2 - Get a Project view on first managed display (Priority: P1)

**Goal**: Show a healthy remote Magit or Dired view beside the terminal. Reuse views by exact host and Worktree or directory.

**Independent Test**: First-display healthy Git, non-Git, custom-provider, same-Worktree, different-Worktree, and different-host Sessions. Verify focus and buffer identity.

### Tests for User Story 2

- [X] T012 [US2] Add failing ERT cases for missing-view Magit/Dired fallback, custom providers, provider failure, and no-window preparation in `claude-code-ide-tests.el`
- [X] T013 [US2] Add failing ERT cases for exact-host Worktree sharing, non-Git directory identity, unchanged Session metadata, and reuse without refresh in `claude-code-ide-tests.el`

### Implementation for User Story 2

- [X] T014 [P] [US2] Implement native Magit/Dired lookup, per-view creation admission, provider fallback, no-window bindings, and conservative origin tracking in `claude-code-ide-remote-project.el`
- [X] T015 [P] [US2] Implement the enabled terminal-first ordinary-window layout and focus-preserving completion insertion in `claude-code-ide-manager.el`
- [X] T016 [US2] Connect first-display preparation, view publication, same-root reuse, and unsplittable-layout guidance across `claude-code-ide-manager.el` and `claude-code-ide-remote-project.el`

**Checkpoint**: User Story 2 independently displays the correct Project view without changing the selected window.

---

## Phase 5: User Story 3 - Preserve bulk attachment and later layout restoration (Priority: P1)

**Goal**: Keep bulk attach lazy. Restore exact surviving views and maintain per-Session manual-close suppression across navigation and reattach.

**Independent Test**: Bulk-attach three Sessions, display them individually, restore a completed background result, exercise closure commands, reattach, and use `R`.

### Tests for User Story 3

- [X] T017 [US3] Add failing ERT cases for bulk-attach laziness, exact-buffer layout restore, background completion return, reattach, and `R` health-gated reuse in `claude-code-ide-tests.el`
- [X] T018 [US3] Add failing command-loop ERT cases for `C-x 0`, `q`, `C-x b`, `C-x 1`, Dired `RET`, shared-buffer kill, Session switch, and Help-window reuse in `claude-code-ide-tests.el`

### Implementation for User Story 3

- [X] T019 [P] [US3] Implement remembered Session view intent, manual-close suppression, sibling-kill invalidation, and replacement permission in `claude-code-ide-remote-project.el`
- [X] T020 [P] [US3] Capture exact view objects and substitute current names through saved current/previous/next buffer references in `claude-code-ide-manager.el`
- [X] T021 [US3] Integrate bulk-attach deferral, first display, reattach, background-ready insertion, and full `R` reset semantics in `claude-code-ide-manager.el`
- [X] T022 [US3] Implement frame-local attachment snapshots, layout epochs, and pre/post-command dismissal detection in `claude-code-ide-manager.el`

**Checkpoint**: User Story 3 restores only exact live buffers. Only `R` clears the initiating Session's suppression.

---

## Phase 6: User Story 4 - Diagnose project access without blocking the terminal (Priority: P1)

**Goal**: Keep terminal interaction responsive while each failure reports its host, phase, and corrective action.

**Independent Test**: Exercise missing client/server, incompatible response, denied authentication, inaccessible directory, delayed health, delayed provider, and fallback failure.

### Tests for User Story 4

- [X] T023 [US4] Add failing ERT cases for prerequisite guidance, current health, deadline reporting, no acquisition, retry policy, fallback boundaries, and suppressed worker windows in `claude-code-ide-tests.el`

### Implementation for User Story 4

- [X] T024 [P] [US4] Map capability, authentication, server, health, directory, provider, and cancellation outcomes to host-scoped guidance in `claude-code-ide-remote-project.el`
- [X] T025 [P] [US4] Preserve terminal-only manager layouts and avoid repeated notices after failed or canceled attempts in `claude-code-ide-manager.el`
- [X] T026 [US4] Apply TRAMP error-display, Magit warning, interaction, provider fallback, and `process-file-side-effects` bindings in `claude-code-ide-remote-project.el`

**Checkpoint**: User Story 4 reports each failure once and leaves the terminal and unrelated Sessions usable.

---

## Phase 7: User Story 5 - Keep pending results separate from Session control (Priority: P2)

**Goal**: Cancel and supersede attempts without stale display, focus theft, retry, detach, or shared-connection retirement.

**Independent Test**: Delay each phase, then switch, reset, cancel, detach, replace the attachment, disable the host, remove approval, and use another RPC client.

### Tests for User Story 5

- [X] T027 [US5] Add failing ERT cases for cancellation, supersession, exact-attachment invalidation, late results, Session switches, focus preservation, and shared-connection reuse in `claude-code-ide-tests.el`

### Implementation for User Story 5

- [X] T028 [P] [US5] Implement cancel, supersede, host-change invalidation, queued-result rejection, and incomplete-candidate handling in `claude-code-ide-remote-project.el`
- [X] T029 [P] [US5] Add `C` for `claude-code-ide-manager-cancel-project-view-at-point` in the action menu in `claude-code-ide-transient.el`
- [X] T030 [US5] Wire cancel, reset, detach, Session-ended, and attachment-replacement events to exact attempt invalidation in `claude-code-ide-manager.el`
- [X] T031 [US5] Enforce same-Session visible-terminal display permission while preserving selected and unrelated windows in `claude-code-ide-manager.el`

**Checkpoint**: User Story 5 rejects every stale result and leaves independent transport failure policy unchanged.

---

## Phase 8: User Story 6 - Optionally close only owned Project views on explicit detach (Priority: P2)

**Goal**: Close only proven feature-created, unmodified, exclusive Magit/Dired views after successful explicit detach.

**Independent Test**: Run the complete cleanup matrix for disabled, shared, reused, modified, custom, source-file, unknown, cross-host, and newer-attachment cases.

### Tests for User Story 6

- [X] T032 [US6] Add failing ERT cleanup-matrix cases, including perspective hooks and assertions for zero remote I/O, saves, prompts, or connection cleanup in `claude-code-ide-tests.el`

### Implementation for User Story 6

- [X] T033 [P] [US6] Implement snapshot-based cleanup eligibility, retention reasons, exact-mode checks, hook vetoes, and local-only buffer disposal in `claude-code-ide-remote-project.el`
- [X] T034 [US6] After T033, capture pre-detach ownership and invoke cleanup only after successful explicit `D` or `X` detach in `claude-code-ide-manager.el`

**Checkpoint**: User Story 6 cleans only eligible views. Generic close, network loss, Stop, and exit perform no new cleanup.

---

## Phase 9: Polish and Cross-Cutting Verification

**Purpose**: Finish user documentation and run the required package and acceptance gates.

- [X] T035 [P] Document both host options, `R`, `? C`, reuse without refresh, setup guidance, and cleanup boundaries in `README.org`
- [X] T036 Run `./scripts/format-and-clean.sh` on changed Emacs Lisp files and inspect its changes against `.specify/memory/constitution.md`
- [X] T037 Run `./scripts/compile-and-test.sh` and require successful byte compilation with zero unexpected ERT results in `claude-code-ide-tests.el`
- [X] T038 Execute the authorized real-host scenarios and record client/server versions plus observed results in `specs/005-remote-rpc-magit/quickstart.md`

---

## Dependencies and Execution Order

### Phase dependencies

- **Setup** has no dependencies.
- **Foundational** depends on Setup and blocks all user stories.
- **US1** depends on Foundational.
- **US2** depends on US1 admission and host options.
- **US3** depends on US2 view publication and layout insertion.
- **US4** depends on US1 and Foundational. It can proceed beside US2 after the admission API is stable.
- **US5** depends on US2 completion and Foundational attempt ownership.
- **US6** depends on US1 cleanup configuration and US2 origin tracking.
- **Polish** depends on all selected user stories.

### User story graph

```text
Setup -> Foundation -> US1 -> US2 -> US3
                         |      |-> US5
                         |      `-> US6
                         `-> US4

US3 + US4 + US5 + US6 -> Polish
```

### Contract and entity traceability

| Story | Data and contract coverage | Tasks |
|-------|----------------------------|-------|
| US1 | Host Preferences and Admission | T008–T011 |
| US2 | Shared Project View, provider contract, and Display/Focus | T012–T016 |
| US3 | Session View Intent, Frame Display Intent, restore, and Manual Closure | T017–T022 |
| US4 | Preparation Attempt health, authentication, deadline, and Diagnostics | T023–T026 plus T002–T007 |
| US5 | Attempt freshness, Cancel, supersession, and completion authority | T027–T031 |
| US6 | Cleanup Snapshot, eligibility, retention, and explicit Detach | T032–T034 |

### Within each story

1. Add the ERT cases.
2. Run only those cases and confirm the expected failure.
3. Implement the story.
4. Run the story cases and confirm the independent criterion.
5. Continue to the next story.

---

## Parallel Execution Examples

### User Story 1

After T008 fails as expected, run these tasks together:

```text
T009: Define host options in claude-code-ide-manager.el
T011: Update the remote-host docstring in claude-code-ide-zmx.el
```

Then run T010.

### User Story 2

After T012–T013 fail as expected, run these tasks together:

```text
T014: Implement provider and view identity in claude-code-ide-remote-project.el
T015: Implement terminal-first layout in claude-code-ide-manager.el
```

Then run T016.

### User Story 3

After T017–T018 fail as expected, run these tasks together:

```text
T019: Implement Session view intent in claude-code-ide-remote-project.el
T020: Implement exact-buffer layout storage in claude-code-ide-manager.el
```

Then run T021–T022 in order because both update the manager.

### User Story 4

After T023 fails as expected, run these tasks together:

```text
T024: Implement outcome guidance in claude-code-ide-remote-project.el
T025: Preserve terminal-only failure layouts in claude-code-ide-manager.el
```

Then run T026.

### User Story 5

After T027 fails as expected, run these tasks together:

```text
T028: Implement attempt cancellation in claude-code-ide-remote-project.el
T029: Add the cancel menu entry in claude-code-ide-transient.el
```

Then run T030–T031 in order because both update the manager.

### User Story 6

After T032 fails as expected, implement T033 before T034:

```text
T033: Implement cleanup eligibility in claude-code-ide-remote-project.el
T034: Integrate its cleanup API in claude-code-ide-manager.el
```

---

## Implementation Strategy

### MVP first

1. Complete Setup and Foundational.
2. Complete User Story 1.
3. Verify disabled and unapproved paths independently.
4. Stop before remote Project-view behavior if a safety gate fails.

User Story 1 is the safety MVP. User Story 2 is the first user-visible Project-view increment.

### Incremental delivery

1. Add US1 host gating without changing existing workflows.
2. Add US2 first-display Project views and exact sharing.
3. Add US3 lazy bulk behavior, restoration, and manual closure.
4. Add US4 failure guidance and responsiveness.
5. Add US5 cancellation and stale-result ownership.
6. Add US6 conservative explicit-detach cleanup.
7. Run formatting, the full suite, and authorized real-host acceptance.

### Scope controls

- Keep Session identity keyed by Session ID.
- Keep agent definitions, CLI paths, zmx transport, metadata policy, and installed RPC sources unchanged.
- Reuse surviving views without automatic refresh.
- Preserve user-directed native `g` refresh.
- Never commit unless the user asks.

## Phase 10: Convergence

- [X] T039 CRITICAL: Add forward declarations for every optional `tramp-rpc` advice target in `claude-code-ide-remote-project.el` per Constitution Elisp Standards (partial)
- [X] T040 Dispose or quarantine proven unpublished candidates, invalidate attempts when candidates die, prevent later reuse, and add ERT coverage in `claude-code-ide-remote-project.el` and `claude-code-ide-tests.el` per T028 (partial)
- [X] T041 Recheck exact current host approval before publishing or reporting queued attempt results and add disablement, host-removal, and host-change ERT cases in `claude-code-ide-remote-project.el`, `claude-code-ide-manager.el`, and `claude-code-ide-tests.el` per FR-032 (partial)
- [X] T042 Complete and record real-host no-acquisition, missing-server, and reconnect acceptance with acquisition entry points observed per plan: Current health and no provisioning verification (partial)
- [X] T043 Complete and record real-host Dired fallback, same-Worktree sharing, different-Worktree separation, and different-host separation per plan: Correct provider and view sharing verification (partial)
- [X] T044 Complete and record real-host manager-focus and unrelated-window-focus completion cases per plan: No stale display or focus theft verification (partial)

## Phase 11: Convergence

- [X] T045 CRITICAL: Prove default-provider creation ownership before assigning `created-by-feature`, classify preexisting or uncertain Magit/Dired results as reused, and add race, cancellation, and cleanup ERT coverage in `claude-code-ide-remote-project.el` and `claude-code-ide-tests.el` per Constitution VI and FR-035 (contradicts)
- [X] T046 Run and record real-host Project-view completion with manager focus and unrelated-window focus, including the actual Session, remote buffer identity, and selected-window result in `specs/005-remote-rpc-magit/quickstart.md` per FR-023 and US2/AC6 (partial)

## Phase 12: Convergence

- [X] T047 Use each target frame's stored managed Session and attachment token for completion and dismissal admission, remove global current-Session checks from those frame-local decisions, and add multi-frame ERT coverage in `claude-code-ide-manager.el` and `claude-code-ide-tests.el` per FR-033 and T022 (partial)
