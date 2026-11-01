# Quickstart: Fork a Session from the Sidebar with `S`

## Prerequisites

- omp with this feature on the local host and on the remote host (v12dev). On v12dev, use `git pull --ff-only` in the omp repo.
- The package loaded in the live Emacs with `~/bin/emacsclient --eval`.
- A scratch repo: `/tmp/cci-fork-key` locally and `/home/yufu/tmp/cci-fork-key` on v12dev.

## Gates

1. In `~/agents/oh-my-pi/packages/coding-agent`, run `bun run check`. Expect exit 0.
2. In the same directory, run `bun run test`. Expect 0 fail.
3. In the package repo, run `./scripts/compile-and-test.sh`. Expect 0 unexpected results.

## Live scenarios

| # | Steps | Expected |
|---|---|---|
| 1 | Local omp Session A with 2 exchanges. Sidebar, `S` on A. | Echo "Fork request sent to <A>". B row appears within 5 s with A's 2 exchanges. A and B have no new message. |
| 2 | Type `draft text` in A without Return. `S` on A. | B appears. A's input still shows `draft text` with the same cursor. |
| 3 | Start a long turn in A. `S` on A. | No question shows in A. B appears with the saved conversation. A's turn keeps running. |
| 4 | Open a dialog in A (for example `/model`). `S` on A. | A shows "Fork request ignored: close the open dialog first." No B. The dialog stays open. |
| 5 | Run `/spawn something` in A. During the spawn window, `S` on A. | The fork creates its B. The `/spawn` still creates its own B. |
| 6 | Vibe mode in A. `S` on A. | A shows "Exit vibe mode first." No B. |
| 7 | Remote omp Session on v12dev. `S` on its row. | B appears under the v12dev host with A's conversation. |
| 8 | `S` on a Claude row, on a disconnected row, and on a group header. | The matching user error in the echo area. No packet goes out. |
| 9 | `?` in the sidebar. | `S` shows "Fork session". No sidebar entry starts a Session with the permissions bypass. |
| 10 | `S` twice fast on A. | Two Bs. |

## Cleanup

1. End each B with `/despawn` in A, or stop it with `K` in the sidebar.
2. Remove both scratch repos.
3. Remove their `~/.omp/agent/sessions/*cci-fork-key*` folders.
