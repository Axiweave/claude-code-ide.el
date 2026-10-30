# Implementation Plan: Local Session Reattach

**Feature**: `019-local-session-reattach` | **Date**: 2026-10-29 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/019-local-session-reattach/spec.md`

## Summary

A local zmx-backed Session must stay in the manager as a disconnected row and survive an Emacs restart, as a remote row does. The remote path already has everything that this needs. The plan makes a local row "a remote row with host nil":

1. Key row retention on the zmx name instead of the host (R1). The persisted state already holds local rows, so nothing new is stored (R2).
2. Make one reattach function with an optional host. `c`, selection, and `a`/`A` all reach it, and `a`/`A` reuse the remembered Session ID (R3, R4, R7).
3. Forget a local row when its zmx session is gone: on client exit, at the first manager build, and on reattach (R5, R6).
4. Let Stop and detach work on a disconnected local row (R8). Count remembered orders so that new Sessions do not repeat them (R9).

## Technical Context

**Language/Version**: Emacs Lisp, Emacs 28.1+

**Primary Dependencies**: None new. zmx (optional external binary) and Ghostel (optional).

**Storage**: The existing `persist` manager state. No new key and no version bump.

**Testing**: ERT in `claude-code-ide-tests.el`, run by `./scripts/compile-and-test.sh`. zmx is mocked at `claude-code-ide-zmx--call` and `claude-code-ide-zmx-list-sessions`.

**Target Platform**: Emacs on macOS and Linux with a local zmx server.

**Project Type**: Emacs package (single project)

**Performance Goals**: At most one local `zmx list` call for each client exit, for each reattach, and for the first manager build in an Emacs instance.

**Constraints**: No zmx call at package load. A missing or failing zmx never removes a row. The remote behavior does not change (FR-017).

**Scale/Scope**: About 80 changed lines in 2 source files, plus tests and docs.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Result | Evidence |
|---|---|---|
| I. Shared Session Core | Pass | The changes are in the shared Session and manager layers. No Agent adapter changes |
| II. Batch-Verifiable Gate | Pass | ERT mocks zmx at its two existing entry points. No display, no Ghostel, no zmx binary needed |
| III. Optional Dependencies | Pass | No new `require`. zmx stays optional, and `claude-code-ide-zmx--ensure` gives the error at the point of use |
| IV. Ghostel-Only Terminal | Pass | Reattach uses the existing Ghostel terminal path |
| V. Simplicity | Pass | No new struct slot, state key, or dependency. One option is renamed, and four functions lose their `remote` prefix after a cutover. One reattach function replaces a remote-only one |
| VI. Local/Remote Parity | Pass | This feature brings local up to remote. The required differences and their constraints: (a) local rows are checked at startup and remote rows are not, because remote checks need SSH to each host (R6). (b) Local verification is synchronous and remote is asynchronous, because a local list has no network deadline (R5) |

Post-design re-check: Pass. Phase 1 added no violation.

## Project Structure

### Documentation (this feature)

```text
specs/019-local-session-reattach/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── elisp-surface.md
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit.tasks
```

### Source Code (repository root)

```text
claude-code-ide.el           # cleanup-on-exit, verify, reattach-target, attach-zmx-entry,
                             #   live-session-for-target, create-session/-local-session,
                             #   next-session-order, stop/stop-local-session
claude-code-ide-manager.el   # remember-session, build-items (+ startup check),
                             #   session-ended, visible-name, help-echo, navigate message,
                             #   ensure-live-target, reattach/detach-at-point, option rename
claude-code-ide-tests.el     # local lifecycle tests; rename symbols in remote tests
README.org                   # disconnected rows are no longer remote-only
docs/remote.org              # selection reattach wording
CONTEXT.md                   # "Disconnected session" covers local zmx Sessions
```

**Structure Decision**: Single Emacs package. All files are at the repository root. No new file.

## Design Notes

- **Order in `--cleanup-on-exit`**: remember the row, remove the Session from the registry, clean up the resources, then verify a local row (R5). The verify step needs the Session to be gone from the registry. Otherwise its "live again" guard cancels the check.
- **Detach after R1**: a buffer kill now keeps a local zmx row. So `detach-at-point` must call `session-ended KEY t` for every row, not only for remote rows.
- **Stop for a stub Session**: `--stop-local-session` must not call `kill-buffer` with a nil buffer. That call kills the current buffer.
- **Uncommitted work**: the working tree already has the remote auto-reattach option and its tests. This feature renames that option and builds on it. Commit them together, or commit the remote change first and the rename after it.
- **ADR**: `docs/adr/0001-zmx-backed-agent-sessions.md` makes zmx own the process. This feature agrees with it, and no new ADR is needed.

## Complexity Tracking

No violations.
