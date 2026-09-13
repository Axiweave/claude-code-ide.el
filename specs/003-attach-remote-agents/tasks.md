---
description: "Implementation tasks for attaching existing remote Agents"
---

# Tasks: Attach Remote Agents

**Input**: Design documents from `specs/003-attach-remote-agents/`.

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/remote-sessions.md`, `contracts/zmx-attach-guard.md`, and `quickstart.md`.

**Tests**: Constitution Principle II requires ERT coverage for new logic. Include focused behavioral regressions in the existing suite.

**Organization**: Keep the specification's story identifiers. Execute P1 stories US1, US2, US3, and US5 before P2 story US4.

**Feature 008 removal record**: EAT and vterm support no longer exists.
The dated Status and T041–T042 entries below record the former rejection path.
Feature 008 deleted that path, its per-Agent override, and its regression.
These historical entries are not current configuration instructions.

**Status**: Implementation, automated verification, and the live guide are complete on stock zmx. The repository gate passed with 655 tests, 646 as expected, nine skips, and no failures. On 2026-09-05 the user rejected the patched zmx; T002–T004 were superseded by T040. On 2026-09-06 a live Ghostel lifecycle on `ramhorn` (stock zmx 0.8.0) passed against the disposable target `cci-omp-repo-bsY2O4`: attach, detach, same-ID reattach, persisted restore with zero requests, canceled Stop, verified Stop, and missing-target reattach. Live checks found and fixed two bugs: blank stock `list --short` output was rejected, and repeated unchanged saves deleted the persisted state file. vterm and Eat are rejected at the remote attach entry (T041). See `quickstart.md` for evidence. On 2026-09-06 the two-host walkthroughs (T020, T036, T039) passed live against `ramhorn` and `vps`.

## Format: `[ID] [P?] [Story] Description`

- `[P]` identifies independent file ownership within the documented execution wave.
- `[US1]` through `[US5]` identify the specification's user stories.
- Setup, foundational, and final tasks have no story label.
- Finish each wave's prerequisites before concurrent edits.
- Run validation only after concurrent writers finish.

## Path Conventions

- Emacs package paths are relative to this repository root.
- Feature document paths start with `specs/003-attach-remote-agents/`.
- Reuse the existing Emacs modules and ERT suite. Do not add a remote framework, dependency, or second manager.

## Shared Implementation Contracts

These contracts let separate file owners work without inventing incompatible interfaces.

1. Add `host` to `claude-code-ide-session`. Keep `host=nil` local.
2. Add `host`, `zmx-name`, and `cli-type` to `claude-code-ide-manager-item`. Reuse `live-p` rather than adding connection state.
3. Keep the Session ID stable through disconnect and reattach. Identify remote targets by `(host, zmx-name)` and projects by `(host, directory)`.
4. Extend existing attach commands with an optional `host` argument. Preserve local calls and use `C-u` for interactive host selection.
5. Extend shared Session creation with remote host and reusable Session ID inputs. Set the host marker before terminal hooks run.
6. Implement `claude-code-ide-zmx--call-remote` with the process-handle return and explicit callback outcome from `contracts/remote-sessions.md`.
7. Use `claude-code-ide-manager--remember-remote-session (session)` to copy a remote Session into a disconnected manager item. This helper must not refresh or perform network requests.
8. Extend `claude-code-ide--cleanup-on-exit` with expected-process ownership and a cleanup disposition after its existing arguments. Preserve existing local call behavior.
9. Let ordinary remote disconnect remember metadata. Let verified-stop teardown release resources without remembering metadata.
10. Extend `claude-code-ide-stop` with an optional exact Session ID. The manager passes its selected ID through this shared command.
11. Use request process identity for pending-operation ownership. Do not add a persistent request registry or global generation counter.

One integration owner owns the lifecycle changes across `claude-code-ide.el` and `claude-code-ide-manager.el`. T022–T026 form one integrated change. T023 includes persistence migration because refresh, restoration, and disconnect must not ship as separate partial changes. US4 independently verifies that shared implementation.

## Phase 1: Setup

**Purpose**: Confirm the installed zmx builds this feature targets.

- [X] T001 Record the stock zmx versions in scope (local 0.7.1, `ramhorn` 0.8.0) in `specs/003-attach-remote-agents/contracts/zmx-attach-guard.md`.

**Checkpoint**: Stock zmx is the only target. No external checkout is part of this feature.

## Phase 2: Foundational — Blocking Prerequisites

**Purpose**: Provide guarded existing-session attachment, shared identity fields, and safe remote process handling.

- [~] T002 Superseded by T040. Existing-only regressions in the private zmx checkout are not part of this feature.
- [~] T003 Superseded by T040. `zmx attach --existing` is not part of this feature.
- [~] T004 Superseded by T040. No external build gate exists.
- [X] T040 Implement the stock attach guard in `claude-code-ide-zmx.el`: `claude-code-ide-zmx--attach-guard`, `claude-code-ide-zmx--attach-args`, and their use in `claude-code-ide-zmx-wrap-command` and `claude-code-ide-zmx--remote-attach-command`. Remove the capability probe from discovery and reattach. Verify `attach NAME false` on a missing target exits nonzero and leaves no session on stock 0.7.1 and 0.8.0.
- [X] T005 [P] Add the Session host slot and host-aware project identity helper in `claude-code-ide.el`. Preserve local directory keys. Treat remote directories as metadata without filesystem normalization.
- [X] T006 [P] Add remote target slots to `claude-code-ide-manager-item` in `claude-code-ide-manager.el`. Preserve existing constructors and presentation fields. Leave the complete persistence and refresh cutover to T023.
- [X] T007 [P] Implement `claude-code-ide-remote-hosts`, validation, quoting, and `claude-code-ide-zmx--call-remote` in `claude-code-ide-zmx.el`. Use asynchronous pipes, the specified SSH options, separate output streams, and a thirty-second deadline. Complete callbacks once and cancel only owned processes.
- [X] T008 Migrate every attach-only caller of `claude-code-ide-zmx-wrap-command` in `claude-code-ide-zmx.el` and `claude-code-ide.el` to the guarded arguments. Preserve command-bearing local creation. Add wrapper, quoting, timeout, and callback-ownership regressions in `claude-code-ide-tests.el`.

**Validation details**: T007 must reject unconfigured destinations and unsupported names before dispatch. Apply the exact validation rules in `data-model.md`. Quote valid punctuation rather than replaying remote command text. Unset `ZMX_SESSION` and `ZMX_SESSION_PREFIX` for remote zmx operations. Preserve the socket namespace environment.

T008 must test unsupported help output without executing the new option. Local reattach checks the local executable. Remote reattach checks the remote executable and must not require local zmx.

**Checkpoint**: The stock attach guard passes its regressions. The Emacs changes preserve local creation and do not enable an unsafe remote attach path.

## Phase 3: User Story 1 — Discover and Attach an Existing Remote Agent (Priority: P1)

**Goal**: Discover and attach a selected configured host's existing Agent through the shared terminal backend.

**Independent Test**: Start a disposable remote Agent before validation. Discover it, attach through editor controls, submit input, and observe output without restarting it. Complete discovery through usable attachment within 60 seconds.

### Tests for User Story 1

- [X] T009 [US1] Add remote discovery and attachment regressions in `claude-code-ide-tests.el`. Cover malformed versus empty responses, zmx 0.8 `cwd=` rows, failed hosts, metadata omissions, unknown Agents, and disappearing targets. Assert no creation or local integration side effects.

### Implementation for User Story 1

- [X] T010 [P] [US1] Implement detailed discovery and terminal command construction in `claude-code-ide-zmx.el`. Use `ssh -T -n` for control and explicit `ssh -t` for attachment.
- [X] T011 [US1] Extend `claude-code-ide-attach`, `claude-code-ide-attach-all`, and `claude-code-ide-attach-select` in `claude-code-ide.el`. Preserve local behavior and existing pickers. Carry host metadata through asynchronous completion and marked selection. Name bulk skips and permit manual Agent identification and remote-directory text entry.
- [X] T012 [US1] Extend shared Session creation and `claude-code-ide--attach-zmx-entry` in `claude-code-ide.el`. Reuse terminal setup with the SSH command and a valid local working directory. Bypass Agent builders, executable checks, MCP startup, launcher configuration, and local zmx wrapping.
- [X] T013 [US1] Exclude remote Sessions from local PID queries and zmx title writes in `claude-code-ide.el`. Make `claude-code-ide--session-buffer-for-agent` reject remote Sessions through both zmx-name and buffer-name matches. Update affected callers in `claude-code-ide-mcp-sse-server.el`. Preserve local-only OSC presentation and shared output observation.
- [X] T014 [P] [US1] Guard remote filesystem and project actions in `claude-code-ide-manager.el`. Use terminal-only first-switch and reset behavior. Reject remote project-open and launch actions before local Git, Magit, Dired, TRAMP, or Treemacs work.
- [X] T015 [US1] Run focused US1 regressions and its terminal walkthrough from `specs/003-attach-remote-agents/quickstart.md`. Record attachment timing, input/output, and failure messages with Ghostel. Confirm remote attachment without local zmx or an Agent executable. Ghostel attach, detach, and missing-target failure on `ramhorn` passed on 2026-09-06 in a batch Emacs. The user confirmed interactive input and output through `C-u M-x claude-code-ide-attach` in a live Emacs on the same day. vterm and Eat were out of scope (feature 008 has since removed them).

**Acceptance details**: Test an empty host, unsupported zmx, an unreachable host, missing metadata, and unknown Agent commands. Distinguish a candidate's own error from malformed protocol output. Verify that bulk attach names skipped entries. Do not turn metadata into launch arguments. Unsupported terminal behavior requires an explicit message at use time.

**Checkpoint**: US1 supplies the smallest useful demonstration. Do not release partial manager lifecycle changes or omit the remaining requested stories.

## Phase 4: User Story 2 — Work Across Hosts in the Existing Manager (Priority: P1)

**Goal**: Keep local and remote targets distinct while retaining the existing manager and presentation controls.

**Independent Test**: Attach one local Agent and Agents on two hosts with identical project and zmx names. Select and rename each target. Confirm that only the selected terminal receives input.

### Tests for User Story 2

- [X] T016 [US2] Add host-collision and manager-isolation regressions in `claude-code-ide-tests.el`. Cover duplicate attachment, rename, ordering, local scope exclusion, directory lookup, and unavailable-host isolation.

### Implementation for User Story 2

- [X] T017 [P] [US2] Apply host-aware target and project lookup in `claude-code-ide.el`. Update directory matching, related-session ordering, and `--zmx-live-names`. Reuse connected or pending targets by `(host, zmx-name)` without merging hosts.
- [X] T018 [P] [US2] Add host-qualified labels and global-only remote scope membership in `claude-code-ide-manager.el`. Keep `[HOST] PROJECT` visible after rename. Preserve local scope behavior without remote filesystem queries.
- [X] T019 [US2] Preserve pinning, ordering, selection, and terminal-only layout behavior in `claude-code-ide-manager.el`. Bind restored terminal windows to the current attached buffer. Never treat stale buffer names as live targets.
- [X] T020 [US2] Run the three-host collision walkthrough from `specs/003-attach-remote-agents/quickstart.md`. Record selection, input routing, rename, and one-host failure results. Confirm other hosts and local Sessions remain usable. Live 2026-09-06 on the user's Emacs with `ramhorn` and `vps` (zmx 0.8.1, omp built from the fork): two Agents named `repo` gave distinct IDs and labels `[ramhorn] repo` and `[vps] repo`; renames landed only on the intended row; both processes stayed live. One-host failure is covered by ERT and the earlier unreachable-host check.

**Checkpoint**: Host identity controls lookup and presentation. US5 later verifies exact Stop routing against the same collision fixture.

## Phase 5: User Story 3 — Distinguish Output Silence from Disconnection (Priority: P1)

**Goal**: Retain a disconnected target without claiming Agent completion, then reattach only on an explicit request.

**Independent Test**: Observe genuine output and output idle, then end the SSH client without stopping its Agent. Refresh and select the retained row without network traffic. Explicitly reattach the same row and Session ID.

### Tests for User Story 3

- [X] T021 [US3] Add disconnect and reattach regressions in `claude-code-ide-tests.el`. Cover first-attach failure, refresh, disabled persistence, stale sentinels, old buffer hooks, duplicate requests, and removed hosts. Distinguish Ghostel redraws from genuine output.

### Implementation for User Story 3

- [X] T022 [P] [US3] Extend cleanup ownership and disposition handling in `claude-code-ide.el`. Remember owned disconnects before unregistering live Sessions. Clear idle timers and activity, then release only captured resources. Ignore missing or changed owners and preserve local cleanup behavior.
- [X] T023 [P] [US3] Integrate remembered-item lifecycle and version 3 persistence in `claude-code-ide-manager.el`. Implement the shared remember helper, serialization, restoration, refresh merging, and `session-ended` behavior together. Preserve version 1/2 readers, presentation, and disconnected selection without network requests.
- [X] T024 [US3] Implement explicit same-ID reattach in `claude-code-ide.el` and `claude-code-ide-manager.el`. Materialize selected targets before attachment and retain failed attempts. Revalidate configured hosts, deduplicate pending requests, and never replace missing remote targets.
- [X] T025 [US3] Add `claude-code-ide-manager-reattach-at-point` on `c` in `claude-code-ide-manager.el` and its entry in `claude-code-ide-transient.el`. Keep ordinary selection passive. Show explicit disconnected status and corrective messages for removed hosts.
- [X] T026 [US3] Run focused lifecycle regressions and the disconnect walkthrough from `specs/003-attach-remote-agents/quickstart.md`. Verify stable identity, cleared activity, passive refresh, and successful explicit reattach. Confirm first-attach and missing-target failures retain one disconnected row. Live on `ramhorn` 2026-09-06: detach kept the row, refresh made zero requests, explicit reattach reused the Session ID, and the missing-target reattach retained the row with no remote session left.

**Atomic lifecycle boundary**: T022 and T023 share the fixed remember-helper contract. The integration owner must integrate T022–T026 before treating this lifecycle change as complete. T023 supplies US4's shared persistence implementation, not a separate migration scaffold.

**Persistence details**: Save changed state before refresh can reload it. Let current live records override disconnected snapshots. Restore remote items with `live-p=nil` and clear dead active-terminal references. Validate saved metadata without requiring current host membership for row visibility. Disabled persistence must preserve current in-memory rows without restoring them after restart.

**Checkpoint**: A quiet connection remains connected. An ended connection becomes a retained disconnected row. Neither state proves Agent completion.

## Phase 6: User Story 5 — Detach or Stop with Clear Consequences (Priority: P1)

**Goal**: Detach only the local client, or stop the exact remote target after explicit confirmation and verified remote success.

**Independent Test**: Attach two clients to one disposable Agent. Close one terminal, cancel Stop, then confirm Stop for the named host and target. Check the surviving client after each action.

### Tests for User Story 5

- [X] T027 [US5] Add detach and Stop regressions in `claude-code-ide-tests.el`. Cover cancellation, host collisions, misleading success, timeout, lost verification, and duplicate requests. Exercise both callback orders, subsequent refresh, and late callbacks against newer attachments.

### Implementation for User Story 5

- [X] T028 [P] [US5] Implement verified remote Stop operations in `claude-code-ide-zmx.el`. Send one exact kill without force and require the exact success response. Verify absence once with `zmx list --short`. Never retry a kill or report ambiguous success.
- [X] T029 [US5] Route `claude-code-ide-stop` through exact Session identity in `claude-code-ide.el`. Confirm host, zmx name, and impact on all clients before dispatch. Revalidate configuration and retain ownership throughout verification. Reject reattach while Stop owns the target.
- [X] T030 [US5] Implement verified Stop finalization in `claude-code-ide.el` and `claude-code-ide-manager.el`. Invalidate captured live ownership before resource teardown. Remove remembered rows, layouts, and references afterward, then save before refresh. Prevent stale callbacks from restoring or removing targets.
- [X] T031 [P] [US5] Add `claude-code-ide-manager-stop-at-point` on `K` in `claude-code-ide-manager.el` and its entry in `claude-code-ide-transient.el`. Pass the selected Session ID to shared Stop. Preserve existing detach keys and `R` layout reset.
- [X] T032 [US5] Run the two-client Stop walkthrough from `specs/003-attach-remote-agents/quickstart.md`. Record detach survival, canceled-request counts, exact-target effects, and unconfirmed outcomes. Run both callback-order regressions and refresh after verified completion. Live on `ramhorn` 2026-09-06: detach left the other client (`clients=1`, same PID), cancel sent zero requests, confirmed Stop sent exactly `kill` then `list --short`, removed the Session and row in 1.05 s, and left `cci-omp-saga-sdk-1lEr7U` untouched.

**Required ordering**: A sentinel-first completion may temporarily retain a disconnected row. Verified Stop must remove that row even without a live record. A verification-first completion removes live ownership before releasing resources. Later sentinels must then do nothing. A stale Stop request cannot finalize a newer attachment.

**Checkpoint**: Closing a buffer or Emacs never sends remote Stop. Only verified Stop removes the remembered target.

## Phase 7: User Story 4 — Return After Restart or Change of Computer (Priority: P2)

**Goal**: Restore local history without network requests and permit independent attachment from another Emacs.

**Shared implementation**: T023 provides persistence migration and restoration. T024 provides same-ID reattach. Do not implement a second history store or a later competing restoration path.

**Independent Test**: Restart Emacs with persistence enabled and inspect disconnected rows before any explicit connection. Repeat with persistence disabled. Discover the same Agent from a second Emacs without shared history.

### Tests for User Story 4

- [X] T033 [US4] Add restart and migration regressions in `claude-code-ide-tests.el`. Cover version 1/2 local state, version 3 remote state, invalid metadata, removed hosts, and saved presentation. Assert zero startup requests and no remote restoration when persistence is disabled.

### Integration and Validation for User Story 4

- [X] T034 [US4] Document remote persistence and independent-computer behavior in `README.org`. Explain passive disconnected restoration, explicit reattach, disabled persistence, removed hosts, and independent histories.
- [X] T035 [US4] Run restart validation from `specs/003-attach-remote-agents/quickstart.md`. Verify saved labels, pinning, order, selection, and layout behavior with zero implicit requests. Repeat with persistence disabled and with a removed host. Live on `ramhorn` 2026-09-06: a fresh Emacs restored the remembered row disconnected with zero requests and reattached on the same ID. Persistence-disabled and removed-host cases are covered by ERT. This run found that repeated unchanged saves deleted the state file; fixed with a fixed empty persist default.
- [X] T036 [US4] Run the second-Emacs walkthrough from `specs/003-attach-remote-agents/quickstart.md`. Discover and attach the same Agent without shared history. Verify continued work and the first client's survival. Live 2026-09-06: a second Emacs with an empty persist directory restored zero rows, discovered `vps`, attached (clients 2 to 3) with its own label, and detached (back to 2); the first Emacs kept its process, buffer, and custom name.

**Checkpoint**: Remote history remains local to each Emacs. Restored rows do not claim a live connection or authorize an unconfigured host.

## Phase 8: Polish and Cross-Cutting Verification

**Purpose**: Document the completed behavior and prove the full feature without expanding its scope.

- [X] T037 Document configuration, commands, stock zmx behavior, backend limits, and troubleshooting in `README.org`. Distinguish local creation from guarded reattach. Explain detach versus Stop and the deferred remote-editor and text-transfer scope.
- [X] T038 Run `scripts/compile-and-test.sh` after all source edits finish. Resolve affected compile and ERT failures. Record exact results in `specs/003-attach-remote-agents/quickstart.md` without claiming unavailable backends passed.
- [X] T039 Complete all five workflows and SC-001–SC-010 checks in `specs/003-attach-remote-agents/quickstart.md`. Record timing, backend coverage, no-creation evidence, and zero implicit requests. Confirm no separate-terminal commands were needed after prerequisite setup. Live 2026-09-06: all five workflows passed across `ramhorn` and `vps`. Workflow 3 on `vps`: connection loss left a disconnected row that kept its name and host, and explicit reattach reused the ID. Workflow 5 on `vps`: canceled Stop changed nothing; confirmed Stop removed the row and the zmx session. Only editor commands were used after prerequisite setup.

**Delivery gate**: All five stories, the full repository check, and the live guide must pass. An unavailable host remains a named blocker, not permission for an unsafe fallback or a reduced feature.

## Dependencies and Execution Order

### Phase Dependencies

```text
T001 → T002 → T003 → T004
                      ↓
                 T005 / T006 / T007
                      ↓
                     T008
                      ↓
                     US1
                    /   \
                  US2   US3
                       /   \
                     US5   US4
                       \   /
                 Final verification
```

Final verification also depends on US1 and US2. The numbered phases prioritize P1 work before P2 work.

### User Story Dependencies

| Story | Required completed work | Independent acceptance |
|-------|-------------------------|------------------------|
| US1 | Setup and foundational tasks | Discovery, interactive attach, no creation, no local integration |
| US2 | US1 and shared host identity | Three-host collision and failure-isolation walkthrough |
| US3 | US1 and manager item fields | Output idle, disconnect, passive refresh, same-ID reattach |
| US5 | US3 lifecycle and US1 transport | Two-client detach, exact confirmed Stop, both callback orders |
| US4 | US3's integrated persistence and reattach | Restart without network traffic, disabled persistence, second Emacs |

US2 and US3 have no required information exchange beyond the shared contracts. Their files overlap, so do not assign concurrent unrestricted edits. US5 and US4 share the same constraint.

### Within Each Story

1. Read the named design sections and existing callers before editing.
2. Use available language-server references before changing exported symbols.
3. Write the story's behavior tests before implementation.
4. For new behavior, verify the relevant tests fail before the corresponding implementation.
5. Finish each documented parallel wave before running validation.
6. Integrate shared-file changes through one owner.
7. Run the story's focused regressions and independent walkthrough.
8. Preserve earlier story behavior when later changes touch shared functions.

US4 tests validate implementation shared with US3. Existing correct behavior need not fail artificially. Do not rerun full project checks during parallel edits. Run the full Emacs verification gate at T038.

## Parallel Examples

Only the listed implementation waves authorize parallel file ownership. Test tasks precede their story's implementation and share one test file.

### Foundation

After T004, run T005 (`claude-code-ide.el`), T006 (`claude-code-ide-manager.el`), and T007 (`claude-code-ide-zmx.el`) together. T008 waits for all three.

### User Story 1

After T009, run T010 (`claude-code-ide-zmx.el`) and T014 (`claude-code-ide-manager.el`) together. T011–T013 share core source ownership and remain serial. T011 and T012 require T010's completed remote command interface. T015 waits for every US1 implementation task.

### User Story 2

After T016, run T017 (`claude-code-ide.el`) and T018 (`claude-code-ide-manager.el`) together. Both use T005's completed project identity helper. T019 follows T018. T020 waits for both owners.

### User Story 3

After T021, run T022 (`claude-code-ide.el`) and T023 (`claude-code-ide-manager.el`) together under the shared remember-helper contract. The integration owner then completes T024–T026 serially. Do not validate or ship either half alone.

### User Story 5

After T027, run T028 (`claude-code-ide-zmx.el`) and T031 (`claude-code-ide-manager.el`, `claude-code-ide-transient.el`) together. T031 uses the fixed `claude-code-ide-stop` optional-ID contract. T029 follows T028. T030 waits for both core and manager writers. T032 follows integration.

### User Story 4

T033–T036 remain sequential. They validate shared lifecycle code and use the same acceptance guide. A separate implementation lane would duplicate completed code or conflict with shared-file ownership.

## Requirement Coverage

| Requirements | Owning tasks |
|--------------|--------------|
| FR-001, EC-02: no persistent creation and discovery race | T040, T008–T010, T012, T024 |
| FR-002, FR-022, EC-06: explicit configured hosts, no implicit requests | T007, T011, T023–T026, T029, T033–T035 |
| FR-003: individual, bulk, and duplicate attachment | T011–T012, T017, T024 |
| FR-004: explicit interactive PTY | T010, T012, T015 |
| FR-005: no local editor integration | T009, T012–T013, T015 |
| FR-006, FR-007, EC-08: Agent identification and project metadata | T009, T011–T012 |
| FR-008, FR-009, SC-001, SC-002: labels and host identity | T005–T006, T016–T020, T027, T029–T032 |
| FR-010, EC-05: output observation versus connection state | T013, T021–T022, T025–T026 |
| FR-011–FR-013, SC-003: retention and explicit reattach | T021–T026 |
| FR-014, FR-015, SC-004: persistence and local history | T023, T033–T035 |
| FR-016: independent clients | T003–T004, T036 |
| FR-017, SC-005: detach and cancellation | T022, T027, T029, T032 |
| FR-018, FR-019, SC-006: exact confirmed Stop | T027–T032 |
| FR-020, EC-01, SC-008: actionable isolated failures | T007, T009–T011, T016, T020, T028–T029 |
| FR-021, EC-04: backend support or explicit failure | T012, T015, T037, T039 |
| FR-023, EC-07: safe names and quoting | T007–T010, T023–T024, T028–T029 |
| EC-03: remote paths remain metadata | T005, T011–T014, T016–T019 |
| SC-007, SC-009, SC-010: editor-only workflows and timing | T015, T020, T026, T032, T035–T039 |

## Implementation Strategy

### MVP First

Complete T001–T015 for the first US1 demonstration on stock zmx. The MVP is a validation milestone, not a reduced final deliverable. Complete all remaining stories before feature delivery.

### Incremental Integration

1. Complete the external zmx gate before remote attachment integration.
2. Prove US1's discovery and terminal interaction.
3. Add US2's host-isolated manager behavior.
4. Integrate US3's complete remembered lifecycle and persistence cutover.
5. Add US5's exact confirmed Stop.
6. Independently verify US4's restart and second-computer behavior.
7. Complete documentation and the final verification gates.

### Parallel Team Strategy

Keep one integration owner for shared Session and manager lifecycle code. Use only the file-separated waves above. Each concurrent assignment must skip formatters, linters, builds, and tests. The integration owner runs validation after writers finish. Do not assign the shared ERT file to multiple writers simultaneously.

## Notes

- Do not add remote Agent launch, automatic reconnect, TRAMP integration, host provisioning, or history synchronization.
- Keep user-owned Agent configuration authoritative.
- Keep existing terminal input and output-idle algorithms unless a verified defect requires a change.
- Do not add a guessed minimum zmx version or a plain-attach fallback.
- Do not commit unless the user requests it.

## Phase 9: Convergence

- [X] T041 Reject non-Ghostel terminal backends at the remote attach entry (`claude-code-ide--create-remote-session` in `claude-code-ide.el`) with a `user-error` naming the backend and the Ghostel requirement, before any terminal or SSH process starts; remove the vterm and Eat exit-hook branches from that remote path; add one ERT regression in `claude-code-ide-tests.el` that a vterm or eat backend signals the error and creates no process or buffer, per FR-021 / EC-04 (contradicts). Done 2026-09-06: `claude-code-ide--create-remote-session` signals `user-error` naming the backend before materializing a row; the vterm and Eat exit-hook branches are gone; `claude-code-ide-test-remote-attach-rejects-non-ghostel-backend` fails on the prior code and passes now. Gate: 655 tests, 646 as expected, 9 skipped.

## Phase 10: Convergence

- [X] T042 Delete the stale CAPABILITY sentence from the docstring of `claude-code-ide--create-remote-session` in `claude-code-ide.el` (lines 2069-2072): the signature has no CAPABILITY parameter and no `zmx help` probe exists, per T040 / plan Phase 1 §1 (partial). Done 2026-09-06: sentence removed; the regression `claude-code-ide-test-remote-attach-rejects-non-ghostel-backend` also binds `claude-code-ide-cli-terminal-backends` to nil so a per-CLI override cannot mask the case. Gate after these edits: 655 tests, 646 as expected, 0 unexpected, 9 skipped, byte-compile clean.

## Phase 11: Convergence

- [X] T043 Align the verification records with the current result: replace the 654/645 count and the "remain blocked" sentence in `tasks.md` line 15 Status, change `contracts/remote-sessions.md` line 3 to state live acceptance passed on 2026-09-06 per `quickstart.md`, and rename the `quickstart.md` heading "Live Acceptance Blocker" to "Live Acceptance Result", per plan: Verification Strategy / T038 (partial). Done 2026-09-06.
- [X] T044 Record the repository gate result on the T042 line in `tasks.md` (gate ran 2026-09-06 after the T042 edits: 655 tests, 646 as expected, 0 unexpected, 9 skipped, byte-compile clean), per T038 / Constitution II (partial). Done 2026-09-06.
