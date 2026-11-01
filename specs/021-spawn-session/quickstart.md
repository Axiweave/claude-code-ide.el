# Quickstart: Validate Spawn and Remove

## Prerequisites

- zmx 0.8.1 or later on every host.
- An omp build from the feature branch in `~/agents/oh-my-pi`.
- Emacs with this package and Ghostel loaded. Load new code with `~/bin/emacsclient --eval '(load-file "…")'`.
- One local omp Session A in zmx, shown in Emacs. For the remote checks, also use one Session on a host in `claude-code-ide-remote-hosts`.

## Automated gates

1. Run `./scripts/compile-and-test.sh` in this repo. Expect 0 unexpected results (SC-007).
2. Run `bun test` for the changed omp test files in `packages/coding-agent`. Then run `bun run check` and the full suite with `bun run test`. Expect all to pass (SC-007).

## Scenarios

| # | Do | Expect | Covers |
|---|---|---|---|
| 1 | In A: `/spawn write a README for the scripts directory` | Within 5 s, a new row `cci-omp-…`. Emacs shows B, and B starts work. A's conversation has one `Spawned …` tool result. | US1, FR-001, FR-004, FR-008, FR-012, SC-001 |
| 2 | `zmx list` | B's line has `cci-parent=<A name>` and `cmd=` with `@/…` and no prompt text. | FR-006, D7 |
| 3 | Set `claude-code-ide-switch-on-spawn` to nil, then spawn again | The row appears. The selected window and buffer do not change. | FR-013 |
| 4 | `/spawn fork this into a new session` | B shows A's history and waits for input. | FR-007 |
| 5 | `/spawn hand off the test fixes to a new session` | B starts from a summary. A has no compaction entry. | FR-007 |
| 6 | With uncommitted edits in A: `/spawn try the refactor in a new worktree` | B's `cwd` is a new worktree on a new branch that has A's edits. `git status` in A is unchanged. | FR-023 |
| 7 | Set `spawn.confirm` to true, spawn, then answer No | No zmx session, no row, no announcement. | FR-022 |
| 8 | Ask the model to spawn twice in one `/spawn` | One zmx session and one row. | SC-008 |
| 9 | After `/spawn`, a turn that only answers in text | The next turn's tool list has no `spawn_session`. | FR-002, SC-006 |
| 10 | Run omp outside zmx, then `/spawn x` | A refusal that names the reason. Nothing is created. | FR-020 |
| 11 | `printf '\e]52;e;"claude-code-ide-session-spawn-announce" "cci-omp-fake-zzzzzz"\e\\'` in a shell Ghostel buffer and in A | No attach and no error in the terminal. | FR-010, FR-011, SC-004 |
| 12 | In A: `/despawn`, pick B while B works, then confirm | The confirmation says "It is working on:" with the first line of B's current request. B's zmx session, row, and buffer are gone. | US3, FR-014–FR-016, SC-005 |
| 13 | Worktree child, `worktree.onExit=remove`, with an edit in B, then `/despawn` | The one remove confirmation shows the risk and offers "remove its worktree" and "keep its worktree". "Keep" ends B and keeps the worktree and branch. | FR-015, FR-024 |
| 14 | Detach A's Emacs, then `/despawn` a child | The child ends. Reattach shows no child row. | FR-017 |
| 15 | Repeat 1 and 12 on a remote host | The same result through the remote path. | Principle VI, FR-021 |
| 16 | In A: `/spawn start a session on <another provider/model> that reviews the diff` | B's `cmd=` has `--model <that model>`. Profile and thinking level match A. | Spec assumption on the model, research D6 |
| 17 | Spawn B. Then detach A with the manager and attach A again | The manager has one row for A and one row for B. No new buffer appears, and no second B row appears. | SC-003 |
| 18 | Set `ask.enabled` to false. In A: `/spawn take this somewhere else` | omp asks no question, and B starts in the mode that the model picked. With `spawn.confirm` on, the confirmation shows that mode first. | FR-003 exception, FR-022 |

## Cleanup

- `zmx kill` each test session that is left.
- `git worktree remove` each test worktree that is left, and delete its branch.
