# Implementation Plan: zmx-backed persistent agent sessions

**Branch**: `001-zmx-sessions` | **Date**: 2026-08-28 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-zmx-sessions/spec.md`

## Summary

Add an opt-in mode (`claude-code-ide-use-zmx`) in which the agent CLI runs inside a zmx session instead of directly in the terminal buffer. Emacs wraps the built command as `zmx attach <name> <cmd>`, so the process survives buffer kills and Emacs exits, and any terminal can reattach. A new adapter file provides the zmx subprocess calls (`list`, `kill`, name handling). Session start offers eligible orphaned zmx sessions for reattach, and a new `claude-code-ide-attach` command adopts externally launched sessions. Decisions and trade-offs are recorded in `docs/adr/0001-zmx-backed-agent-sessions.md`.

## Technical Context

**Language/Version**: Emacs Lisp, Emacs 28.1+ (per `Package-Requires` in `claude-code-ide.el`)

**Primary Dependencies**: No new Elisp dependency. External optional binary: `zmx` (resolved via `executable-find` at point of use). Terminal backend: Ghostel.

**Storage**: None. zmx owns all session state; Emacs queries `zmx list` on demand.

**Testing**: ERT in `claude-code-ide-tests.el`, batch mode via `./scripts/compile-and-test.sh`. zmx subprocess calls mocked (no zmx binary in CI).

**Target Platform**: Local Emacs on macOS/Linux. TRAMP/remote zmx out of scope (spec Assumptions).

**Project Type**: Emacs package (flat single-directory layout).

**Performance Goals**: One `zmx list` subprocess call per session start (zmx mode on) and per `claude-code-ide-attach` invocation. No polling, no timers.

**Constraints**: Package must load, byte-compile, and pass tests without zmx installed (FR-009). Nil defcustom must preserve current behavior byte-for-byte (FR-001).

**Scale/Scope**: One new file (~150 lines), targeted edits in `claude-code-ide.el`, tests, README section.

## Constitution Check

*GATE: evaluated against `.specify/memory/constitution.md` v1.0.0.*

| Principle | Verdict | Evidence |
|---|---|---|
| I. Shared session core, thin adapters | PASS | Wrapping happens once in `claude-code-ide--create-terminal-with-command` (the shared seam all four agent builders funnel into), not per agent. zmx control calls live in one adapter file. No agent-specific fork. `claude-code-ide-agent-definitions` untouched. |
| II. Batch-verifiable quality gate | PASS | New logic ships with ERT tests; zmx calls go through one function that tests override, like the existing websocket mocks. `./scripts/compile-and-test.sh` is the gate. |
| III. Optional dependencies stay optional | PASS | zmx is an external binary, not an Elisp package: no `require` at all. Missing binary raises `user-error` naming zmx at point of use (FR-009). |
| IV. Ghostel-Only Terminal Support | PASS | The wrapper changes the command string before Ghostel creates the terminal. All Agents share this path. |
| V. Simplicity and compatibility | PASS | No new runtime dependency. `refs/emacs-term-sessions` is reference-only, not vendored. Emacs 28.1 APIs only (`executable-find`, `process-file`, `completing-read`). |

No violations. Complexity Tracking is empty.

*Post-design re-check (after Phase 1)*: PASS unchanged. The design added no new files beyond `claude-code-ide-zmx.el` and no agent-specific branches.

## Project Structure

### Documentation (this feature)

```text
specs/001-zmx-sessions/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── commands.md      # User-facing command/defcustom contract
└── tasks.md             # Phase 2 output (/speckit.tasks - not created here)
```

### Source Code (repository root)

```text
claude-code-ide-zmx.el        # NEW: zmx adapter (defcustoms, list/kill calls,
                              #      name scheme, parsing, availability check)
claude-code-ide.el            # EDIT: wrap command at the shared seam; reattach
                              #      offer; claude-code-ide-attach; stop = zmx kill
claude-code-ide-tests.el      # EDIT: ERT tests with mocked zmx calls
AGENTS.md                     # EDIT: add claude-code-ide-zmx.el to core files
README.md                     # EDIT: zmx mode documentation (if README exists)
```

**Structure Decision**: flat package layout, matching every existing `claude-code-ide-*.el` module. The adapter is a separate file so zmx never loads unless the feature is used, and `claude-code-ide.el` gains only the integration seams.

## Design outline

Integration points, all verified in source this session:

1. **Wrap seam**: `claude-code-ide--create-terminal-with-command` (claude-code-ide.el:1525) receives the final `cmd` string from every agent builder. With zmx mode on, replace `cmd` with `zmx attach <name> <split cmd>` (argv-quoted, as the reference implementation does). Env vars still flow through the terminal process's environment, so a newly created zmx session inherits them.
2. **Session identity**: `claude-code-ide--create-session` (claude-code-ide.el:1706) mints the session-id. Derive the zmx name there and store it in a new `zmx-name` slot on the `claude-code-ide-session` struct (claude-code-ide.el:409).
3. **Detach semantics**: already correct for free. Buffer kill hooks and `kill-emacs-hook` cleanup (claude-code-ide.el:1111-1119) kill only the local attach-client process; the zmx server and agent survive. Only `claude-code-ide-stop` (claude-code-ide.el:1866) changes: for a session with a `zmx-name`, prompt and run `zmx kill`.
4. **Reattach offer (FR-006)**: in `claude-code-ide--create-session`, when zmx mode is on and neither continue nor resume is set, list zmx sessions with the `<prefix><agent>-<project>-` prefix, subtract names present in `claude-code-ide--sessions`, and offer via `completing-read` with "create new".
5. **Adoption (FR-007/008)**: new command `claude-code-ide-attach` lists all zmx sessions, annotates with `start_dir`/`cmd`, infers CLI type by matching the command head against `claude-code-ide-agent-definitions` values and `claude-code-ide-cli-path`, then reuses the normal session-creation path with the attach command in place of a build.

## Complexity Tracking

No constitution violations; table intentionally empty.
