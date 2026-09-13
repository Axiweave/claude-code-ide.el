# Implementation Plan: Predefined Manager Layouts

**Branch**: `main` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/007-add-layout-presets/spec.md`.

**Feature identifier**: `007-add-layout-presets`.
The setup script reports this identifier as `BRANCH`. The actual Git branch remains `main`.

**Design status**: Phase 0 research and Phase 1 design complete.
**Execution gate status**: ERROR. The required repository gate has existing missing-Magit-module failures. No exception is granted.

## Summary

Add six manager presets through one shared preference: Magit left/right, Shell left/right, and Dired left/right.
Keep `magit-left` as the default and remove the old side preference from package behavior.
Only the Magit presets retain the configurable content function, as temporary compatibility.
Whole-layout customization remains a later feature.

Use the existing manager window-state and remote attempt mechanisms.
Add one runtime Session-to-shell table, a fixed preset descriptor table, and captured layout request metadata.
Use ordinary Ghostel shell creation through the terminal Session layer.
Do not change the Agent CLI, Agent terminal backend, zmx ownership, host approval, or user shell preferences.

A saved layout wins over the current default.
A missing or exited saved shell never causes automatic shell creation.
Explicit shell reset creates a replacement only when no live companion exists.
Session removal releases a live shell as an ordinary terminal, while temporary disconnection retains its association.

This command creates design documents only.
It does not implement the layouts, create `tasks.md`, run feature acceptance scenarios, or commit changes.

## Technical Context

**Language/Version**: Emacs Lisp. Local package and Ghostel require Emacs 28.1 or later. The existing optional RPC project-access client requires Emacs 30.1 or later. The inspected runtime is Emacs 31.1.50.

**Primary Dependencies**: Existing declared package dependencies: websocket, transient, web-server, persist, with-editor, and avy. Dired is built in. Magit remains optional for Git companions. Ghostel 0.53.0 in the inspected checkout supplies `ghostel-create`, its native module, and compat support. The installed RPC client supplies approved remote file/process access. No new runtime dependency is proposed.

**Storage**: Existing manager persisted plists and writable native window state. Add optional preset and shell-name metadata to saved layouts. Keep buffer objects and the new Session-to-shell hash table runtime-only. Keep remote attempts and provider-aware view keys runtime-only.

**Testing**: Existing ERT suite and `scripts/compile-and-test.sh`. New behavior checks belong in `claude-code-ide-tests.el`. Use `emacsclient` for live reload and real window/terminal validation after implementation. Do not load test mocks into live Emacs.

**Target Platform**: Existing supported Emacs desktop platforms. Local Agent terminals use Ghostel exclusively. Current remote Agent attachment remains Ghostel-only. Remote companion shells require a supported POSIX host and the existing admitted project-access path.

**Project Type**: Emacs extension with public preferences, interactive commands, and optional remote process integration.

**Performance Goals**: Keep the remote Agent usable while companion preparation runs. Do not perform remote work on preference changes, sidebar rendering, or ordinary restoration. Reusing or mirroring a live shell starts zero additional shell processes. Reuse native window-state operations rather than parse terminal output or maintain another window tree.

**Constraints**: Six fixed presets, one preference, no general layout registration protocol. No automatic host approval, package installation, remote software installation, local substitution for remote companions, or Agent restart. Captured request identity controls delayed publication. Preserve selected windows, sidebar placement, and ordinary shell preferences.

**Scale/Scope**: All supported Agents use the shared manager workflow. Each Session has at most one owned companion shell association, only when applicable. Identical host/directory values do not merge shell ownership. Git/Dired can reuse native views subject to exact provider and buffer ownership checks.

All technical questions have decisions in [research.md](research.md).
No unresolved product clarification or technical placeholder remains.

## Constitution Check

The design check and the repository execution gate are separate results.
Design completion does not turn a failing repository gate into a pass.

| Principle | Initial design | Post-design result | Evidence and required implementation proof |
| --- | --- | --- | --- |
| I. Shared Session core | PASS | PASS | Preset and window policy live in the manager. Ghostel operations live in the Session layer. Remote preparation uses the existing shared attempt workflow. No Agent adapter changes. |
| II. Batch-verifiable quality gate | ERROR | ERROR | Latest observed run: byte compilation passed, 915 tests, 896 expected, 10 missing-Magit-module failures, 9 skipped. The exact required gate must succeed before implementation acceptance. |
| III. Optional dependencies | PASS | PASS | Ghostel loads only for shell creation. Dired requires neither Ghostel nor Magit. Missing support leaves the Agent usable. No new hard require. |
| IV. Ghostel-Only Terminal Support | PASS | PASS | Companion choice does not change the Agent terminal. Validate available local and remote Agents through Ghostel. |
| V. Simplicity and compatibility | PASS | PASS | One fixed alist, one runtime shell table, additive layout metadata, and existing workers. Local Emacs 28.1 remains supported. No new framework or dependency. |
| VI. Local/remote parity | PASS | PASS | Same presets, focus, ownership, and saved-layout rules. Remote preparation may finish later due to remote I/O. Exact host approval and independent terminal use remain required. |

### Gate error and scope

The missing-Magit failures already occurred before planning and before any layout implementation.
The live Emacs can locate Magit, but the required script uses a different batch package path.
That difference explains why a live package installation is not sufficient evidence for the required gate.
This plan does not install packages or modify unrelated test infrastructure.

The Phase 0/1 design artifacts are complete, but the command cannot report an overall passing gate.
The repository execution error remains a prerequisite for implementation acceptance, with no waiver in Complexity Tracking.

### Reviewer corrections included in the planning input

The specification now states that missing/exited companions alone cannot trigger default-layout fallback.
Reset replacement uses the condition that no live companion shell exists.
It distinguishes a killed buffer, an exited process, a hidden window, and a retained remote disconnection.
It documents delayed remote preparation, disabled versus failed access, and output retention under Ghostel preferences.
The four accepted clarification answers remain intact.

## Project Structure

### Documentation (this feature)

```text
specs/007-add-layout-presets/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── elisp-surface.md
└── checklists/
    └── requirements.md
```

`tasks.md` belongs to the later task-generation command and is not an output of this command.

### Source Code (repository root)

```text
claude-code-ide-manager.el         # Presets, windows, shell ownership, saved state
claude-code-ide-session.el         # Ordinary Ghostel creation and liveness helpers
claude-code-ide-remote-project.el  # Captured requests, providers, admitted preparation
claude-code-ide-tests.el           # Behavioral ERT coverage and affected existing tests
README.org                        # Current manager and remote-view user documentation
CONTEXT.md                        # Layout and companion glossary
scripts/compile-and-test.sh        # Existing required gate, not a feature change
```

The existing `claude-code-ide.el` cleanup path is an integration reference.
Use its manager Session-end callback rather than duplicate cleanup in Agent-specific code.
Change that source only if implementation finds a missing shared callback, with a targeted regression check.
No Ghostel native source or RPC transport source change is required by this design.

**Structure Decision**: Extend existing shared modules and their current state ownership.
Do not create a standalone layout framework, a second remote scheduler, or a companion process persistence service.

## Complexity Tracking

No constitution exception is proposed.
The failing repository gate is an unresolved error, not a justified deviation.

The provider descriptor in the existing remote view key serves a current requirement: a Dired request cannot reuse a cached Magit view.
The separate runtime shell table is necessary because reset removes the saved layout before rebuilding it.
Neither mechanism is preparation for future arbitrary layouts.

## Phase 0: Research Outcomes

| Question | Decision | Evidence |
| --- | --- | --- |
| Preset selection | One `defcustom` plus a fixed descriptor alist | [R1](research.md#r1-use-one-preference-and-six-fixed-descriptors) |
| Session ownership | Canonical Session ID to exact shell buffer, runtime only | [R2](research.md#r2-separate-shell-ownership-from-saved-window-state) |
| Shell creation | Ordinary `ghostel-create`, nil display action, caller-owned reuse | [R3](research.md#r3-create-ordinary-shells-through-ghostels-existing-interface) |
| Exited output | Respect `ghostel-kill-buffer-on-exit` | [R4](research.md#r4-preserve-ordinary-ghostel-exit-behavior) |
| Saved layout recovery | Native window state plus companion metadata, no automatic shell fallback | [R5](research.md#r5-reuse-native-window-state-restoration) |
| Removal and disconnect | Release on end/removal, retain on temporary remembered disconnection | [R6](research.md#r6-release-shells-on-removal-retain-them-on-disconnection) |
| Remote transport | Admitted RPC-qualified path, existing client PTY policy | [R7](research.md#r7-use-admitted-rpc-paths-not-a-second-package-level-transport) |
| Remote shell preference | Ghostel method/catch-all/connection-local resolution | [R8](research.md#r8-preserve-remote-shell-preferences-without-local-substitution) |
| Provider reuse | Preserve location semantics, add provider descriptor, keep shells unshared | [R9](research.md#r9-distinguish-companion-providers-from-remote-location-identity) |
| Async ownership | Capture layout request and verify it at publication | [R10](research.md#r10-capture-request-intent-before-asynchronous-work) |
| Verification | Exact repository gate plus behavioral and live checks | [R11](research.md#r11-keep-verification-honest) |

A native window-state experiment ran in disposable batch Emacs.
After the companion buffer was killed, restoration kept the Agent window and did not recreate the companion buffer.
This is evidence for the current Emacs 31.1.50 runtime, not a claim that minimum-version testing has completed.
No remote connection or feature acceptance scenario ran during research.

## Phase 1: Design

### A. Resolve one layout request

Add `claude-code-ide-manager-layout-preset` with the six values and `magit-left` default.
Resolve it to companion kind and side through a private fixed alist.
Capture the Git provider and exact Session directory at the same point.
Validate invalid values before deleting saved layout state or allocating a companion.

Remove `claude-code-ide-manager-session-window-side` from its declaration and both production split decisions.
Do not add an alias or use the old value as a fallback.
Keep `claude-code-ide-manager-status-buffer-function` only on the Git path.
The existing `R` command and manager reset entry point remain the application mechanism.

The descriptor is a request snapshot, not a dynamically reread preference.
Preference changes alone do not mutate saved layouts or pending requests.
An explicit reset creates a new snapshot and supersedes the prior action.

### B. Keep the Agent usable before companion work

The manager resolves the exact live target Agent and preserves its buffer/process.
Establish an ordinary content window for that Agent using existing manager window behavior.
Check a local split before starting a new shell when possible.
A missing dependency, bad directory, invalid preset, or failed split must not leave the target inaccessible.

Choose the companion source from the captured descriptor:

- Git: invoke the captured configured provider with the Session directory and retain the existing Dired fallback.
- Dired: call `dired-noselect` for the exact Session directory, independent from the Git provider.
- Shell: reuse the Session's live shell or create one only when the request permits creation.

Use shared content-side and focus policy for local construction and delayed remote display.
The remote display function must stop reading the old side preference.
Its existing host, attachment, and frame checks must remain in place.

### C. Isolate Ghostel details in the Session layer

Add two private Session-layer operations: create an ordinary companion shell for a directory, and test whether a supplied shell buffer is live.
Creation uses a unique ordinary terminal name and `ghostel-create` with nil display action.
Do not call Agent terminal setup, apply Agent environment injection, or attach a zmx Session.
Do not scan Ghostel terminal slots or directory names to establish ownership.

Soft-load Ghostel only at creation time and report a missing creation interface or native module.
Preserve ordinary local and remote shell preferences and initial input mode.
A startup error after allocation must not destroy the Agent window.
A partial buffer without a live process can be removed if the request created it.
If a shell already runs but cannot be published, leave it as an ordinary terminal and report its buffer.

The manager owns `claude-code-ide-manager--companion-shells`, keyed by canonical Session ID.
This table survives layout reset but does not survive manager state serialization.
Session-end cleanup releases entries without killing shell buffers or processes.
The existing retained-remote-row branch preserves an entry across temporary disconnection.

### D. Extend saved state without persisting processes

Add the optional metadata in [the saved layout model](data-model.md#4-saved-layout-record).
Record the applied preset when building or resetting a layout.
Later capture copies that applied metadata instead of reading the current default.

The only shell ownership authority is the runtime Session table.
Persisted names are advisory window references, not instructions to recreate or adopt a process.
Filter `:shell-buffer` from persistence alongside the existing memory-only Project-view fields.
Keep plain preset/kind/name metadata to recognize missing saved shells after restart.
Old records without those fields retain their existing native layout semantics.

During restoration, substitute a renamed owned shell's current name before calling native `window-state-put`.
Prevent a missing saved shell name from selecting an unrelated buffer that reused that name.
Use the existing substitution pattern rather than invent a new window-state representation.
An exited buffer can show output, but must not count as a live shell.

The handled missing/exited-shell recovery returns a usable Agent window.
The public switch path must not then fall through to default-layout shell creation.
If another restoration problem occurs for a saved shell layout, use Agent-only recovery with reset guidance rather than an automatic process launch.
An ordinary return to a non-shell layout keeps existing fallback behavior for unrelated restoration failures.

Preserve the saved selected window for remote layouts when it remains valid.
The current remote restoration branch always favors the Agent, so this is an explicit implementation change.
After delayed companion preparation, preserve whatever window the user currently selected.

### E. Extend the existing admitted remote request

Pass the captured request as the required final argument to Session-managed `claude-code-ide-remote-project-prepare`.
Update its declaration, manager preparation helper, all three manager call paths, and affected tests together.
The public explicit-target interface and its callback payload stay unchanged.

The remote worker retains its existing client checks, health deadline, host admission, cancellation, and main-thread completion.
Git/Dired preparation creates or reuses a provider-aware Project view.
Shell preparation calls the Session-layer ordinary shell operation with the qualified directory, without selecting windows.
It must not enter the global Project-view registry or native Magit/Dired lookup.

Capture the request on the existing attempt and frame intent.
Before publication, verify current attempt, admitted host, Session ID, attachment, frame epoch, preset/provider/directory, and creation permission.
Retain the existing user-dismissal suppression rule so navigation does not reopen a deliberately hidden companion.
A reset clears suppression through the current reset mechanism.

Existing automatic `replacement` and reattach paths need special care.
For a saved shell layout, they may recover the existing live companion but may not start a replacement process.
Only a genuine new default layout or explicit shell reset grants creation permission.

A superseded request cannot publish into a newer layout.
If it already started a shell, preserve that terminal without adopting it into the newer request.
Do not close an RPC connection during cancellation or Session removal.
The underlying RPC client can use direct SSH PTYs or RPC PTYs according to its existing preference.

### F. Make remote view reuse provider-aware

Keep the location key semantics from `--resolve-view-key`.
The second field remains a location classification, not a preset kind.
Append the provider descriptor defined in [data-model.md](data-model.md#6-shared-remote-project-view-key).

Migrate every runtime constructor and consumer to the new shape in one change:

- Session-managed and explicit-target key construction.
- Native view lookup and provider invocation.
- Shared writer claims and completion registration.
- Surviving-view and saved-view validation.
- Cleanup, Worktree reconciliation, and matching tests.

A Dired request cannot accept a Magit buffer from native lookup.
Custom providers receive the captured requested Session directory rather than an implicitly substituted Worktree root.
The provider descriptor prevents results for different requested directories or functions from colliding.

Different descriptors can still lead native functions to return one buffer.
Cleanup must retain that exact buffer while another registered owner uses it.
Keep the existing protections for modified, preexisting, custom, source-file, process, and uncertain buffers.
Do not introduce automatic deletion of ordinary shell buffers into Project-view cleanup.

### G. Update behavior tests and user documentation

Use existing ERT helpers and isolated optional-dependency fixtures.
Exercise observable windows, selected buffers, directory identity, process identity, and failure results.
Do not test source text, implementation field copying, or mock argument echoes as the feature contract.
Replace the old side-preference behavior test with preset orientation and cutover behavior.

New tests must defend plausible failures, especially:

- Same-directory Sessions accidentally sharing a shell.
- Reset losing the runtime shell reference when it discards the saved layout.
- A missing or renamed shell resolving to the wrong buffer.
- A normal return starting a replacement shell.
- An old async request displaying the wrong provider or orientation.
- Dired receiving cached Magit content.
- Cleanup killing a shared native view or a live companion shell.
- Remote restoration losing the saved selected window.

Update `README.org` sections for CC Manager, per-Session layouts, configuration, and optional remote Project views after implementation.
Update affected explanatory details in `docs/remote.org` if the preparation contract changes their claims.
The glossary already records the agreed layout and companion meanings.
No new ADR is needed for these reversible extensions to existing ownership and preference rules.

## Delivery Order and Shared Contracts

1. Implement the fixed preset descriptor, Session-layer shell operations, and runtime shell ownership.
2. Integrate local build/reset/capture/restore using those established contracts.
3. Extend remote request snapshots and provider-aware view keys using the same descriptor and ownership model.
4. Integrate remote result publication, suppression, cleanup, and focus preservation.
5. Complete behavioral tests, documentation updates, the full gate, and live validation.

The shared contracts are the descriptor values, captured layout request, Session-keyed shell table, and remote result variants in the data model.
Do not change those interfaces independently across files.
The remote key migration and all its consumers form one integration boundary.
This ordering is implementation guidance, not a generated `tasks.md` checklist.

## Requirement Coverage

| Requirements | Planned implementation and proof |
| --- | --- |
| FR-001–FR-004 | Fixed six-preset preference, old-side cutover, temporary Git provider. Six visible layouts and provider-isolation checks. |
| FR-005–FR-006 | Ordinary Ghostel creation and exact local/RPC directory. Shell PID, directory, and unchanged Agent checks. |
| FR-007–FR-009 | Applied-layout metadata, native restoration, explicit creation permission, selected-window policy. Saved/missing/exited/renamed shell and focus checks. |
| FR-010–FR-012 | Git-only Dired fallback and explicit dependency/startup/split errors. Agent usability checks. |
| FR-013–FR-014 | Admitted remote worker, captured publication, existing disabled behavior. Approved/disabled/failed and stale-result checks. |
| FR-015 | Shared manager and Session seams with no Agent-specific branches. Available Agent/backend matrix. |
| FR-016 | Direct Dired provider and provider-aware remote lookup. Exact directory and no-Ghostel/no-Magit checks. |
| FR-017 | Session-end release and retained-disconnect handling. Live shell survives removal, reattachment retains identity. |

The runnable post-implementation scenarios are in [quickstart.md](quickstart.md).

## Phase 1 Completion and Verification

Generated artifacts:

- [Research decisions](research.md).
- [Data model](data-model.md).
- [Elisp and interaction contract](contracts/elisp-surface.md).
- [Quickstart validation guide](quickstart.md).

Document validation passed for seven feature artifacts and 68 local links, including linked Markdown headings.
The specification retains all 17 functional requirements, eight success criteria, and four accepted clarification answers.
The research, data model, contract, and quickstart agree on all six preset values.
No unresolved technical marker remains. The specification checklist remains 16/16, with no checkbox changes.

The final planning run of `./scripts/compile-and-test.sh` exited with code 1.
Byte compilation passed with warnings. ERT reported 915 tests, 896 expected results, ten unexpected results, and nine skipped tests.
The same ten Magit-dependent tests failed. Feature behavior and minimum-version compatibility have not been tested because implementation has not started.

No extension registry exists, so no before-plan or after-plan hook required execution.
The working tree contains documentation changes only, on `main`. This command made no commit.

The next normal workflow command is `/speckit.tasks` after the design is accepted.
The repository gate error remains unresolved and must not be carried forward as a passing acceptance result.
