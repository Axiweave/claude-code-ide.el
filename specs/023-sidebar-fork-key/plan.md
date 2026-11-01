# Implementation Plan: Fork a Session from the Sidebar with `S`

**Branch**: `main` (spec dir `023-sidebar-fork-key`) | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/023-sidebar-fork-key/spec.md`

## Summary

`S` in the manager sidebar sends the APC packet `ESC _ pi:action;fork-spawn ESC \` to the omp of the Session on the selected row. omp reads the packet in its Composer input listener, which already consumes every `pi:` packet before the editor sees it. So A's draft does not change. Composer passes the action name to a new `onAction` field. InteractiveMode sets that field after it adopts the Composer, and runs `handleForkSpawnCommand(false)`. The `false` skips the busy-turn question. A dialog that owns input blocks the fork with a warning. B is created and announced as in spec 022, and Emacs attaches it with no new package code. The old permissions-bypass start leaves the sidebar.

## Technical Context

**Language/Version**: Emacs Lisp (Emacs 28.1+) in this package. TypeScript on Bun in omp (`packages/tui`, `packages/coding-agent`).

**Primary Dependencies**: Ghostel (terminal input), zmx (Session transport), the `pi:` packet family, and the spec 021/022 spawn path.

**Storage**: N/A.

**Testing**:
- ERT in `claude-code-ide-tests.el`, through `./scripts/compile-and-test.sh`.
- `bun test` in omp: `test/spawn-command.test.ts` (InteractiveMode harness, input through `mode.ui.injectDebugInput`, plus one case that passes a prebuilt, started Composer to the constructor, and one case with two packets back to back) and `test/modes/composer-editor-handoff.test.ts` (Composer with a VirtualTerminal).
- Full omp gate: `bun run check` and `bun run test` in `packages/coding-agent`.

**Target Platform**: macOS and Linux hosts that run omp inside zmx under Emacs/Ghostel, local and remote.

**Project Type**: Emacs package plus a CLI agent (omp).

**Performance Goals**: B shows in the sidebar within 5 s on a local host (SC-002).

**Constraints**: No byte of the request reaches A's draft (FR-004). No new message and no model turn (FR-003). The packet must not answer a dialog (FR-011, FR-012).

**Scale/Scope**: about 15 changed lines in omp source, about 30 in the package, and the test changes.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Result |
|---|---|
| I. Shared Session Core, Thin Agent Adapters | Pass. The send uses the shared `claude-code-ide-session-send-omp-packet`. The omp-only check is one CLI-type test in the manager command. |
| II. Batch-Verifiable Quality Gate | Pass. New ERT tests mock the row buffer and the send. They need no display and no Ghostel. |
| III. Optional Dependencies Stay Optional | Pass. No new dependency or `require`. |
| IV. Ghostel-Only Terminal Support | Pass. The packet goes through the existing Ghostel send. |
| V. Simplicity and Compatibility | Pass. One packet kind, one Composer field, one manager command. One command and one argument are removed. |
| VI. Local and Remote Workflow Parity | Pass. The row buffer is the Ghostel attachment for local and remote rows, and omp creates B on A's host. No remote difference. |

Post-design re-check: still Pass. The design adds no module and no setting.

## Project Structure

### Documentation (this feature)

```text
specs/023-sidebar-fork-key/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── pi-action-packet.md
└── tasks.md             # /speckit.tasks
```

### Source Code

```text
claude-code-ide.el/                          # this repo
├── claude-code-ide-manager.el     # add claude-code-ide-manager-fork-at-point and bind S;
│                                  # remove ...-start-session-at-point-skip-permissions
│                                  # and the DANGEROUS argument of ...-start-session-at-point
├── claude-code-ide-transient.el   # dispatch "S" "Fork session"; declare-function updates
├── claude-code-ide-session.el     # send-omp-packet docstring names "action"
└── claude-code-ide-tests.el       # binding and dispatch mirror; fork-at-point cases;
                                   # delete the skip-permissions tests

~/agents/oh-my-pi/
├── packages/tui/src/prompt/composer.ts            # pi:action kind; onAction field
├── packages/tui/CHANGELOG.md                      # Composer.onAction
├── packages/coding-agent/src/modes/interactive-mode.ts
│                                  # set composer.onAction after adoption;
│                                  # handleForkSpawnCommand(confirmBusy = true);
│                                  # extract #inputOwnedByDialog() from #isSpeckitStartBlocked
├── packages/coding-agent/src/modes/types.ts       # handleForkSpawnCommand(confirmBusy?)
├── packages/coding-agent/test/spawn-command.test.ts
├── packages/coding-agent/test/modes/composer-editor-handoff.test.ts
├── packages/coding-agent/CHANGELOG.md             # pi:action;fork-spawn
└── UPSTREAM_DIVERGENCES.md                        # packet decision gets pi:action
```

**Structure Decision**: The package owns the key, the row checks, and the send. omp owns the packet and the fork. Each repo gets its own commit. omp goes to `fork/main`, the package to `origin/main`, and the parent gets a gitlink-only bump.

## Complexity Tracking

No violations.
