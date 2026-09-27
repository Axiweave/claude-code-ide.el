---
description: "Implementation tasks for Remote Image Paste"
---

# Tasks: Remote Image Paste

**Input**: Design documents in `specs/014-remote-image-paste/`.
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, and `quickstart.md`.
**Governance**: `.specify/memory/constitution.md` version 2.0.0.
**Tests**: Required by FR-013, FR-014, SC-004, the interface contract, and constitution Principle II.
**Organization**: Setup, shared prerequisites, three user stories in priority order, then final verification and documentation.

**Execution status (2026-09-27 UTC)**: The implementation, automated gates, and private-candidate transport acceptance passed.
T001–T026, T005R, T028–T037, and T039–T045 are complete.
The task list has no open tasks. Installation still needs separate approval.
Three authorized OMP vision turns reported the correct image counts, colors, bar counts, and dimensions.
The current per-gesture record includes each Session, attachment number, and matching expected/received SHA-256.
Stock zmx dropped input during the concurrent large-image check. The approved backpressure correction closed that failure.
The private candidate delivered ten first-gesture images with two clients attached to each Session.
Both 5245667-byte images arrived unchanged, in 1667 ms and 1727 ms.
The current package gate passed 961 tests with 14 skips. Ghostel ERT passed 1200 checks with 8 skips.
OMP passed 442 focused checks, both type checks, and scoped lint/format checks in Phase 9.
Phase 9 repeated the package and OMP gates without live acceptance. Ghostel's latest full gate remains the Phase 8 result.
The earlier zmx run passed 95 unit checks and nine CLI cases.
The user removed SC-007 and its related tasks, T027 and T038.
The approved T039 cleanup removed only the obsolete trust entry.
See the [private backpressure acceptance record](quickstart.md#private-zmx-backpressure-correction-2026-09-27-utc) for exact digests and verification.
See the [Phase 8 checks](quickstart.md#phase-8-implementation-checks) for T042, T043, and the Ghostel gate results.
See the [Phase 9 checks](quickstart.md#phase-9-implementation-checks) for T044, T045, and the current package and OMP results.
See the [T039 cleanup record](quickstart.md#t039-approved-trust-cleanup) for configuration preservation checks.

## Format: `[ID] [P?] [Story] Description`

- Each task has a checkbox, a sequential ID, and exact file paths.
- `[P]` identifies tasks that can run together after their stated prerequisites finish.
- Story tasks use `[US1]`, `[US2]`, or `[US3]`.
- Tasks remain unchecked until implementation and their required evidence exist.

## Path Conventions

- Unprefixed paths start at `/Users/fuyu0425/.spacemacs.d-30/site-lisp/claude-code-ide.el`.
- `../ghostel/` is `/Users/fuyu0425/.spacemacs.d-30/site-lisp/ghostel`.
- The existing OMP client is `/Users/fuyu0425/agents/oh-my-pi/packages/coding-agent/src/utils/enhanced-paste.ts`.
- Paths under `packages/` in T005R start at `/Users/fuyu0425/agents/oh-my-pi`.
- Record implementation checks in the existing `specs/014-remote-image-paste/quickstart.md`.
- Keep protocol parsing and grants in libghostty. Keep the package route in `claude-code-ide-session.el`.
- Add no stored model, configuration option, required dependency, or image file transfer.
- The user approved one multiplexer exception: lossless zmx input backpressure, regression checks, and private candidates. Installation needs separate approval.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the actual source state and resolve conflicting design statements before implementation.

- [X] T001 Record current toolchains, Ghostel pin, loaded module, and OMP client support in `specs/014-remote-image-paste/research.md`. Inspect `../ghostel/build.zig.zon` and `/Users/fuyu0425/agents/oh-my-pi/packages/coding-agent/src/utils/enhanced-paste.ts`. Use `~/bin/emacsclient --eval` for live module information.
- [X] T002 Reconcile route and verification contradictions in `specs/014-remote-image-paste/spec.md`, `specs/014-remote-image-paste/contracts/ghostel-package-interface.md`, `specs/014-remote-image-paste/contracts/osc-5522-exchange.md`, and `specs/014-remote-image-paste/quickstart.md`. Preserve unchanged behavior for unsupported CLIs without a new message. Distinguish a completed paste attempt from an acknowledged attachment. Require byte comparison, not dimensions alone, to prove unchanged bytes. Document empty-clipboard handling without changing valid text paste.

**Checkpoint**: The interface contract has one outcome for each route. No task treats the existing local `C-v` path as remote support.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Prove the native API, clipboard byte access, and remote control conditions that all stories need.

- [X] T003 Migrate the candidate ghostty pin in `../ghostel/build.zig.zon` and its affected native APIs. Update `../ghostel/src/GhostelTerm.zig`, `../ghostel/src/NativeProcess.zig`, `../ghostel/src/comint_filter.zig`, and `../ghostel/src/kitty_graphics.zig` for the verified upstream changes. Adapt `../ghostel/build.zig` only as required. Build with Zig 0.16.0 and verify `TerminalStream.Handler.paste`, `Paste`, `clipboard.Read`, and `sys.randomSecure`. Record commands and results in `specs/014-remote-image-paste/research.md`. The first attempt failed, and the original pin was restored.
- [X] T004 Prove byte-level macOS clipboard access for the selection targets used by `../ghostel/lisp/ghostel.el`. Use an approved disposable image and `~/bin/emacsclient --eval`. Record byte type, MIME mapping, and exact-byte comparison in `specs/014-remote-image-paste/research.md`. Do not use a file-based transfer or transcode the payload.
- [X] T005 Resolve leadership preflight, restored mode 5522, and transfer-failure detection in `specs/014-remote-image-paste/research.md` and `specs/014-remote-image-paste/plan.md`. Trace `claude-code-ide-zmx.el`, `../ghostel/src/GhostelTerm.zig`, and the existing OMP client. Identify observable sources for leadership, completion, disconnect, and timeout. Verify reattachment replays mode 5522 rather than assuming output forwarding proves it. Update `specs/014-remote-image-paste/contracts/ghostel-package-interface.md` and `specs/014-remote-image-paste/contracts/osc-5522-exchange.md` with the verified interfaces and ownership.
- [X] T005R Implement and verify the approved OMP receiver prerequisite in `packages/coding-agent/src/utils/enhanced-paste.ts`, its InputController adapter, and the required TUI lifecycle points. Add paired-MIME integrity checks, request identity, bounded expiry, busy refusal, and the guarded editor commit. Preserve local and legacy paste routes. Run focused tests and an actual receiver-to-editor smoke check before closing T005.

**Blocking rules**:

- Finish T003 before native implementation.
- Finish T004 before implementing the clipboard reader.
- Finish T005 before any story implementation.
- T005R is the approved receiver scope extension. Complete it before closing T005 or starting the original story tasks.
- Do not infer leadership from buffer focus or process liveness.
- Do not send probe input that claims leadership or changes the Agent.
- If stock zmx cannot expose a required condition, record the evidence and request a design decision.
- Do not silently replace the requirement, add zmx changes, or claim completion when a prerequisite fails.

**Checkpoint**: All three prerequisites have observed evidence. No implementation depends on an invented capability or failure signal.

## Phase 3: User Story 1 - Paste an image into a remote Agent (Priority: P1)

**Goal**: Deliver a local clipboard image to remote OMP through OSC 5522 while preserving existing local and text paste behavior.

**Independent Test**: Paste a known image into a supported remote OMP Session five times. Confirm five attachments and Agent acknowledgement.
Compare local attachments, dimensions, content, and received bytes. Verify text paste and unsupported CLI behavior separately.

### Tests for User Story 1

- [X] T006 [P] [US1] Add native round-trip coverage in `../ghostel/src/GhostelTerm.zig` and `../ghostel/test/ghostel-osc-test.el`. Cover mode precedence, MIME choice, BEL/ST termination, and exact byte reconstruction across chunk boundaries. Preserve OSC 52 behavior.
- [X] T007 [P] [US1] Add route and preservation cases in `claude-code-ide-tests.el`. Cover local image CLIs, remote OMP, remote unsupported CLIs, text-only clipboards, and unknown CLI types. Prove remote success sends no raw `C-v`. Preserve existing keybinding precedence and text behavior.

### Implementation for User Story 1

- [X] T008 [US1] Implement the native paste exchange in `../ghostel/src/GhostelTerm.zig`, `../ghostel/src/handler.zig`, and `../ghostel/src/module.zig`. Use libghostty paste, secure randomness, and a synchronous clipboard-read callback after resolving the Emacs-thread handoff. Keep grants terminal-local and deny ungranted reads from the first implementation. Preserve OSC 52 handlers.
- [X] T009 [US1] Add `ghostel-paste-events-supported-p` and `ghostel-paste-clipboard` in `../ghostel/lisp/ghostel.el`. Advertise available MIME types and read bytes only for an authorized request. Keep one coherent payload per reply. Preserve existing paste commands, send commands, and keybindings.
- [X] T010 [US1] Synchronize capability release versions in `../ghostel/src/version.zig`, `../ghostel/lisp/ghostel-module-install.el`, `../ghostel/lisp/ghostel.el`, and `../ghostel/build.zig.zon`. Keep the capability predicate safe when native support is absent or older.
- [X] T011 [US1] Add the remote OMP route in `claude-code-ide-session.el` after the Ghostel interface works. Reuse the Session identity, host, CLI type, image predicate, and optional-dependency patterns. Keep the OSC 5522 CLI set private. Preserve local `C-v`, other CLI routes, and text paste. Refuse missing capability before sending bytes.
- [X] T012 [US1] Apply the verified reattachment requirements from T005 in `../ghostel/src/GhostelTerm.zig` and `../ghostel/lisp/ghostel.el`. Preserve terminal mode state through the supported attachment path without synthesizing Agent input. Record evidence instead of adding code when the existing path already satisfies the contract.
- [X] T013 [US1] Extend ordering and identity coverage in `claude-code-ide-tests.el` and `../ghostel/test/ghostel-osc-test.el`. Cover alternating terminals, repeated distinct images, clipboard changes before the granted read, and reattached Sessions. Verify exact destinations and payload order.
- [X] T014 [US1] Run the focused package paste cases and Ghostel native, Zig, and Elisp checks through `scripts/compile-and-test.sh` guidance and `../ghostel/Makefile`. Record commands and observed results in `specs/014-remote-image-paste/quickstart.md`. Run checks after integrated edits, not during concurrent edits.
- [X] T015 [US1] Exercise the real local and remote paths in `specs/014-remote-image-paste/quickstart.md`. Verify five first-gesture successes, local Claude/Codex/OMP parity, text variants, multiple MIME types, and exact bytes. Verify a usable image of at least 5 MB within 10 seconds. Verify ten alternating gestures deliver five images per Session, including reattachment and separate Emacs clients.

**Checkpoint**: The supported route works through real Emacs, Ghostel, SSH, zmx, and OMP. Mocks alone cannot complete US1.

## Phase 4: User Story 2 - Receive the image without a workspace side effect (Priority: P1)

**Goal**: Transfer only authorized clipboard bytes through the existing terminal connection, without transfer files or lifecycle changes.

**Independent Test**: Compare remote file activity and working directory before and after a controlled paste. Verify no transfer-created image file exists.
Verify zero reads without a gesture and rejection of replayed or cross-terminal grants.

### Tests for User Story 2

- [X] T016 [P] [US2] Add authorization invariants in `../ghostel/src/GhostelTerm.zig` and `../ghostel/test/ghostel-osc-test.el`. Cover missing, unknown, spent, expired, and cross-terminal grants. Cover unadvertised MIME types and other clipboard selections. Assert zero payload reads without a valid gesture and grant.
- [X] T017 [P] [US2] Extend Session boundary coverage in `claude-code-ide-tests.el`. Prove paste preserves the exact host, directory, process, and attachment identity. Reuse existing host-approval and lifecycle cases without changing their behavior. Assert no file-path substitute reaches Agent input.

### Implementation and Verification for User Story 2

- [X] T018 [US2] Complete grant and reply lifetime enforcement in `../ghostel/src/GhostelTerm.zig`, `../ghostel/src/handler.zig`, and `../ghostel/lisp/ghostel.el`. Reuse libghostty grant checks rather than creating another authorization store. Discard grant and reply state on completion, refusal, terminal destruction, or failure. Close any gaps found by T016 without changing image bytes.
- [X] T019 [US2] Verify the no-file transfer path in `specs/014-remote-image-paste/quickstart.md`. Inspect before/after workspace and temporary-directory activity during a controlled remote paste. Verify unchanged working directory and no cleanup prompt. Distinguish transfer-created files from the Agent's later storage behavior, which the spec excludes.
- [X] T020 [US2] Verify clipboard isolation and lifecycle preservation in `specs/014-remote-image-paste/quickstart.md`. Observe zero reads with zero gestures and no reads for another Session's grant. Confirm approval, authentication, attachment, reattachment, detach, and Stop rules remain unchanged. Record the checks without changing host permissions or stopping unrelated Sessions.

**Checkpoint**: US2 adds evidence and closes authorization gaps in the shared transfer path. It adds no second transport or stored model.

## Phase 5: User Story 3 - Understand a paste that cannot be delivered (Priority: P2)

**Goal**: Explain an unavailable or failed image transfer without sending a substitute or taking input ownership.

**Independent Test**: Exercise each refusal condition. Confirm an actionable explanation, no attachment or substitute, and a usable Session.
Preserve the existing behavior for unsupported CLIs and valid text clipboards.

### Tests for User Story 3

- [X] T021 [P] [US3] Add refusal cases in `claude-code-ide-tests.el`. Cover absent and false capability predicates, non-leading clients, unavailable GUI selections, and empty image input. Assert no terminal bytes, ownership changes, or false success. Assert the condition and remedy without pinning exact message wording.
- [X] T022 [P] [US3] Add failure cases in `../ghostel/test/ghostel-osc-test.el` and `../ghostel/test/ghostel-mouse-paste-test.el`. Cover unreadable MIME data, clipboard replacement, unsafe text, process loss, and the verified transfer deadline. Assert refusal without partial attachment and preserve normal text handling.

### Implementation and Verification for User Story 3

- [X] T023 [US3] Implement the T005 leadership preflight at the existing Session/zmx boundary in `claude-code-ide-session.el` and `claude-code-ide-zmx.el`. Refuse before transmission when another client owns input. Explain how the user restores delivery. Do not claim leadership, use `zmx send`, or modify zmx.
- [X] T024 [US3] Complete capability and clipboard explanations in `claude-code-ide-session.el` and `../ghostel/lisp/ghostel.el`. Distinguish missing native support, unavailable GUI clipboard, and empty or unreadable image data. Keep successful routes silent and unsupported CLI behavior unchanged. Keep valid text paste on its existing path.
- [X] T025 [US3] Implement verified disconnect and timeout reporting in `../ghostel/lisp/ghostel.el` and `claude-code-ide-session.el`. Use the completion and failure sources established by T005. Clear transient transfer state and prevent incomplete payloads from becoming attachments. Do not equate command return with Agent acknowledgement or add retries.
- [X] T026 [US3] Run the failure matrix in `specs/014-remote-image-paste/quickstart.md`. Exercise old or missing support, non-leading input, unreachable host, timeout, empty clipboard, unreadable data, and absent GUI selection. Verify no substitute, no partial attachment, and usable Session input. Also confirm unchanged unsupported-CLI and text-only behavior.

**Checkpoint**: Every supported-route failure has an observed outcome. No refusal changes the target, Agent, terminal, or input owner.

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Run the complete gates, document actual support, and close the acceptance record.

- [X] T028 Run `./scripts/compile-and-test.sh` and the Ghostel targets in `../ghostel/Makefile` after all integrated changes. Verify package loading, byte-compilation, and tests without native paste support. Record actual commands, counts, and failures in `specs/014-remote-image-paste/quickstart.md`.
- [X] T029 [P] Document remote OMP support, unchanged local routes, and unsupported CLI behavior in `README.org` and `docs/remote.org`. Describe the installed-capability requirement and available remedies without claiming support for untested Agents.
- [X] T030 [P] Document the verified leadership restriction and remedy in `docs/zmx.org`. State that the feature neither changes zmx nor takes input ownership.
- [X] T031 [P] Document the new Ghostel interface and module requirement in `../ghostel/README.org` and `../ghostel/CHANGELOG.md`. State that existing paste commands and OSC 52 behavior remain unchanged.
- [X] T032 Complete the acceptance record in `specs/014-remote-image-paste/quickstart.md` and update `specs/014-remote-image-paste/tasks.md`. Link observed evidence for FR-001 through FR-017, EC-01 through EC-09, and SC-001 through SC-006. Leave unmet checks open. Remove only temporary verification artifacts created for this feature.

## Dependencies & Execution Order

### Phase Dependencies

```text
Setup T001-T002
  -> Foundation T003-T005
  -> US1 T006-T015
  -> US2 T016-T020
  -> US3 T021-T026
  -> Final gates T028
  -> Documentation T029-T031
  -> Acceptance record T032
```

US2 and US3 need US1's real transfer path for their independent acceptance checks.
Their concerns remain separate, but their source files overlap. Run the story phases sequentially to avoid shared edits.
US3 does not depend conceptually on US2's no-file check. The execution order preserves priority and one owner per shared file.

### Within Each Story

1. Write the listed tests before the related implementation.
2. State the property each test proves.
3. Use fixed-seed generated payloads for byte preservation, chunk bounds, ordering, and isolation.
4. Cover empty, single-byte, 4095-byte, 4096-byte, 4097-byte, multi-chunk, and large payloads.
5. Print the seed and smallest failing case when a generated check fails.
6. Integrate shared edits before running checks.
7. Exercise the real changed path before marking the story complete.

Tests must prove consumer-visible behavior, not copied formulas, function wiring, or exact incidental wording.
Keep valid existing behavioral regressions. Remove incidental wording or implementation tests rather than repinning them.
The shared exchange must enforce authorization from T008 onward. US2 verification is not permission to omit early security checks.

### Detailed Dependencies

- T003 and T004 follow Setup. T005 incorporates both results and closes all shared prerequisites.
- T006 and T007 can run together after T005.
- T008 follows T006. T009 follows T008 and uses T004's verified clipboard mapping.
- T010 follows T009. T011 follows T007 and the working Ghostel provider, including T010.
- T012 and T013 follow T011. T014 verifies the integrated US1 code before T015 exercises it live.
- T016 and T017 can run together after US1. T018 follows both tests. T019 and T020 verify the integrated result.
- T021 and T022 can run together after US2. T023-T025 then run sequentially because their files overlap.
- T026 follows all failure handling.
- T028 follows every story. T029-T031 can then run together because their files do not overlap.
- T032 follows all checks and documentation. A blocked acceptance check prevents feature completion.

## Parallel Example: User Story 1

After T005, assign these independent test-authoring slices:

```text
Worker A: T006 — ../ghostel/src/GhostelTerm.zig and ../ghostel/test/ghostel-osc-test.el
Worker B: T007 — claude-code-ide-tests.el
```

Integrate both results before native implementation and verification. Do not run tests while either worker edits.

## Parallel Example: User Story 2

After US1, assign these independent test-authoring slices:

```text
Worker A: T016 — Ghostel grant and clipboard authorization properties
Worker B: T017 — Package Session identity and boundary properties
```

Both use the established transfer contract. Neither worker changes the other's files.

## Parallel Example: User Story 3

After US2, assign these independent test-authoring slices:

```text
Worker A: T021 — claude-code-ide-tests.el refusal outcomes
Worker B: T022 — Ghostel native host and paste failure outcomes
```

Then use one integration owner for T023-T025. Their source files overlap.

## Implementation Strategy

### MVP First

The first demonstrable increment is Setup, Foundation, and US1: one supported remote OMP route with unchanged local behavior.
It is not the completed feature. US2's privacy requirements and US3's refusal requirements remain release requirements.
Do not defer grant validation, byte preservation, or missing-capability refusal to a later increment.

### Incremental Delivery

1. Establish the verified native and remote prerequisites.
2. Deliver and observe the supported remote transfer.
3. Complete the no-file, authorization, and lifecycle evidence.
4. Complete the refusal and failure behavior.
5. Run the full gates and finish user documentation.
6. Close the feature only when every required acceptance check has evidence.

## Requirement Coverage

| Requirement group | Tasks |
|---|---|
| FR-001, FR-003, FR-008, FR-011, FR-015, FR-016 | T006-T015 |
| FR-002, FR-013, FR-014, SC-004 | T007, T009-T011, T014, T021, T024, T028 |
| FR-005, FR-006, FR-007, FR-012 | T008-T009, T016-T020 |
| FR-004, FR-009, FR-010 | T002, T005, T011, T021-T026 |
| FR-017, EC-01, EC-02, EC-03 | T004, T006, T009, T013, T015, T022 |
| EC-04, EC-08, EC-09, SC-005 | T005, T012-T015, T016, T020 |
| EC-05, EC-06, EC-07, SC-003 | T007, T021-T026, T028 |
| SC-001, SC-002 | T015 |
| SC-006 | T016, T020 |
| Complete acceptance record | T032 |

## Execution Notes

- Work on the current branches. Do not commit or push without a separate user request.
- Use `~/bin/emacsclient --eval` to inspect Emacs and load changed Lisp.
- A changed native module needs a fresh Emacs process or an approved restart, not a Lisp reload alone.
- Use synthetic, non-sensitive images for live checks. Do not transmit the user's existing clipboard content.
- Confirm the exact remote target and payload immediately before a live transfer unless the user already authorized that exact action.
- Restore temporary clipboard state after the checks. Do not terminate unrelated Sessions.
- Preserve text paste, keybindings, optional dependencies, host approval, and lifecycle ownership throughout implementation.
- No task claims the Agent accepted an image merely because the package sent a paste event.

## Phase 7: Convergence

These tasks address findings F1–F8, except the withdrawn participant trial F6. In this phase, `packages/` paths start at `/Users/fuyu0425/agents/oh-my-pi`.

- [X] T033 [HIGH] [F1] Bind the original Session and editor before verified receipt in `packages/coding-agent/src/utils/enhanced-paste.ts` and `packages/coding-agent/src/modes/controllers/input-controller.ts`. Invalidate destination changes through `packages/coding-agent/src/modes/controllers/session-focus-controller.ts` and `packages/coding-agent/src/modes/interactive-mode.ts`. Cover pre-`DONE` changes and switch-away/switch-back cases in `packages/coding-agent/test/input-controller-enhanced-paste.test.ts`. Preserve the final commit check and local/legacy behavior. Sources: FR-001, EC-04, EC-08, plan lifecycle rules, T005R. Gap type: partial.
- [X] T034 [HIGH] [F2] Preserve bounded, process-bound delivery-uncertainty observation after local write completion in `../ghostel/lisp/ghostel.el`. Retire clipboard authorization promptly. Explain a subsequent connection loss while delivery remains uncertain, without retries or success claims. Update `../ghostel/src/GhostelTerm.zig` only if the outcome distinction requires it. Prove the post-write disconnect case with the retained regression in T037. Preserve the approved unconfirmed-delivery model rather than assuming local writes prove remote attachment. Sources: FR-004, FR-010, US3/AC3, T025. Gap type: partial.
- [X] T035 [HIGH] [F3] After explicit model-turn approval, complete T015's remaining acceptance checks in `specs/014-remote-image-paste/quickstart.md`. Verify next-turn image acknowledgement, usable dimensions and image content, and local/remote parity with synthetic images. Record each gesture's Session, attachment number, and expected/received byte digest for the alternating-Session check. Keep the acceptance blocked without the required approval. Sources: FR-011, FR-015, US1/AC1, SC-005, T015. Gap type: partial. Three approved vision turns and the exact per-gesture record are complete. The later private zmx correction closed T015's transport failure without another model turn.
- [X] T036 [MEDIUM] [F4] Reject undecodable verified image data before attachment in `packages/coding-agent/src/modes/controllers/input-controller.ts`. Reuse the decode validation in `packages/tui/src/chat/image-loading.ts`. Keep the expiry and destination checks after awaited validation. Add invalid-image boundary coverage in `packages/coding-agent/test/input-controller-enhanced-paste.test.ts`. Preserve transferred bytes, local/legacy behavior, ordinary storage, and the Agent's supported format rules. Sources: FR-010, FR-015, T005R. Gap type: contradicts.
- [X] T037 [MEDIUM] [F5] Retain public-path expiry and process-loss regressions in `../ghostel/test/ghostel-osc-test.el` and the relevant `../ghostel/test/ghostel-mouse-paste-test.el` cases. Cover failure after admission, including disconnect after a completed local write. Exercise both PTY writers where their failure paths differ. Assert semantic explanations, retired authorization, rejection of incomplete data, and recovery where the Session remains usable. Do not replace these checks with metadata-range or first-write assertions. Sources: FR-004, FR-010, T022, T025. Gap type: partial.
- [X] T039 [MEDIUM] [F7] After explicit user approval, remove only `projects["/private/var/folders/vg/4l8mg2ss5m36qk342npvgw240000gq/T/cci014-local-parity-_x0pe4jh/claude"]` from `~/.claude.json`. Confirm the exact obsolete trust entry immediately before removal. Preserve every other current field rather than restoring an old configuration snapshot. Record the cleanup evidence in `specs/014-remote-image-paste/quickstart.md`. Source: T032. Gap type: partial.
- [X] T040 [LOW] [F8] Strengthen the clipboard refusal cases in `claude-code-ide-tests.el` to distinguish empty data from unavailable GUI access. Assert the condition and remedy without exact text matching. Preserve the current correct messages and avoid production changes for this test gap. Sources: T021, T024. Gap type: partial.
- [X] T041 [HIGH] Correct the confirmed zmx input loss under the approved scope exception. Update `/Users/fuyu0425/agents/zmx/src/loop.zig`, `src/ipc.zig`, and `src/util.zig`. Preserve accepted bytes with backpressure, FIFO order, responsive control requests, and EOF handling. Keep the regression in `test/backpressure.py` and `test/backpressure.bats`. Verify private local and remote candidates with two attached clients, exact image digests, and no further model turns. Installation needs separate approval.

## Phase 8: Convergence

This assessment found two partial gaps in the current implementation and retained regression coverage.
T042 confirmed and corrected F1. Its regression and API smoke passed.
F2 concerns a retained regression, not a demonstrated production failure.
T039 remained deferred during this phase. The later approved cleanup is complete.
Paths under `packages/` start at `/Users/fuyu0425/agents/oh-my-pi`.
This phase authorizes no installation, model turn, or trust change.

- [X] T042 [HIGH] [F1] Complete verified-image format validation in `packages/coding-agent/src/modes/controllers/input-controller.ts` and `packages/tui/src/chat/image-loading.ts`. Reject actual/declared format disagreement before ordinary image preparation or editor mutation. Preserve full decoding, original bytes, and local/legacy behavior. Extend `packages/coding-agent/test/input-controller-enhanced-paste.test.ts` with a decodable unsupported-format case carrying a supported MIME label. Assert unchanged pending attachments after refusal and successful recovery with a valid image. Evidence: `image-loading.ts:91-100` skips MIME agreement when `parseImageMetadata` returns null. Per FR-010, FR-015, T036, and plan: receiver validation checks (partial).
- [X] T043 [MEDIUM] [F2] Complete T037's retained partial-reply regression in `../ghostel/test/ghostel-osc-test.el` using the existing two-PTY fixture. Exercise interruption or expiry after image DATA starts through both the native and Emacs PTY writers. Assert the explanation, retired authorization, and receiver rejection of incomplete data. Verify a fresh successful paste when the Session remains usable. Keep the existing completed-write disconnect checks. Evidence: `ghostel-osc-test.el:1357-1468,1737-1770` covers zero-read failures, complete replies, and mocked Emacs-writer interruption, but not this complete matrix. Per FR-004, FR-010, US3/AC3, T022, and T037 (partial).

## Phase 9: Convergence

This assessment found one validation-scope question and one plan reconciliation gap.
The assessment smoke confirmed that ordinary attachments also used the strict unknown-format rejection.
T044 isolated that restriction to verified receipt. T045 reconciled the plan's approved zmx exception.
The actual PNG decode output passed validation. No correctly labeled PNG failure was found.
T043 covers partial-data rejection and recovery through both PTY writers. T039 is complete.
Paths under `packages/` start at `/Users/fuyu0425/agents/oh-my-pi`.
This phase authorizes no installation, model turn, remote transfer, clipboard change, or trust change.

- [X] T044 [MEDIUM] [F1] Resolve T042's broader validation policy in `packages/tui/src/chat/image-loading.ts`. Review its ordinary attachment and provider-context consumers in `packages/coding-agent/src/utils/image-loading.ts` and `packages/coding-agent/src/session/provider-image-budget.ts`. Either justify the broader policy against the local/legacy preservation requirements in the feature artifacts or isolate the verified-specific restriction. Keep verified actual/declared format validation before editor mutation in `packages/coding-agent/src/modes/controllers/input-controller.ts`. Preserve full decoding, existing recognized-format mismatch checks, and original verified bytes. Retain verified refusal, unchanged draft/pending attachments, and valid-image recovery checks in `packages/coding-agent/test/input-controller-enhanced-paste.test.ts`. Add a focused ordinary-path behavior check under the resolved policy using the same decodable unsupported-format case. Evidence: `packages/tui/src/chat/image-loading.ts:91-96` rejects an unknown container labeled with a supported MIME type. A read-only smoke decoded the synthetic BMP successfully, but `loadImageAttachmentInput` rejected it with a PNG label. Sources: FR-002, T036, T042, plan: Summary and receiver validation checks. Gap type: unrequested.
- [X] T045 [LOW] [F2] Reconcile the zmx scope statements in `specs/014-remote-image-paste/plan.md`. Update Structure Decision, Multiplexer, and Post-Design Constitution Check to match the approved input-backpressure exception and completed T041. Preserve the separate installation approval and unchanged IPC, leadership, host approval, authentication, and attachment lifecycle limits. Do not undo the backpressure correction or expand its scope. Evidence: plan lines 53-57 and 201 approve the correction, but lines 187, 282, and 349 still describe an untouched multiplexer. Sources: plan: approved zmx exception, T005, T041. Gap type: partial.
