# Quickstart: validate `/fork spawn`

## Prerequisites

- omp from `~/agents/oh-my-pi` main with this change. Use `omp-dev` locally and `omp` on v12dev.
- Emacs with claude-code-ide.el loaded, `claude-code-ide-cli-path` set to omp, and zmx on the path.
- A scratch git repo, for example `/tmp/cci-fork-spawn`.

## Automated gates

1. In `packages/coding-agent`, run `bun test test/spawn-command.test.ts test/slash-commands/fork.test.ts`.
2. Run `bun run check`, then `bun run test` in `packages/coding-agent`. Expect 0 failures (SC-006).
3. Run `./scripts/compile-and-test.sh` in this repo. Expect 0 unexpected results. This repo has no change, so this check only confirms the gate.

## Scenarios

| # | Do | Expect | Covers |
|---|---|---|---|
| 1 | Start A in Emacs, send two messages, then `/fork spawn` | Within 5 s, a new row `cci-omp-…`. Emacs shows B, B shows A's two messages, and B waits. | US1, FR-002, FR-004, SC-001, SC-002 |
| 2 | Read A's session file before and after scenario 1 | No new entry. A shows `Spawned <name>` only as a status line. | FR-003, SC-003 |
| 3 | `zmx list` | B's line has `cci-parent=<A name>`, `--fork <A's file>`, no `cci-wt-*`, and A's cwd | FR-005 |
| 4 | Set `spawn.confirm` to true, then `/fork spawn` | No confirmation. B is created. | Assumption |
| 5 | `/fork spawn extra` | Usage message. No new zmx session. | FR-010 |
| 6 | Run omp outside zmx, then `/fork spawn` | `Spawn failed: spawn needs a zmx session`. Nothing is created. | FR-007 |
| 7 | In a new A with no message yet, run `/fork spawn` | `Spawn failed: … no saved conversation yet`. Nothing is created. | FR-007 |
| 8 | While A works on a turn, run `/fork spawn` and answer No | Nothing is created. Answer Yes: B is created, and A's turn continues. | FR-008 |
| 9 | Run `/spawn x`, and while the model works, run `/fork spawn` | `/fork spawn` creates one B. The `/spawn` still creates its own B. | Edge case |
| 10 | `/despawn` in A after scenario 1 | B is in the list. Ending it removes its zmx session, row, and buffer. | US2, FR-011, SC-005 |
| 11 | Repeat scenario 1 from a remote A on v12dev | B appears under `@v12dev` with A's conversation. | US3 |

## Cleanup

Kill every test zmx session. Delete the scratch repo and its omp session folders under `~/.omp/agent/sessions/`.
