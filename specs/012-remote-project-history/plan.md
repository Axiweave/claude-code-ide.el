# Implementation Plan: Remote Project History

**Branch**: `[012-remote-project-history]` | **Date**: 2026-09-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/012-remote-project-history/spec.md`

## Summary

Persist a bounded, per-host recent repository list inside the manager's existing state. Explicit remote open always asks for a host and then offers remembered repositories plus manual absolute-path entry. Ordinary open keeps its current contextual behavior. Record a target only after the remote Worktree request accepts it synchronously.

## Technical Context

**Language/Version**: Emacs Lisp with lexical binding; Emacs 28.1+

**Primary Dependencies**: Existing `persist`, `transient`, `cl-lib`, and package-owned remote Worktree modules. No new dependency.

**Storage**: Existing `persist.el` storage for `claude-code-ide-manager--persisted-state`

**Testing**: Batch ERT in `claude-code-ide-tests.el`; full gate through `./scripts/compile-and-test.sh`

**Target Platform**: Emacs 28.1+ on supported local systems with user-configured SSH destinations

**Project Type**: Emacs package

**Performance Goals**: Render a repository picker from local state without remote I/O; process at most 20 choices for the selected host

**Constraints**: No user configuration for history persistence; no remote I/O during restore or picker rendering; exact host approval; plain host-local path metadata; optional dependencies remain optional

**Scale/Scope**: At most 20 remembered repositories per configured host; one interactive user; existing manager state versions remain readable

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Pre-Research Gate

- **Shared Session Core, Thin Agent Adapters**: PASS. The feature changes manager selection and state only. It does not add Agent-specific behavior.
- **Batch-Verifiable Quality Gate**: PASS. The plan adds headless ERT coverage and requires the full compile-and-test gate.
- **Optional Dependencies Stay Optional**: PASS. The feature reuses existing dependencies and does not add a hard requirement.
- **Ghostel-Only Terminal Support**: PASS. The feature does not change terminal construction or interaction.
- **Simplicity and Compatibility**: PASS. The design adds one persisted field and extends existing manager functions. It targets Emacs 28.1 and adds no dependency.
- **Local and Remote Workflow Parity**: PASS. The explicit remote command gains a project chooser comparable to local project selection. The required remote difference remains exact configured-host selection and absolute host-local metadata.

### Post-Design Gate

- **Shared Session Core, Thin Agent Adapters**: PASS. The command contract stays in the manager module.
- **Batch-Verifiable Quality Gate**: PASS. The quickstart and test design cover picker behavior, persistence, restart restore, and no-I/O guards.
- **Optional Dependencies Stay Optional**: PASS. Contracts introduce no new package or transport.
- **Ghostel-Only Terminal Support**: PASS. No terminal interface changes.
- **Simplicity and Compatibility**: PASS. MRU order uses list position rather than timestamps or a new model layer. Standard completion handles selection.
- **Local and Remote Workflow Parity**: PASS. Explicit selection and contextual fast paths remain distinct. Host approval and remote failure isolation remain unchanged.

No gate violation requires complexity tracking.

## Project Structure

### Documentation (this feature)

```text
specs/012-remote-project-history/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── remote-project-picker.md
└── tasks.md
```

`tasks.md` is created by `/speckit.tasks`, not by this planning phase.

### Source Code (repository root)

```text
claude-code-ide-manager.el       # Picker, MRU state, serialization, restore, explicit/contextual commands
claude-code-ide-tests.el         # Headless behavior and persistence regression coverage
README.org                       # User-facing Remote Worktree command and history behavior
docs/remote.org                  # Remote selection, persistence, safety, and troubleshooting details
```

**Structure Decision**: Keep the feature in the existing manager module because that module already owns remote project selection and persisted manager state. Do not create a new source module.

## Phase 0: Research Decisions

Research is consolidated in [research.md](research.md).

1. Reuse the manager's existing persisted state.
2. Add an ordered per-host history field without changing existing field meanings.
3. Validate and bound history during record and restore.
4. Use standard completion that accepts non-candidate absolute paths.
5. Make explicit remote open always prompt while ordinary open remains contextual.
6. Record after synchronous remote Worktree request acceptance.

All Technical Context questions are resolved. No `NEEDS CLARIFICATION` markers remain.

## Phase 1: Design

### Manager State

Add an in-memory per-host MRU alist. Extend manager serialization with `:remote-repositories`. Restore missing history as empty. Normalize restored values without local file predicates or remote calls. Include the field in empty/reset state so disabling or clearing manager persistence removes it through the existing lifecycle.

### Repository Selection

Replace the raw repository prompt with a host-scoped picker. Build remembered candidates as values, not parsed display strings. Allow standard minibuffer input for a new absolute path and retry until the input is valid or the user cancels.

### Command Behavior

Change `claude-code-ide-manager-open-remote` to select a host and repository regardless of point or `default-directory`. Keep `claude-code-ide-manager-open` and its remote-context helper unchanged for contextual use.

### Request Acceptance and Recording

Have the manager request wrapper call `claude-code-ide-remote-worktree-request`. If it returns an operation ID, update the host MRU and save manager state. If validation signals or the user cancels, do not mutate history.

### Tests

Add focused ERT coverage for:

- remembered selection and non-candidate absolute-path input;
- host isolation and paths containing spaces;
- MRU move-to-front, deduplication, and 20-entry limit;
- serialization and restart-style restoration;
- malformed restored state and unconfigured-host inertness without remote I/O;
- persistence disabled behavior;
- explicit remote open prompting from a remote row;
- ordinary contextual open preserving its current fast path;
- request refusal and prompt cancellation leaving history unchanged.

Replace `claude-code-ide-test-remote-worktree-manager-known-context-skips-prompts`
with an explicit-command regression that proves `claude-code-ide-manager-open-remote`
prompts from a remote row. Preserve
`claude-code-ide-test-remote-worktree-manager-open-prefers-rpc-context` as the
regression for contextual `claude-code-ide-manager-open`.

### Documentation

Update the Remote Worktree manager command table and remote guide. Explain that explicit remote open always asks for the host, offers recent repositories, accepts manual absolute paths, and persists history through manager persistence. State that selection and restore do not browse or contact the host.

## Design Artifacts

- [research.md](research.md): decisions and rejected alternatives
- [data-model.md](data-model.md): target identity, MRU rules, validation, and transitions
- [contracts/remote-project-picker.md](contracts/remote-project-picker.md): explicit and contextual command contracts
- [quickstart.md](quickstart.md): batch and end-to-end validation scenarios
