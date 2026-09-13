# Implementation Plan: Ghostel-Only Terminal Support

**Branch**: `main` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/008-remove-legacy-backends/spec.md`.

**Status**: Design complete under constitution 2.0.0. Ready for task generation, not an implementation-completion claim.

The setup script identifies the feature as `008-remove-legacy-backends`.
The actual Git branch remains `main`. This planning run does not create a branch or commit.
This plan is an explicit removal record under FR-013.

## Summary

Remove EAT and vterm support completely and keep Ghostel as the sole terminal runtime for Agents and companion shells.
Delete terminal-selection policy and retired implementations rather than retain a one-value dispatcher.
Preserve the shared Session layer, Ghostel behavior, optional loading, ownership, six layouts, and existing local/remote workflows.

Use the existing Ghostel constructors with one shared point-of-use availability check.
Migrate all affected package callers and the directly related Spacemacs consumer.
Clean all maintained repository references, including prior feature documents.
Add Ghostel-only support to the README's existing distinction list while retaining the original repository attribution.

Research and design outputs:
- [research.md](research.md): decisions, rationale, alternatives, and primary source evidence.
- [data-model.md](data-model.md): existing entities, ownership invariants, and lifecycle transitions.
- [contracts/elisp-surface.md](contracts/elisp-surface.md): retained and removed interfaces and consumer obligations.
- [quickstart.md](quickstart.md): runnable batch checks and native acceptance procedure.

## Technical Context

**Language/Version**: Emacs Lisp with lexical binding. Emacs 28.1 or later.

**Primary Dependencies**: Existing declared dependencies remain unchanged: websocket, transient, web-server, persist, with-editor, and avy.
Ghostel and its native module remain optional at terminal-use boundaries.
Transport and diagnostics providers retain existing optional-loading safeguards.
Optional zmx, remote tools, and project-view providers remain subject to existing capability and admission checks.
No new runtime dependency is required.

**Storage**: Existing Session registry, persistence, and saved layouts.
The Session struct has no backend field. No storage migration or new schema is needed.
Live companion buffers remain outside persisted layout data.

**Testing**: Full `scripts/compile-and-test.sh`, existing ERT interfaces and Ghostel mocks, and focused related parent tests.
Verification includes optional-absence and dependency-present environments plus native Ghostel workflow checks.
Current Magit integration-test dependency assumptions need bounded test isolation, not a new terminal prerequisite.
See research R6 and quickstart sections 2–5.

**Target Platform**: Existing Emacs environments and approved remote Ghostel workflows.
The current CI matrix covers Linux/macOS with Emacs 28.1, 29.4, and 30.1, plus an experimental snapshot entry.
This removal does not expand platform support or remote capabilities.

**Project Type**: Emacs package with shared Agent Sessions, terminal companions, and manager layouts.
A related consumer lives in the parent Spacemacs repository.

**Performance Goals**: Preserve existing input, output, resize, reflow, focus, and activity behavior.
Delete retired render queues and selector work without adding a new dispatch or caching layer.
The specification defines no new numerical performance target.

**Constraints**: Optional dependencies must remain optional for loading, compilation, tests, and non-terminal operations.
Never install native support automatically, substitute a host/directory, or infer ownership from terminal mode alone.
Preserve Agent capability limits, remote admission, saved-layout precedence, and live shell reuse.
No compatibility aliases, hot conversion, external package removal, Git history rewrite, or unrelated terminal changes.

**Scale/Scope**: Five Agent types, six layout presets, every existing local/remote terminal entrypoint, and all maintained support references.
The related parent package configuration and tests migrate with removed private interfaces.
No MCP protocol or external API change is planned.

## Constitution Check

The governing [constitution](../../.specify/memory/constitution.md) is version **2.0.0**, amended 2026-09-12.
That amendment resolved the earlier support-policy conflict before this planning run.
FR-014 is complete. This plan requires no further governance amendment.

| Principle | Initial gate | Post-design gate and evidence |
| --- | --- | --- |
| I. Shared Session Core, Thin Agent Adapters | PASS | PASS. One shared terminal factory and Session layer remain. CLI builders retain only Agent command differences. Research R1–R2, contract C1–C2. |
| II. Batch-Verifiable Quality Gate | PASS | PASS for design. Full ERT and compilation remain mandatory without optional packages. Behavior mocks and explicit native-integration evidence remain distinct. Research R6, quickstart 2–5. |
| III. Optional Dependencies Stay Optional | PASS | PASS. Soft Ghostel loading and native checks occur only at terminal use. Auto-install stays disabled through construction. Research R3, contract C1. |
| IV. Ghostel-Only Terminal Support | PASS | PASS. Retired implementations, preferences, caches, and aliases disappear. Exact live ownership remains required. Contract C2–C5 and data-model invariants. |
| V. Simplicity and Compatibility | PASS | PASS. Emacs 28.1+, no new dependency or stored entity, direct Ghostel calls, and complete caller migration. Research R1, R8–R9. |
| VI. Local and Remote Workflow Parity | PASS | PASS. Existing host approval and remote constraints remain. Terminal attachment stays independent of optional project views. Contract C4, quickstart 8. |

**Post-design result**: PASS. No unresolved clarification or unjustified exception remains.
These are design gates. Implementation must still prove all automated and native acceptance criteria.
A dependency-present baseline does not establish optional-absence or native workflow acceptance.

## Project Structure

### Documentation (this feature)

```text
specs/008-remove-legacy-backends/
  spec.md
  plan.md
  research.md
  data-model.md
  quickstart.md
  contracts/
    elisp-surface.md
  checklists/
    requirements.md
```

`tasks.md` belongs to the later `/speckit.tasks` phase. This planning run does not create it.

### Source Code (repository root)

```text
claude-code-ide.el                 shared factory, selectors, resize, lifecycle, remote entry
claude-code-ide-session.el         dependency check, setup, input, companion construction
claude-code-ide-session-idle.el    output/focus observers and activity
claude-code-ide-transient.el       obsolete terminal documentation
claude-code-ide-tests.el           behavior fixtures, failure checks, optional isolation
scripts/compile-and-test.sh       retired dependency discovery
README.org                        support policy and existing fork-distinction list
docs/remote.org                   obsolete terminal-choice instructions
docs/zmx.org                      consistency review of persistent-session guidance
TODOs.org                         retire the matching removal backlog item
specs/001-zmx-sessions/           affected prior specification and design documents
specs/003-attach-remote-agents/   affected prior specification, guide, plan, and tasks
specs/004-grouped-global-view/   affected plan and native acceptance records
specs/006-sidebar-detail-view/   affected plan and research
specs/007-add-layout-presets/    affected plan, quickstart, and tasks
```

**Verification boundaries, unchanged unless a concrete removed caller requires an edit**:
`claude-code-ide-manager.el`, `claude-code-ide-zmx.el`, `.github/workflows/test.yml`, `CONTEXT.md`, `AGENTS.md`, and `.specify/memory/constitution.md`.
Inspect all other maintained files for references. The named inventory is not a scope exemption.
The constitution and maintainer guide already reflect Ghostel-only policy.

**Inventory boundary**: Use Git's tracked-file list for maintained package source, README, docs, automation, and prior spec artifacts.
Add new maintained feature artifacts explicitly, even before they are tracked.
Hidden tracked files remain in scope.
Do not use an unrestricted ignored-file search as the cleanup inventory.

The current `.gitignore` excludes `refs/`, `ref-docs/`, and `.omp/`. None currently contain tracked files.
Classify matches there separately as ignored reference material, external checkouts, or local tool state.
Do not edit that material or count its matches against the maintained-package zero-support requirement.
External repositories remain outside scope except for the two explicitly named parent consumer files.
An ignore rule does not exempt an already tracked maintained file.

**Related parent consumer**, relative to the package root:

```text
../../lisp/pkgs/pkg-claude-code-ide.el
../../tests/pkg-claude-code-ide-test.el
```

**Structure Decision**: Update existing modules and tests.
Add no terminal adapter framework, standalone migration package, new persistence model, or production file.
Keep unrelated parent configuration and installed terminal packages outside the change.

## Implementation Design

### A. Shared runtime cutover

Delete the selection settings, both current-backend resolvers, the resolver/cache/process lookup, and retired branch machinery listed in contract C5.
Remove retired declarations, requires, hooks, advice, callbacks, setup aliases, renderer queues, and timers.
Migrate every affected caller before deleting each interface.
Do not retain constant-return dispatchers or obsolete-variable compatibility declarations.

Keep `claude-code-ide--create-terminal-with-command` and its `(buffer . process)` result.
Keep Agent command construction, environment, directory, zmx wrapping, and CLI identity unchanged.
Use `ghostel-exec` for Agent commands and `ghostel-create` for ordinary companion shells.
Remove only OMP's backend condition, preserving its graphical/terminal image-protocol difference.

### B. Availability and lifecycle boundaries

Replace the selection-dependent ensure helper with `claude-code-ide-session--ensure-ghostel ()`.
Reuse it for Agent creation, remote attachment, and companion creation.
Disable native auto-install dynamically across loading and construction.
Report missing support at terminal use without impairing package loading or non-terminal operations.

Confirm a live process before publishing successful creation.
Preserve the existing rollback and companion partial-buffer safety rules.
Keep exact Session ownership, registration timing, stale-callback guards, and ordinary-shell distinction.
Remove only the redundant remote backend-selection rejection, not remote admission or zmx checks.

Unify the current library-only Agent check and the companion native check in that one preflight.
Check `ghostel--new` availability as well as soft library loading.
Run preflight before MCP startup or terminal creation.
Preserve setup timing, then validate the returned live process before active Session registration.
After callback installation and initialization delay, recheck ownership and liveness before display or a success message.
Keep existing rollback for resources owned by the failed request.
An existing disconnected remote target row may remain after failure. It must not represent a successful live attachment.

On reload, old terminal buffers must fail the actual Ghostel mode boundary without reconfiguration, adoption, input, or destructive cleanup.
Require restart instead of converting those buffers.
New creation must never consult their cached backend preference.

### C. Surviving interaction and display

Simplify shared setup and input to Ghostel while retaining paste/raw input distinctions, control keys, activity, and image limits.
Keep generic input aliases still used by consumers.
Keep both Ghostel output observers, focus tracking, copy mode, exact cursor handling, and reflow behavior.
Remove backend arguments from resize install/remove helpers and target Ghostel directly.
Preserve observer idempotence and first/last Session lifetime.

The manager retains six presets, layout precedence, selected-window restoration, live shell reuse, and stale-request checks.
Do not remove generic popup side/width settings or change zmx detach into Stop.
No layout schema migration or remote transport change is required.

### D. Related consumer migration

Remove the parent package's two terminal-choice assignments and dead vterm workaround comment.
Replace five removed resolver calls with real Ghostel mode checks in page navigation, End, and Evil state hooks.
Keep unrelated-buffer fallback, Plan Review pass-through, copy-mode transitions, and hidden-buffer recenter protection.
Migrate parent test fixtures accordingly.
Preserve the existing `magit-left` preference, popup settings, and unrelated uncommitted work.

### E. Verification and documentation cutover

Remove retired terminal mocks and tests that validate deleted policy or renderer behavior.
Migrate surviving launch, environment, input, lifecycle, activity, and layout fixtures to Ghostel interfaces.
Add only meaningful regressions for uncertain failure, ownership, and no-install boundaries.
Delete source-text and forwarding-only assertions instead of repinning them.
Remove `emacs-libvterm` discovery from the runner without machine-specific replacement paths.

Keep the full optional-absence gate active.
Mock optional provider interfaces for package behavior tests.
Limit dependency-absence skips to genuine native integration tests, then execute those tests in a dependency-present lane.
Preserve the existing CI platform matrix and report the two environments separately.

Audit every native Magit submodule require, including the current unconditional `magit-status` require in the unavailable-project-view test.
Keep package failure behavior active through interface mocks. Guard only tests whose purpose requires real Magit behavior.
Do not let a missing optional integration prevent the full suite from loading.

Clean all current guidance and prior feature references under FR-011 through FR-013.
Add the README distinction to the existing list, not a second competing section.
Preserve attribution and truthful historical evidence.
Remove obsolete historical acceptance rows or identify them as superseded without claiming a new Ghostel pass.
Review each remaining product or identifier match rather than deleting unrelated substrings.

### Sequencing and integration boundary

Research is complete. The data model and contracts define the cutover interfaces before implementation.
Runtime and directly related parent caller changes form one coordinated cutover.
Test fixtures must follow those contracts before final verification.
Documentation cleanup can proceed independently using the same removal-record rule.
Run formatting and the complete quality gate once after concurrent implementation changes settle.
Then execute the native acceptance guide and remove only verification artifacts created by this work.

## Requirement Traceability

| Requirement | Design coverage | Required proof after implementation |
| --- | --- | --- |
| FR-001 | A–B, contract C1 | All Agent and companion entrypoints use Ghostel. Quickstart 6–8. |
| FR-002 | A, C, contract C5 | No retired creation, input, display, hook, callback, cleanup, or workaround path. Quickstart 9. |
| FR-003 | A, D, contract C5–C6 | Removed settings and aliases absent. Legacy assignments have no effect. Quickstart 4–5, 9. |
| FR-004 | A, C, contract C2–C3 | Native interaction, capability limits, both output paths, resize, focus, and notifications. Quickstart 4, 6. |
| FR-005 | B–C, data-model transitions | Local/remote identity, detach, reconnect, and owned Stop. Quickstart 8. |
| FR-006 | C–D, contract C4 | All six presets, saved-layout precedence, focus, live reuse, and generic popup behavior. Quickstart 5, 7. |
| FR-007 | B, E, contract C1 | Optional-absence full gate and no-Ghostel package-load check. Quickstart 2–4. |
| FR-008 | B, data-model validation | Failure without false success, wrong directory/host, or damage to existing Sessions. Quickstart 4. |
| FR-009 | B–C, contract C4 | Admission and project-view independence without extra connections. Quickstart 4, 8. |
| FR-010 | E, research R6 | Migrated mocks/tests, removed runner discovery, full gate in both dependency environments. Quickstart 2–5. |
| FR-011 | E, research R7 | Complete maintained-file inventory, including prior documents and hidden automation. Quickstart 9. |
| FR-012 | E, contract C7 | README distinction and consistent guidance with original attribution. Quickstart 9. |
| FR-013 | E, contract C7 | Every residual reference has an explicit removal-record or unrelated-text classification. Quickstart 9. |
| FR-014 | Constitution Check | Existing constitution 2.0.0 and aligned maintainer guidance. No further amendment. |
| FR-015 | A–D, contract compatibility boundary | Shared Agent behavior, bounded parent migration, and preserved unrelated terminals. Quickstart 4–8. |

**Success criteria**: SC-001 maps to quickstart 6, SC-002 to 7, SC-003 to 3–4, and SC-004/SC-005 to 9.
SC-006 maps to quickstart 8. SC-007 maps to 2–3.
The guide also covers all three user stories, their fourteen acceptance scenarios, and the eight specified edge cases.

## Planning Verification

Verified on 2026-09-12:

- All five planning artifacts exist. Relative Markdown links resolve, and template placeholders are absent.
- The plan maps all fifteen functional requirements and seven success criteria.
- Shell command blocks pass `bash -n`. Emacs accepts the quickstart probes' Lisp syntax.
- The full `scripts/compile-and-test.sh` gate passed: 932 tests, 924 expected results, zero unexpected results, and eight skips.
- This run used a disposable HOME and installed dependency paths through `EMACSLOADPATH`, including Magit and its dependencies.
- The first attempt lacked `llama` on that explicit path. The corrected dependency path produced the full pass.
- Byte compilation passed with warnings in unchanged source. Native compilation was not requested.
- Protected source, specification, governance, and parent consumer files remained unchanged.
- No `tasks.md`, runtime implementation, branch change, or commit was created.

These results verify the planning change against the current implementation.
They do not establish post-removal optional-absence, native Agent, layout, or remote acceptance.
The implementation must execute the quickstart guide after the cutover.

## Complexity Tracking

No constitution violation or new runtime dependency requires an exception.
The smallest design removes selection and retired code while preserving existing Session and layout models.
Optional integration test isolation is a verification requirement, not a new runtime abstraction.
