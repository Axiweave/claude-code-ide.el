---
description: "Executable tasks for predefined manager layouts"
---

# Tasks: Predefined Manager Layouts

**Input**: Design documents from `specs/007-add-layout-presets/`.
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/elisp-surface.md](contracts/elisp-surface.md), and [quickstart.md](quickstart.md).
**Branch**: `main`.
**Scope**: Six presets across four user stories. Dired belongs to US1, not a fifth story.

**Tests**: No optional standalone test phase or TDD workflow is added.
Implementation and integration tasks include the ERT coverage required by constitution principle II and `AGENTS.md`.
Keep new behavior checks in `claude-code-ide-tests.el`, using isolated optional-dependency fixtures.
Do not load test mocks into the live Emacs.

**Organization**: Story phases follow the specification's priority order: US1 and US2 are P1, US3 and US4 are P2.
A checkpoint validates an increment. It does not authorize delivery of an incomplete six-preset feature.

## Format: `[ID] [P?] [Story] Description`

- Every execution task has an unchecked checkbox, sequential ID, and exact repository-relative file paths.
- Story tasks also carry their `[US1]` through `[US4]` label.
- `[P]` identifies a disjoint-file pair that can run after its stated prerequisites finish.
- Unmarked tasks run serially within their phase.

## Path Conventions and Execution Rules

This is an existing Emacs Lisp package, not a new project skeleton.
Use root-level source files and the existing ERT suite.
Do not add dependencies, a layout framework, Agent-specific branches, or arbitrary whole-layout customization.

Before modifying exported symbols, inspect references with the available language server.
If no Elisp language server is available, inspect definitions, declarations, and callers with repository search.
Migrate callers in the same task as any signature or data-shape change.

Use Emacs 28.1-compatible local code and existing optional-dependency boundaries.
Remote project companions retain the existing Emacs 30.1 RPC-client prerequisite and supported POSIX-host constraint.
Do not change Ghostel native source, RPC transport policy, host approval, or Agent identity.

For concurrent tasks, freeze the contracts below before dispatch.
Concurrent workers must skip formatters, linters, builds, and tests until their edits reach the integration barrier.
One owner integrates each shared-file boundary and runs validation after the pair finishes.
Do not commit, change branches, or create a worktree without a separate user request.

## Phase 1: Setup (Existing Project)

**Purpose**: Make the required implementation gate executable without concealing its recorded failure.

The planning run compiled successfully but reported 896 expected results, ten unexpected results, and nine skips.
The ten failures concern missing Magit modules in the batch environment.
This is a known prerequisite error, not a specification failure or an approved exception.

- [X] T001 Prepare the existing dependency environment for `scripts/compile-and-test.sh` using the error recorded in `specs/007-add-layout-presets/plan.md`. Do not add runtime dependencies, weaken the gate, or edit unrelated tests. After an environment correction, run the exact gate. If it still fails, stop and report the missing prerequisite.

**Checkpoint**: The exact gate passes in the prepared environment, with no claim that new feature behavior exists yet.
No package installation, remote connection, or unrelated source repair is implicit in this task.

Implementation baseline: the exact gate passed with a temporary HOME and `EMACSLOADPATH` containing the installed dependency directories.
The isolated HOME prevents the script from selecting older Spacemacs-30 dependencies.
Result: 907 expected tests, zero unexpected tests, eight skipped tests. Compilation passed with warnings.
No package, source, test, or gate-script change was needed for this correction.

---

## Phase 2: Foundational (Blocking Shared Contracts)

**Purpose**: Establish one request representation and migrate its shared interface before story-specific providers use it.

- [X] T002 Add `claude-code-ide-manager-layout-preset` and a fixed request resolver in `claude-code-ide-manager.el`. Use the six symbols from `specs/007-add-layout-presets/data-model.md`, with `magit-left` as default. Capture the provider, companion side, exact directory, creation permission, and frame epoch. Validate Session identity and preset values before destructive state changes.
- [X] T003 Carry the captured request through `claude-code-ide-manager.el` and `claude-code-ide-remote-project.el`. Add the required `LAYOUT-REQUEST` argument to `claude-code-ide-remote-project-prepare`. Update every Session-managed caller, declaration, attempt, display intent, and affected fixture in `claude-code-ide-tests.el` together. Preserve `claude-code-ide-remote-project-open-target` arguments and callback results. Do not retain an old-arity fallback that reads global preferences.

**Checkpoint**: The shared request has one shape across all producers and consumers.
Existing Git preparation and explicit-target operations still work.
The new provider implementations remain story work, not placeholder callbacks in the foundation.

Foundation validation: byte compilation passed. The full suite returned 908 expected results, 0 unexpected results, and 8 skips.

### Fixed Shared Contracts

| Contract | Agreed representation |
| --- | --- |
| Presets | `magit-left`, `magit-right`, `shell-left`, `shell-right`, `dired-left`, `dired-right` |
| Captured request | Immutable plist from data-model section 5, stored on existing attempt and frame intent |
| Shell owner | Canonical Session ID, never directory, Worktree, host alone, or buffer name |
| Shell table | Runtime-only `claude-code-ide-manager--companion-shells`, mapping Session ID to exact Ghostel buffer |
| Session-layer shell creation | Private helper accepting an exact local or admitted RPC-qualified directory, returning an ordinary Ghostel buffer |
| Session-layer liveness | Private helper accepting a buffer and checking its actual Ghostel process |
| Shared view key | `(HOST LOCATION-KIND CANONICAL-LOCATION PROVIDER-DESCRIPTOR)` |
| Provider descriptor | `(COMPANION-KIND PROVIDER REQUESTED-RPC-DIRECTORY)`, only for Git/Dired |
| Remote results | Existing view result or Session-owned shell result, distinguished by `:companion-kind` |
| Creation authority | New default layout or explicit shell reset only, never an ordinary saved-shell return |

Use existing naming conventions for private helper names.
Do not create public helper APIs solely to support these tasks.

---

## Phase 3: User Story 1 — Choose the Familiar Content Layouts (Priority: P1)

**Goal**: Apply both Magit and both Dired arrangements through one preference, with unchanged custom-content behavior and Agent focus rules.

**Independent Test**: In a disposable local Session, verify default Magit-left and both Magit orientations with a recognizable custom provider.
Verify both Dired orientations with that provider still configured.
Dired must show the exact Session directory without Magit or Ghostel.
An old side value, invalid preset, missing directory, or failed split must not replace the Agent or silently select another preset.

### Implementation for User Story 1

- [X] T004 [US1] Implement captured Git and direct Dired provider selection in `claude-code-ide-manager.el`. Pass the exact Session directory to the Git provider and retain its existing Dired fallback. Make Dired independent from that provider, Magit, and Ghostel. Reject inaccessible directories without substituting another directory.
- [X] T005 [US1] Apply captured companion orientation to both content split sites in `claude-code-ide-manager.el`. Remove `claude-code-ide-manager-session-window-side` and every production read of it. Preserve the sidebar and the existing Agent buffer. Use the captured display intent for delayed remote orientation, not the current global preference.
- [X] T006 [US1] Connect the new request to default-layout and explicit-reset entry points in `claude-code-ide-manager.el`. Keep public command arguments, the `R` binding, and successful target-window return behavior unchanged. Preserve ordinary saved-layout precedence and honor explicit manager-focus requests. Do not apply a preference merely because it changed.
- [X] T007 [US1] Complete Git/Dired failure recovery in `claude-code-ide-manager.el` and maintain behavioral ERT coverage in `claude-code-ide-tests.el`. Replace the obsolete side-preference test with observable preset and cutover behavior. Cover provider failure, invalid selection, inaccessible directory, split failure, Agent identity, and keyboard focus. Use the `claude-code-ide-test-manager-layout-preset-` prefix for new feature checks.

Local content validation: three preset regression checks passed. Byte compilation and the full suite passed with 909 expected results, 0 unexpected results, and 8 skips.

**Checkpoint**: The four non-shell arrangements pass local acceptance without a companion-shell dependency.
US4 supplies remote provider parity. A local-only checkpoint is not permission to ship a narrower feature.
Validation guide: quickstart sections 5, 6, 8, and 12.

---

## Phase 4: User Story 2 — Work Beside an Ordinary Shell (Priority: P1)

**Goal**: Display an ordinary Ghostel shell on either side of the existing Agent, with one independent shell per Session.

**Independent Test**: Apply both shell presets and print the shell PID and working directory.
Use two Sessions with the same host and directory.
Their shell buffers, processes, directory changes, and command output must remain independent.
Repeat with Ghostel as the local Agent terminal backend for this acceptance run.

### Implementation for User Story 2

- [X] T008 [P] [US2] Implement private ordinary-shell creation and liveness helpers in `claude-code-ide-session.el`. Use `ghostel-create` with a unique name and nil display action. Soft-load Ghostel and preserve its shell preferences and input mode. Check the actual buffer-local process, without invoking Agent setup, environment injection, or zmx attachment.
- [X] T009 [P] [US2] Add the runtime Session-to-shell table in `claude-code-ide-manager.el`. Resolve legacy directory arguments to canonical Session IDs before ownership lookup. Keep the table outside persisted state and saved layouts. Preserve entries when windows close, layouts reset, or another non-shell preset applies.
- [X] T010 [US2] Integrate both shell presets with the Session-layer helpers in `claude-code-ide-manager.el`. Reuse the exact owned live shell, otherwise create only when the captured request permits it. Start a new shell in the exact Session directory. Publish its buffer only under that Session ID, without adding an Agent row.
- [X] T011 [US2] Complete shell-startup recovery in `claude-code-ide-session.el` and `claude-code-ide-manager.el`, with required ERT coverage in `claude-code-ide-tests.el`. Cover missing package/module, failed startup, wrong-directory refusal, same-directory Session isolation, and unchanged Agent backend. Remove only request-created partial buffers without live processes. Preserve a started but unpublished shell as an ordinary terminal and report its buffer.

Shell validation: six preset regression checks passed. The full gate returned 912 expected results, 0 unexpected results, and 8 skips.
Native verification used two real OMP Sessions in the same directory. Their ordinary shell PIDs were 38945 and 42957.
Both shell orientations worked. Mirroring preserved the first shell's PID, directory, buffer, and process, with the Agent selected.

**Checkpoint**: Both local shell arrangements execute real commands beside the same Agent.
Only T008 and T009 form a parallel pair. T010 waits for both, and T011 integrates their behavior.
Validation guide: quickstart sections 5, 7, and 12.

---

## Phase 5: User Story 3 — Preserve Saved Work and Reset Deliberately (Priority: P2)

**Goal**: Restore saved work without automatic shell replacement and keep live shells after Agent Session removal.

**Independent Test**: Resize a shell layout, select the shell window, change the default, switch away, and return.
The saved windows, selected window, shell process, output, and directory must remain intact.
Mirror the layout without restarting its shell.
After shell exit or buffer deletion, return without a replacement process, then explicitly reset to create one.
Remove a disposable Agent Session and continue its surviving shell command.

### Implementation for User Story 3

- [X] T012 [US3] Extend layout capture and persistence filtering in `claude-code-ide-manager.el` using data-model section 4. Record the applied preset, companion kind, and exact shell object/name metadata. Copy applied metadata during later capture instead of reading the current default. Never serialize buffer objects, processes, threads, or provider functions. Keep older plist records valid without migration aliases.
- [X] T013 [US3] Extend native saved-layout restoration in `claude-code-ide-manager.el`. Substitute a renamed owned shell safely and reject unrelated buffers that reuse its old name. Restore retained exited output or remaining windows with reset guidance. Preserve saved selection when possible, otherwise select the Agent. Do not turn missing-shell recovery into default-layout shell creation.
- [X] T014 [US3] Enforce shell creation permission across switch, reset, and recovery paths in `claude-code-ide-manager.el`. Reuse a live shell through explicit reset and mirroring. Replace an exited or missing shell only for an explicit shell reset or genuinely new default layout. Leave manually closed shell windows closed during ordinary restoration. Preserve live shells when Git or Dired replaces their displayed layout.
- [X] T015 [US3] Release shell ownership through `claude-code-ide-manager-session-ended` in `claude-code-ide-manager.el` without killing its buffer or process. Retain ownership for remembered remote Sessions after temporary disconnection. Verify the existing verified-Stop and removal callbacks in `claude-code-ide.el`. Reuse those callbacks rather than adding Agent-specific cleanup or directory-based shell adoption.
- [X] T016 [US3] Complete saved-layout and lifecycle integration in `claude-code-ide-manager.el`, with behavioral ERT coverage in `claude-code-ide-tests.el`. Cover renamed/killed buffers, reused names, closed windows, output retention, reset reuse, and Session removal. Cover old persisted records and temporary disconnection. Make every ordinary saved-shell return start zero replacement processes, including unrelated restoration-error recovery.

Saved-layout validation: all eleven preset regression checks passed.
Native Emacs restored the renamed shell, selected window, and exact saved width after the default changed to Dired.
A manually closed shell window stayed closed. Returning after shell exit attempted zero shell creations.
Stopping the second disposable Agent released ownership. Its shell completed the pending command with PID 42957 and the same directory.
The interim full gate found one obsolete test that required a default layout to override saved work.
That mock-only test was removed. The new old-layout regression checks saved precedence with actual windows.
Final gate results appear in the delivery record.

**Checkpoint**: Saved layout precedence and shell ownership survive all specified lifecycle transitions.
Ghostel's exit preference controls whether old output remains available.
Shell survival ends at ordinary Emacs shutdown. This feature adds no process persistence.
Validation guide: quickstart sections 7 through 10.

---

## Phase 6: User Story 4 — Use Presets Without Weakening Remote Access Rules (Priority: P2)

**Goal**: Apply all six arrangements through existing approved remote access, without blocking or replacing the Agent.

**Independent Test**: On an already approved disposable remote Session, verify all six arrangements and the exact companion host and directory.
Keep the Agent usable during preparation.
Supersede a pending request and verify that its result cannot replace the newer layout or take focus.
Use isolated ERT fixtures for disabled access, failed access, approval changes, unsupported hosts, and stale callbacks.
No failure may create a local substitute or approve additional access.

### Implementation for User Story 4

- [X] T017 [US4] Integrate exact-host admission and request creation permissions in `claude-code-ide-manager.el` and `claude-code-ide-remote-project.el`. Qualify the exact Session directory through `claude-code-ide-remote-project-rpc-directory` only after existing access checks. Keep disabled access terminal-only without companion connection attempts. Make restoration and reattachment reuse live shells without replacing missing saved shells. Preserve independent Agent attachment when enabled project access fails.
- [X] T018 [US4] Migrate provider-aware view keys throughout `claude-code-ide-remote-project.el`, relevant consumers in `claude-code-ide-manager.el`, and affected fixtures in `claude-code-ide-tests.el`. Preserve the existing host, location-kind, and canonical-location fields, then append the captured provider descriptor. Update explicit targets, native lookup, writer claims, surviving views, cleanup, and Worktree reconciliation together. Do not retain three-field runtime keys or let Dired reuse Magit content.
- [X] T019 [US4] Extend the existing worker and result dispatch in `claude-code-ide-remote-project.el`. Invoke captured Git providers or direct Dired with the requested RPC directory. Create ordinary shells through the Session-layer helper and existing RPC-client PTY policy. Keep shells outside the shared Project-view registry. Preserve worker cancellation, deadlines, client safety checks, and the explicit-target callback contract.
- [X] T020 [P] [US4] Integrate delayed result display and shell adoption in `claude-code-ide-manager.el`. Check Session, attachment, frame epoch, admission, and captured layout ownership before changing windows or shell associations. Display the captured companion side and preserve the user's current focus. Preserve saved remote selection and existing user-dismissal suppression. Let explicit reset clear suppression through the existing mechanism.
- [X] T021 [P] [US4] Complete stale-result retention and provider-aware cleanup in `claude-code-ide-remote-project.el`. Preserve live shells from superseded or undisplayable requests as ordinary terminals. Never adopt them into newer requests or close shared remote connections. Retain native views while any registered owner uses their exact buffer. Preserve existing protections for modified, custom, preexisting, process, and uncertain buffers.
- [X] T022 [US4] Complete remote failure and parity integration in `claude-code-ide-manager.el` and `claude-code-ide-remote-project.el`, with ERT coverage in `claude-code-ide-tests.el`. Cover all six arrangements, exact host/directory, disabled versus failed access, and unavailable support. Exercise superseded requests, approval/attachment changes, dismissal, reset, reattachment, shared native buffers, and focus preservation. Verify that shell preferences and explicit-target behavior remain unchanged, without local substitution or software installation.

**Checkpoint**: Remote behavior matches local behavior except for documented preparation delay and platform prerequisites.
Only T020 and T021 form a parallel pair, after T019 fixes the result contract.
T022 owns their integration and test-file changes.
Validation guide: quickstart sections 8 through 12.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Document actual behavior and verify the complete six-preset feature.
These tasks do not authorize speculative refactors, new telemetry, or unrelated cleanup.

- [X] T023 [P] Update CC Manager, layout, configuration, and remote-view sections in `README.org`. Document all six values, the Magit-left default, old-side removal, temporary Git customization, and explicit shell-reset behavior. Explain saved-layout precedence and surviving ordinary shells.
- [X] T024 [P] Update affected preparation, provider reuse, and lifecycle guidance in `docs/remote.org`. Document captured requests, exact admission, shell preferences, and existing RPC PTY policy. Keep the approved terminology in `CONTEXT.md` unchanged unless implementation reveals an actual terminology change.
- [X] T025 Run `scripts/compile-and-test.sh` and the applicable scenarios in `specs/007-add-layout-presets/quickstart.md`. Reload changed Elisp with `emacsclient` after the gate passes. Verify actual windows, focus, commands, and process identity on available supported Agent/backend combinations. Use only authorized disposable Sessions and already approved remote targets. Report unavailable coverage rather than substituting mocks for live acceptance.
- [X] T026 Record final results and unavailable combinations in `specs/007-add-layout-presets/quickstart.md` and completion state in `specs/007-add-layout-presets/tasks.md`. Compare the result with `specs/007-add-layout-presets/spec.md` and `specs/007-add-layout-presets/plan.md`. Keep any unresolved gate or acceptance failure explicit. Do not claim completion with unresolved failures. Do not commit changes or remove unrelated user work.

Final gate: **927 tests, 919 expected results, 0 unexpected results, 8 skips**.
Focused integration: **26/26 checks**, including all **15 layout-preset checks**.
Native Ghostel checks covered all six arrangements locally and on the approved disposable ramhorn Sessions.
The user excluded EAT and vterm from that acceptance run.
Feature 008 has since removed that backend code.
The acceptance record documents Agent combinations, the later Pi exit, process identities, lifecycle checks, and cleanup.
Changed Elisp was reloaded after the gate passed. No commit was created.

**Checkpoint**: The exact repository gate passes and every available acceptance scenario has recorded evidence.
An unavailable required scenario remains an explicit acceptance gap, not a passed check.
All four stories remain required for final feature delivery.

---

## Design-to-Story Mapping

| Design entity or decision | Owning work | Consumers |
| --- | --- | --- |
| Fixed descriptor and captured request | T002–T003 | US1–US4 |
| Temporary Git callback and direct Dired provider | US1, T004 | US4, T018–T019 |
| Canonical Session identity and runtime shell table | US2, T008–T010 | US3–US4 |
| Saved layout metadata and native recovery | US3, T012–T014 | US4, T017 and T020 |
| Released versus disconnected ownership | US3, T015 | US4, T017 and T022 |
| Provider-aware view keys and shared native ownership | US4, T018 and T021 | Session and explicit-target view requests |
| Remote shell transport and shell preferences | US4, T017–T019 | Git/Dired remain independent from Ghostel |
| Existing gate error and no new dependencies | T001 | All implementation phases and T025 |

| Contract sections | Story coverage |
| --- | --- |
| 1–3: Preference, arrangements, Git callback, old-side removal | US1 and US2, remote parity in US4 |
| 4: Existing manager commands | US1 application/focus, US3 saved layouts/reset, US4 delayed return |
| 5: Companion shell lifecycle | US2 creation/identity, US3 survival/recovery, US4 remote ownership |
| 6: Remote interfaces, admission, publication | T003 signature migration, US4 behavior |
| 7: Failures and recovery | US1 content/windows, US2 startup, US3 restoration, US4 remote access |
| 8: Validation references | Story checkpoints and T025–T026 |

## Requirement and Acceptance Coverage

| Requirement | Tasks | Independent evidence |
| --- | --- | --- |
| FR-001 | T002, T004–T005, T008–T010, T018–T020 | US1/US2 layouts and US4 six-preset parity |
| FR-002 | T002, T005–T007 | One choice, old-side cutover, invalid selection leaves Agent usable |
| FR-003 | T002, T007 | Unconfigured Session opens Magit left |
| FR-004 | T004, T007, T019 | Both Git orientations retain captured custom content |
| FR-005 | T008, T010–T011, T019 | Ordinary shell commands, no extra Agent row, unchanged backend |
| FR-006 | T008, T010–T011, T017, T019 | Exact local/remote directory and wrong-target refusal |
| FR-007 | T006, T012–T014, T016, T020 | Saved arrangement wins, missing/exited return starts no shell |
| FR-008 | T009–T010, T014, T016–T017 | Same-Session reuse and same-directory Session isolation |
| FR-009 | T005–T007, T013, T020, T022 | Sidebar, Agent identity, initial focus, and saved selection |
| FR-010 | T004, T007, T019, T022 | Git-only Dired fallback |
| FR-011 | T008, T011, T019, T022 | Optional support, explicit startup failure, usable Agent |
| FR-012 | T005, T007, T011, T020–T022 | Failed split preserves Agent and any started shell |
| FR-013 | T017–T022 | Approved remote parity with delayed preparation |
| FR-014 | T017, T020, T022 | Disabled access performs no companion work, failed enabled access explains |
| FR-015 | T002–T003, T007, T011, T025 | Shared manager paths across available Agent/backend combinations |
| FR-016 | T004, T007, T018–T019, T022 | Exact Dired directory, no Git callback or Magit dependency |
| FR-017 | T015–T017, T021–T022 | Shell survives Session removal and retains ownership across temporary disconnection |

US1 covers its eight acceptance scenarios and SC-002, SC-003, SC-007, and SC-008.
US2 covers its six acceptance scenarios and SC-004.
US3 covers its eight acceptance scenarios and SC-005.
US4 covers its three acceptance scenarios and the remote portion of SC-001.
Together, the story integrations cover SC-001 and SC-006 across successful and failed operations.

## Dependencies & Execution Order

### Phase Dependencies

```text
T001: execution environment
  |
T002 -> T003: shared request and complete interface migration
  |
US1: T004 -> T005 -> T006 -> T007
  |
US2: (T008 || T009) -> T010 -> T011
  |
US3: T012 -> T013 -> T014 -> T015 -> T016
  |
US4: T017 -> T018 -> T019 -> (T020 || T021) -> T022
  |
Polish: (T023 || T024) -> T025 -> T026
```

### User Story Dependencies

- US1 requires the request resolver and caller migration from the foundation.
- US2 reuses US1's window construction and reset entry points.
- US3 requires US2's ordinary shell and runtime ownership table.
- US4 consumes all three earlier stories' provider, ownership, restoration, and focus contracts.
- Final verification requires all stories, not only the suggested MVP checkpoint.

These dependencies follow the existing shared manager module.
The stories are independently testable after their prerequisites, but they are not independent branches with disjoint source ownership.
Do not mark the whole story set parallel merely because it has separate labels.

### Within Each Story

Complete providers and state before their integration entry points.
Complete both members of a parallel pair before any consumer or validation task.
Maintain mandatory ERT behavior coverage as part of implementation, without adding a separate optional test program.
Run the story's independent acceptance check after its integration task.

### Parallel Opportunities

| Pair | Prerequisite | Disjoint write ownership | Integration owner |
| --- | --- | --- | --- |
| T008 and T009 | T007 complete | Session helpers / manager ownership table | T010, then T011 for ERT |
| T020 and T021 | T019 complete | Manager publication / remote-project retention and cleanup | T022 |
| T023 and T024 | T022 complete | README / remote documentation | T025–T026 |

T003 and T018 are atomic multi-file changes and must remain serial.
All tasks that modify `claude-code-ide-tests.el` remain serial.
Do not run the full suite while another worker modifies any source or test file.

## Parallel Example: User Story 1

No safe independent write pair exists inside this story.
All four tasks modify the shared manager, and the last task integrates its ERT behavior.

```text
Run T004 -> T005 -> T006 -> T007 serially.
Then run the US1 independent acceptance check.
```

## Parallel Example: User Story 2

After T007, dispatch only the two independent implementations:

```text
Worker A: T008, claude-code-ide-session.el only
Worker B: T009, claude-code-ide-manager.el only
Shared contract: exact directory to ordinary shell buffer, Session ID to owned buffer
Both workers: skip build, lint, formatter, and tests
Barrier: both edits complete
Integration owner: T010 -> T011
```

## Parallel Example: User Story 3

No safe independent write pair exists inside this story.
Capture, restoration, reset, and cleanup share manager state and must agree before validation.

```text
Run T012 -> T013 -> T014 -> T015 -> T016 serially.
Then run the US3 independent acceptance check.
```

## Parallel Example: User Story 4

After T019 fixes the remote result variants, dispatch the disjoint publication and retention work:

```text
Worker A: T020, claude-code-ide-manager.el only
Worker B: T021, claude-code-ide-remote-project.el only
Shared contract: captured request and completed result variants from data-model sections 5 and 7
Both workers: preserve existing caller signatures and skip validation
Barrier: both edits complete
Integration owner: T022, including claude-code-ide-tests.el
```

## Implementation Strategy

### MVP First: Internal US1 Demonstration

1. Complete the environment prerequisite and the shared foundation.
2. Complete US1 and verify its four local Git/Dired arrangements.
3. Demonstrate that checkpoint without claiming shell support or complete remote parity.
4. Continue the remaining stories unless the user explicitly approves a scope change.

This MVP is a development checkpoint, not the final requested deliverable.
Do not ship a preference with incomplete shell choices as a finished feature.

### Incremental Delivery

1. Add US2 and verify ordinary shell commands and Session isolation.
2. Add US3 and verify saved work, explicit replacement, and shell survival.
3. Add US4 and verify approved remote parity and stale-result protection.
4. Complete documentation, the full gate, and available live acceptance scenarios.
5. Report any missing required coverage or gate failure before claiming completion.

### Parallel Team Strategy

Assign one owner to each file within the three declared parallel pairs.
Freeze the shared contracts before dispatch and integrate each pair before its consumers start.
Keep the two cross-file migrations and all ERT edits under one integration owner.
Do not create extra abstraction or split tests into new files merely to create more parallel work.

## Notes

All 26 tasks remain unchecked because this command generates the implementation work list only.
The known repository gate error remains unresolved until T001 succeeds.
Do not repeat the unchanged failing gate solely to confirm the recorded error.
No feature acceptance scenario has run during task generation.

## Phase 8: Convergence

Assessment found four remaining gaps after T001–T026 completed.
The findings below describe current behavior, not changes between revisions.
The user excluded EAT and vterm from the native checks recorded here. Feature 008 removed that integration.

- [X] T027 **CRITICAL** Complete delayed remote-view display after navigation per Constitution VI, FR-013, US4/AC1, plan §1E, and T020/T022 (partial).
  Update `claude-code-ide-manager.el` and `claude-code-ide-remote-project.el` for finding F3.
  Reproduce remote A → local B → remote A before initial Project-view preparation completes.
  Make the completed companion appear without another reset or Session switch.
  Preserve the captured provider, side, admission, attachment, suppression, and frame-epoch checks rather than accepting stale results.
  Add a deterministic visible-completion regression in `claude-code-ide-tests.el`.

- [X] T028 Restore non-shell layout recovery per FR-007, plan §1D, and T006/T016 (partial).
  Update `claude-code-ide-manager-switch-to-session` in `claude-code-ide-manager.el` for finding F1.
  Reproduce a native restoration error while returning to a non-shell layout from another Session.
  Rebuild the applicable default layout instead of retaining the previous Session's companion.
  Keep Agent-only recovery and zero automatic shell creation for failed saved-shell restoration.
  Add a regression in `claude-code-ide-tests.el` that checks the displayed companion and preserves the existing shell-recovery checks.

- [X] T029 Preserve saved manager-window selection per FR-007, SC-005, US3/AC1, and T013 (partial).
  Update `claude-code-ide-manager--restore-layout` in `claude-code-ide-manager.el` for finding F2.
  Save a layout with its manager sidebar selected, switch away, and return through ordinary Session navigation.
  Select that saved manager window when it remains valid instead of unconditionally excluding manager buffers.
  Preserve explicit manager-focus requests and the Agent fallback when the saved window is unavailable.
  Add a visible-window selection regression in `claude-code-ide-tests.el`.

- [X] T030 Correct remote companion guidance in `README.org` per plan §1F–G and T023 (partial).
  Address finding F4 in the remote Project-view section around the existing identity, shell transport, and reset descriptions.
  Describe provider-aware view identity instead of unconditional sharing by host and Worktree alone.
  Describe the installed RPC client's existing PTY policy without claiming that every shell uses an RPC PTY.
  Distinguish fresh-worker health checks from reset or mirroring that reuses a live shell without a worker.

### Convergence validation

T027–T030 completed on 2026-09-12.
The final gate passed with **930 tests, 922 expected results, 0 unexpected results, and 8 skips**.
All **18 layout-preset regressions** passed, including the three new red-before-green checks.
Native OMP/Ghostel checks verified delayed ramhorn completion, saved manager focus, and local non-shell recovery.
Changed Elisp was reloaded after the gate passed.
Disposable resources were removed. The acceptance record in `quickstart.md` contains the detailed evidence.
No post-implementation hook registry exists. No commit was created.

## Phase 9: Convergence

Assessment date: 2026-09-12.
The current-code assessment found two partial gaps: one CRITICAL and one HIGH.
The three behavioral fixes from Phase 8 still passed their focused scenarios.
This assessment made no application-code changes and did not repeat native acceptance or the full compile gate.

- [X] T031 **CRITICAL** Reject stale remote Git/Dired publication per Constitution VI, FR-016, plan §1E/R10, and T019–T022 (partial).
  Address finding F5 in `claude-code-ide-remote-project.el` and the corresponding replay path in `claude-code-ide-manager.el`.
  Reproduce a Session directory change while its Git or Dired worker is pending, then complete that worker.
  The current display guard rejects the result, but `--finish-view-success` registers it and assigns it to the Session intent first.
  Ordinary navigation then displays that old view under a new request for the changed Session directory.
  Verify captured request ownership before publication, and prevent stale views from becoming eligible through later replay.
  Preserve T027's valid delayed navigation completion, explicit-target callbacks, and conservative candidate cleanup.
  Add a regression in `claude-code-ide-tests.el` that checks the visible directory after completion and subsequent navigation.

- [X] T032 **HIGH** Preserve local layouts when a Git provider changes windows per FR-001, FR-004, FR-009, SC-001, and T004–T007 (partial).
  Address finding F6 in `claude-code-ide-manager.el`, especially `--open-status-buffer` and `--build-default-layout`.
  The builder creates its content windows before invoking the provider, without isolating the provider's window changes.
  Magit's `magit-display-buffer-same-window-except-diff-v1` replaces the Agent and duplicates the companion.
  Its `magit-display-buffer-fullframe-status-v1` removes the companion window and leaves no visible Agent after recovery.
  Isolate provider window changes while preserving the returned content buffer and existing Dired fallback.
  Preserve the same live Agent, the requested companion side, the manager sidebar, and the invoking action's focus policy.
  Add behavioral regressions in `claude-code-ide-tests.el` for successful providers that replace or delete layout windows.

**Validation**: After T031–T032, run `./scripts/compile-and-test.sh` and the affected live Ghostel scenarios.
Reload the changed Elisp through `emacsclient` after the gate passes.
This verification excluded EAT and vterm, which feature 008 removed. Do not create a commit.

### Phase 9 verification

T031–T032 completed on 2026-09-12.
The final `./scripts/compile-and-test.sh` run passed: **932 tests, 924 expected results, 0 unexpected results, and 8 skips**.
All **20 layout-preset regressions** passed, including both new red-before-green checks.
The stale-directory regression also covers a previously ready view during request replacement.
All **54 existing remote Project-view tests** passed with current ownership metadata in their fixtures.

Native OMP/Ghostel checks used real Magit and RPC access on the approved host `ramhorn`.
Both local Magit orientations preserved the Agent under same-window and full-frame display policies.
Both remote Git and Dired results stayed hidden after their captured directory became stale, including after navigation.
Explicit reset recovered Dired in the current directory.
Valid delayed navigation retained captured Magit-left content and manager focus despite newer preferences.

The user's Emacs loaded the changed production Elisp through `emacsclient` after the final gate passed.
The disposable remote Agent stopped with verified absence.
Both supervised processes exited successfully. The cleanup commands removed the disposable local and remote directories.
The detailed acceptance record is in `quickstart.md`.

Additional T031 checks covered automatic replacement after a ready view's directory changed and recovery while an obsolete request remained pending.
Both extended regressions failed before repair and passed afterward.
Capture now discards window snapshots that contain the obsolete view, including snapshots that would otherwise survive serialization.
Replacement scheduling uses current view ownership and supersedes an obsolete pending request through the existing preparation path.
Real RPC checks verified both transitions beside the same live Ghostel Agent without a manual reset.
The final repeated gate retained **932 tests, 924 expected results, 0 unexpected results, and 8 skips**.
The user's Emacs loaded the final source after that gate.
The final disposable remote Agent stopped with verified absence. Cleanup removed both final verification directories.
