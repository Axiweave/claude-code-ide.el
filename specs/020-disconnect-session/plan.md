# Implementation Plan: Disconnect Session

**Branch**: `020-disconnect-session` | **Date**: 2026-10-31 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/020-disconnect-session/spec.md`

## Summary

Add Disconnect: `d` in the manager and `M-x claude-code-ide-disconnect` for the current buffer. Disconnect closes the terminal client of one zmx-backed Session, and the row stays as a Disconnected session row.

Disconnect adds no new lifecycle path. It is a set of guards in front of the existing buffer-kill path. A buffer kill runs the buffer's `kill-buffer-hook`, and the hook calls `claude-code-ide--cleanup-on-exit`. Since spec 019, `--cleanup-on-exit` remembers a zmx-backed row for local and remote Sessions. Disconnect does not copy `claude-code-ide-manager-detach-at-point`, because detach removes the row (`session-ended KEY t`, `claude-code-ide-manager.el:5618`) and runs Project-view cleanup (line 5616).

The guards are the value of the feature. A buffer kill on a Session that does not run in zmx ends its Agent. Disconnect refuses that Session and every other case where the result is not a kept row (see [research.md](research.md) R2).

## Technical Context

**Language/Version**: Emacs Lisp, Emacs 28.1+ (`Package-Requires`)

**Primary Dependencies**: none new. Ghostel and zmx are optional and stay optional.

**Storage**: the existing manager state file. Disconnect changes no stored format.

**Testing**: ERT in `claude-code-ide-tests.el` through `./scripts/compile-and-test.sh`. Reuse the `claude-code-ide-tests--with-local-targets` and `claude-code-ide-tests--with-remote-targets` fixtures.

**Target Platform**: Emacs on macOS and Linux, with local and remote zmx.

**Project Type**: Emacs package (single project, files at the repository root).

**Performance Goals**: no network request. A local disconnect makes one local `zmx list` call, which the spec 019 buffer-kill path already makes.

**Constraints**: no new row state. No new window rules. No Project-view cleanup. `D`, `X`, `K`, `c`, `a`, and `A` do not change.

**Scale/Scope**: two commands, one key, one menu entry, docs. About 40 lines of code.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Result | Evidence |
|---|---|---|
| I. Shared Session Core | Pass | The core command lives in `claude-code-ide.el` next to `claude-code-ide-stop`. It has no Agent-specific code. The manager command only resolves the row at point. |
| II. Batch-Verifiable Gate | Pass | New ERT tests use the existing mocked fixtures. They need no display, Ghostel, or zmx. |
| III. Optional Dependencies | Pass | No new `require`. |
| IV. Ghostel-Only | Pass | Disconnect kills the live Session buffer. It adds no terminal code. |
| V. Simplicity | Pass | It reuses the buffer-kill path and adds no row state and no dependency. Nothing becomes obsolete. |
| VI. Local/Remote Parity | Pass | One code path for both. Only difference: the pending-request guard applies to remote rows, because only remote targets have in-flight requests (R4). The spec 019 local zmx check after the kill is existing behavior. |

Post-design re-check: Pass. The design in [data-model.md](data-model.md) and [contracts/elisp-surface.md](contracts/elisp-surface.md) adds no state and no dependency.

## Project Structure

### Documentation (this feature)

```text
specs/020-disconnect-session/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── elisp-surface.md
└── tasks.md             # /speckit.tasks output
```

### Source Code (repository root)

```text
claude-code-ide.el            # claude-code-ide-disconnect (autoload, interactive, optional SESSION-ID)
claude-code-ide-manager.el    # claude-code-ide-manager-disconnect-at-point, `d' binding
claude-code-ide-transient.el  # `d' in the manager dispatch, declare-function
claude-code-ide-tests.el      # disconnect tests
README.org                    # manager key list, zmx lifecycle bullets
docs/zmx.org                  # "Detach and Stop" table
docs/remote.org               # manager key table
CONTEXT.md                    # "Disconnect" glossary entry next to "Detach"
```

**Structure Decision**: single Emacs package at the repository root. The feature touches the files above only.

## Implementation Notes

- **Order in `claude-code-ide-disconnect`**: resolve the Session, run the guards, kill the buffer, then call `--cleanup-on-exit KEY t` if the Session is still registered. The second step covers a Session without a kill hook. After the kill, a live buffer means a kill query refused the kill. Report it and stop.
- **Point**: `session-ended` without FORGET keeps `:selected-session-key`. The manager command still calls `--sync-point-to-session-key` after the disconnect, as detach does for its survivor.
- **Active Session**: `session-ended` clears `:active-session-key` for the ended key. This is the existing buffer-kill behavior. Disconnect activates no other Session (FR-017).
- **Spec 019 dependency**: commit `a19f021` is in the tree. Without it, a local buffer kill removes the row.

## Complexity Tracking

No violations.
