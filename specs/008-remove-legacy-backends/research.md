# Research: Ghostel-Only Terminal Support

**Date**: 2026-09-12
**Spec**: [spec.md](spec.md)
**Status**: Resolved for implementation planning. No runtime removal has occurred.

This document is an explicit removal record under FR-013.
It names EAT, vterm, and their symbols only to define the removal.
Repository source takes precedence over research-agent recommendations.

## R1. Remove terminal selection, not the shared Session layer

**Decision**: Delete global selection, per-Agent overrides, cached backend identity, backend resolvers, and retired implementations.
Retain the existing shared terminal factory and Session operations with direct Ghostel calls.
Do not retain resolvers that always return `ghostel` or aliases for removed settings.

**Rationale**: The core Session record has no backend field.
Terminal selection adds no useful state when the package supports one runtime.
Shared Session behavior remains necessary for all five supported Agents.

**Alternatives considered**:
- Keep selectors with one allowed value. Rejected because FR-003 requires their removal.
- Add a terminal adapter interface. Rejected because there is only one implementation.
- Duplicate Ghostel calls in each Agent builder. Rejected because this violates shared Session behavior.

**Sources**: [core](../../claude-code-ide.el), `claude-code-ide-terminal-backend`, `claude-code-ide-cli-terminal-backends`, `claude-code-ide-session`, `claude-code-ide--create-terminal-with-command`.

## R2. Preserve both existing Ghostel construction contracts

**Decision**: Keep `ghostel-exec` for Agent command execution and `ghostel-create` for ordinary companion shells.
The shared Agent factory continues to return `(buffer . process)`.
`ghostel-exec` returns a lifecycle process, not that cons.
`ghostel-create` returns a new buffer, not a reusable shell selected by directory.

**Rationale**: Agent commands need the existing shell, `-lc` arguments, environment, directory, and zmx wrapping.
Companion shells need ordinary shell initialization and caller-controlled reuse.
A constructor change would alter behavior unrelated to terminal removal.

Preserve CLI-specific command construction, quoting, and environment variables.
For OMP, remove only the backend condition around `PI_FORCE_IMAGE_PROTOCOL`.
Keep `kitty` in graphical Emacs and `off` in terminal Emacs. Do not apply this OMP rule to Pi.

**Alternatives considered**:
- Use one Ghostel constructor for both roles. Rejected because their return values and shell behavior differ.
- Parse commands into a new argument model. Rejected because the existing command contract already works.

**Sources**: [core](../../claude-code-ide.el), `claude-code-ide--create-terminal-with-command`, OMP command builder.
[Session module](../../claude-code-ide-session.el), companion-shell creation.
Adjacent dependency source: [Ghostel](../../../ghostel/lisp/ghostel.el), `ghostel-exec` and `ghostel-create`.

## R3. Check optional support without installation

**Decision**: Replace `claude-code-ide--terminal-ensure-backend` with `claude-code-ide-session--ensure-ghostel`.
The replacement takes no arguments and serves Agent creation, remote attachment, and companion creation.
It soft-loads Ghostel and checks its required native support at the terminal-use boundary.
Missing support produces an actionable `user-error`.

Bind `ghostel-module-auto-install` to nil across both dependency loading and actual terminal construction.
Keep the existing forward declaration so the binding remains dynamic under lexical binding.
Do not change the user's global Ghostel preference.
Unify the existing library-only Agent check with the companion's `ghostel--new` availability check.
Do not preserve separate checks with different native-support guarantees.

**Rationale**: Both Ghostel constructors call `ghostel--load-module` with prompting enabled.
Ghostel's native installer defaults to `ask`.
A binding that covers only `require` cannot prevent constructor-time installation prompts.
Plain package loading must not require Ghostel or its native module.

**Alternatives considered**:
- Delete availability checks with the selector. Rejected because a void-function failure is not actionable.
- Hard-require Ghostel. Rejected by Principles II and III.
- Set Ghostel's installation option globally. Rejected because unrelated terminal workflows must remain unchanged.

**Sources**: [Session module](../../claude-code-ide-session.el), dependency forward declarations, existing ensure helper, and companion creation.
Adjacent source: [Ghostel module installer](../../../ghostel/lisp/ghostel-module-install.el), `ghostel-module-auto-install` and `ghostel--load-module`.

## R4. Preserve ownership, failure isolation, and Session recognition

**Decision**: Preserve Session IDs, exact buffer ownership, process representation, and existing registration timing.
Keep customizable Session predicates and add no new pending-registration state.
Setup still requires the actual Ghostel mode.
Ownership-sensitive actions still use the live registered Session buffer and its process.

An ordinary Ghostel shell is not an Agent Session.
Creation must confirm a live process before publishing success.
On failure, preserve existing Sessions and live unrelated buffers.
Companion cleanup may remove only a dead partial buffer created by that request.
Keep the current handling that preserves a live shell after an error or superseded asynchronous request.

**Rationale**: Setup can run before complete Session registration.
Requiring registration for every setup operation would break that lifecycle.
Conversely, recognizing all Ghostel buffers would permit unrelated shell adoption.

**Alternatives considered**:
- Recognize Sessions by terminal mode alone. Rejected because terminal type does not establish ownership.
- Key companions by directory or host. Rejected because multiple Sessions may share both.
- Kill every partially created buffer on failure. Rejected because a live shell may already exist.

**Sources**: [core](../../claude-code-ide.el), `claude-code-ide-session-for-buffer`, `claude-code-ide--session-buffer-from-process`, Session registration and cleanup.
[Session module](../../claude-code-ide-session.el), `claude-code-ide-session-buffer-p` and companion liveness.
[manager](../../claude-code-ide-manager.el), `claude-code-ide-manager--companion-shells` and captured companion requests.
[domain model](../../CONTEXT.md).

## R5. Remove retired workarounds without removing Ghostel behavior

**Decision**: Delete retired render queues, timers, cursor state, terminal setup functions, and exit hooks.
Delete backend-dependent resize selection and reflow-capability predicates.
Keep meaningful reflow, resize-observer, copy-mode, cursor, and focus behavior for Ghostel.

The resize install/remove helpers lose their backend argument and target `ghostel--adjust-size` directly.
Preserve idempotence and first-Session/last-Session observer lifetime.
Keep `claude-code-ide-prevent-reflow-glitch`, which also governs Ghostel.
Keep activity observation on both `ghostel--filter` and `ghostel--events-filter`.

Text paste, raw input, clipboard handling, and control keys keep their distinct Ghostel paths.
Image paste keeps its current Agent capability limits.
Do not replace a removed selector with an always-true guard.

**Alternatives considered**:
- Delete all code described as a terminal workaround. Rejected because Ghostel still needs some of it.
- Merge both output observers into one. Rejected because Ghostel has two output paths.
- Treat paste and raw input as identical. Rejected because bracketed paste and clipboard semantics differ.

**Sources**: [core](../../claude-code-ide.el), resize/reflow helpers and Ghostel cursor path.
[Session module](../../claude-code-ide-session.el), shared input operations.
[idle module](../../claude-code-ide-session-idle.el), Ghostel output and focus observers.

## R6. Migrate behavior tests and isolate optional integrations

**Decision**: Remove EAT/vterm mocks, dependency discovery, selector tests, and retired-renderer tests.
Migrate generic launch, environment, lifecycle, input, idle, layout, and failure fixtures to Ghostel.
Reuse the existing low-level Ghostel mocks rather than loading a native terminal in batch tests.
Delete tests that assert only removed wiring or source text. Preserve observable behavior checks.

The required full gate must pass with optional packages absent.
Keep core and optional-absence checks active in that environment.
Use existing interface mocks for optional providers where the test checks package behavior.
Tests that genuinely exercise a native optional integration may explicitly skip when that integration is absent.
Run those integration tests again with the dependency present, and report their execution separately.
Do not replace package behavior tests with blanket skips.

**Rationale**: The current suite already mocks Ghostel, including both output filters and resize callbacks.
The current runner still discovers `emacs-libvterm`, which must be removed.
Some current Magit integration tests hard-require Magit submodules.
This is a known verification prerequisite issue, not a terminal requirement.
Resolve it in test isolation rather than adding Magit as a runtime dependency.

The existing dependency-present baseline passed 932 tests: 924 expected results, zero unexpected results, and eight skips.
Those eight skips are not proof of optional-Magit absence coverage.
Do not preserve a fixed test count after deleting obsolete tests.

**Alternatives considered**:
- Install terminal packages for CI. Rejected because optional loading must remain verifiable without them.
- Skip all tests that use optional interfaces. Rejected because this would weaken the quality gate.
- Add machine-specific dependency paths to the runner. Rejected. Use caller-supplied `EMACSLOADPATH` for the dependency-present lane.

**Sources**: [tests](../../claude-code-ide-tests.el), dependency mocks and native Magit integration tests.
[runner](../../scripts/compile-and-test.sh), package discovery and full ERT invocation.
[CI](../../.github/workflows/test.yml), existing Emacs/platform matrix.

## R7. Clean every maintained document without falsifying old evidence

**Decision**: Update the README, terminal guides, comments, backlog, maintainer guidance, automation, and prior feature documents.
Only explicit removal records may retain retired product names.
Previous specifications, plans, tasks, and checklists have no blanket historical exemption.

Use tracked maintained files plus explicitly maintained untracked feature artifacts as the cleanup inventory.
Include hidden tracked automation and prior specs.
The [ignore rules](../../.gitignore) exclude `refs/`, `ref-docs/`, and `.omp/`, which currently contain no tracked files.
Classify their contents separately as ignored reference material, external checkouts, or local tool state.
Do not edit them or count their product references against maintained-package acceptance.
Do not use an ignore rule to exempt an already tracked maintained file.
The two named parent consumer files remain the only external-repository migration exception.

Add Ghostel-only support to the README's existing fork-distinction list.
Preserve the original repository attribution.
Remove obsolete setup examples and support claims across all README sections.
Remove obsolete acceptance rows from prior documents, or state that feature 008 supersedes those rows.
Never rename an old native terminal test result into a Ghostel pass.

**Rationale**: FR-011 through FR-013 explicitly include prior feature documents.
A lexical search alone cannot distinguish removal records, real product names, and unrelated substrings.
Review each match and record the reason for any retained reference.

**Alternatives considered**:
- Clean only runtime files and README. Rejected because the request covers all maintained locations.
- Preserve all historical feature documents unchanged. Rejected by FR-011.
- Delete every occurrence of `eat`. Rejected because unrelated words and legal text are outside scope.

**Sources**: [README](../../README.org), [remote guide](../../docs/remote.org), [zmx guide](../../docs/zmx.org), [backlog](../../TODOs.org).
Prior feature directories: `specs/001-zmx-sessions`, `003-attach-remote-agents`, `004-grouped-global-view`, `006-sidebar-detail-view`, and `007-add-layout-presets`.
[specification](spec.md), FR-011 through FR-013.

## R8. Migrate the related Spacemacs consumer

**Decision**: Update `../../lisp/pkgs/pkg-claude-code-ide.el` and `../../tests/pkg-claude-code-ide-test.el` relative to the package root.
Remove the two terminal-choice assignments and the dead commented vterm workaround.
Replace five calls to the removed current-backend resolver with actual Ghostel mode checks.
Keep the existing fallback for unrelated buffers and the package's Session keymap boundaries.

Migrate parent tests away from backend resolver stubs.
Keep page navigation, Plan Review pass-through, copy-mode transitions, hidden-buffer recenter protection, and file-reference behavior.
Retain the current `magit-left` preference and generic popup side/width settings.
Do not modify unrelated Spacemacs terminal configuration or installed packages.

**Rationale**: The parent package configuration is a real caller of private symbols that this cutover deletes.
Leaving it unchanged would cause key and mode-hook failures.
Generic window settings are not terminal-selection policy.

**Alternatives considered**:
- Preserve a compatibility resolver for the parent. Rejected by FR-003.
- Treat all parent configuration as unrelated. Rejected because these callers directly consume the removed interface.
- Delete the parent's terminal guards. Rejected because commands must still avoid unrelated buffers.

**Sources**: Parent package file, page-up/page-down/End functions, Session setup hooks, and package settings.
Parent test file, Ghostel key and state-transition tests.

## R9. Preserve remote and layout models without migration machinery

**Decision**: Keep the Session struct, persisted layout representation, six presets, and zmx identity rules unchanged.
Remove only the remote entrypoint's obsolete backend-selection rejection.
Retain Ghostel availability, approved-host admission, existing remote command construction, and zmx capability checks.
Remote project views remain optional and independent of terminal attachment.

An editor restart is the supported clean-cutover boundary.
Do not convert old terminal buffers or kill their processes during package loading.
Saved layouts use existing missing-buffer recovery after restart.

**Rationale**: There is no persisted backend field to migrate.
Detach, disconnected attachment, and explicit Stop already have separate meanings.
A new state schema or remote transport would add risk without serving the removal.

**Alternatives considered**:
- Convert live retired-terminal buffers. Rejected because the specification excludes hot conversion.
- Create a local terminal after remote failure. Rejected because it changes the requested host.
- Serialize companion buffers into saved layouts. Rejected because live ownership remains runtime-only.

**Sources**: [core](../../claude-code-ide.el), Session struct and remote creation.
[manager](../../claude-code-ide-manager.el), layout presets and `claude-code-ide-manager--persistable-layout`.
[zmx module](../../claude-code-ide-zmx.el), [domain model](../../CONTEXT.md), and specification edge cases.

## Resolution

All technical questions have a selected implementation approach.
No new dependency, public feature, persistent entity, compatibility period, or governance exception is required.
Native Agent and approved-remote checks remain implementation acceptance work, not research results.
