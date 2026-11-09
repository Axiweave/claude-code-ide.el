# Quickstart: validate feature 024

These steps prove the feature end to end on the user's Mac, with one remote host. The configuration shape is in [contracts/intake-config.md](contracts/intake-config.md). The requests are in [contracts/intake-http.md](contracts/intake-http.md).

## Prerequisites

- Bun 1.4, zmx 0.8.1, and `curl` on the Mac. zmx and an omp build that has `launch-session` on every launch host.
- Emacs with this package loaded and its server running (`emacsclient --eval t` prints `t`).
- `v12dev` is in `claude-code-ide-remote-hosts`, and `ssh -o BatchMode=yes v12dev true` works.
- A Linear test team, a personal API key, and a trigger label.

## Setup

```sh
mkdir -p ~/.config/cci-intake && umask 077
openssl rand -hex 32 > ~/.config/cci-intake/token
printf '%s\n' "$LINEAR_KEY" > ~/.config/cci-intake/linear-key
$EDITOR ~/.config/cci-intake/config.toml      # one project, hosts local + v12dev, one [[emacs]] "mac"
cd ~/agents/cci-intake && bun run src/main.ts
```

For pull mode, set these in your Emacs configuration. The client name must equal the `[[emacs]]` `name`. Otherwise the Intake refuses the stream with `400`.

```elisp
(setq claude-code-ide-intake-url "http://127.0.0.1:7311"
      claude-code-ide-intake-client "mac")
```

Use these shell helpers for the steps below:

```sh
T=$(cat ~/.config/cci-intake/token); I=http://127.0.0.1:7311
req() { curl -s -H "Authorization: Bearer $T" -H 'content-type: application/json' "$@"; }
```

## Scenarios

| # | Do | Expect | Covers |
|---|---|---|---|
| 1 | `req -X POST $I/v1/launches -d '{"project":"api","prompt":"Say hi"}'` | `202`, state `queued`. Within 15 s the list shows `running` with a `name`, and the Session row is in the Emacs manager. | Story 1.1, FR-027, SC-001 |
| 2 | Repeat 1 with `"host":"v12dev","worktree":{"branch":"qs-wt"}` | The row is under `v12dev` within 30 s. `git -C <path> worktree list` on `v12dev` shows `qs-wt`. The main checkout is unchanged. | Story 1.2–1.3, VI |
| 3 | Send the same body twice with `"key":"qs-1"` | The second call returns `200` with the same `id`. `zmx list` has one new session. | FR-024 |
| 4 | `req $I/v1/launches -H 'Authorization: Bearer wrong'` | `401`. Nothing is recorded. | FR-020, SC-005 |
| 5 | `zmx kill <name from 1>` by hand, wait 10 s, then list | Launch 1 is `ended`. | Story 3.2, FR-026 |
| 6 | `req -X POST $I/v1/launches/<id 2>/stop` | `200`, `ended`. The zmx session and the Emacs row are gone. The worktree stays. | Story 3.3, FR-029 |
| 7 | Start a Launch with a long prompt. While it works, send `…/input` twice with `mode` `queue` | Attach: both messages arrive once each, in order, after the turn ends. | Story 4.5–4.6, FR-031 |
| 8 | Repeat 7 with `"mode":"guide"`, then with `"mode":"stop"` | `guide` joins the running turn. `stop` ends the turn, then the text starts a new one. | FR-031 |
| 9 | Add the trigger label to a test issue as an allow-listed user | Within 90 s: one Session in a worktree on branch `<team>-<n>`, and one issue comment with the name and host. | Story 2.1, FR-055, SC-004 |
| 10 | While Launch 9 runs, remove the label and add it again. Restart the Intake between two polls | No second Session starts. The list shows one `refused` Launch with a reason that starts with `duplicate`. | Story 2.3, edge case "Same issue, label added again", SC-002 |
| 11 | On the issue from 9, post `/omp also update the README`, then a comment with no prefix | The Session gets `also update the README` as a follow-up. The comment with no prefix and the Intake's own comment from 9 are not delivered. | Story 4.1, 4.2, 4.4, FR-054 |
| 12 | Label an issue as a user who is not on the allow-list | No Session starts, and the issue gets no comment. The list shows a `refused` Launch with a reason that starts with `untrusted`. | Story 2.2, FR-028, FR-052 |
| 13 | Set `[[emacs]]` to an unreachable `ssh`, start Emacs with `claude-code-ide-intake-url` set and `(claude-code-ide-intake-mode 1)`, then repeat 1 | The push records `failed`. Emacs adopts the Session from the stream within 10 s, once. | FR-012, SC-007 |
| 14 | Restore push, keep pull on, run 20 Launches | Each Session appears once in the manager. | SC-007 |
| 15 | Count the package Sessions on the Mac as `N`. Set `max_sessions = N + 3` for `local`, then start 4 Launches | The count never goes over `N + 2`. The other Launches stay `queued` and start when a slot frees. | FR-025, SC-006 |
| 16 | End Launch 9 with `zmx kill <name>` by hand and wait 10 s, then add the label to its issue again | One new Launch starts on branch `<team>-<n>-2`. The branch and worktree from 9 do not change. | Edge case "Issue branch already exists", FR-055 |

## Results (2026-11-08 and 2026-11-09, Mac and `v12dev`)

| # | Result | Evidence |
|---|---|---|
| 1 | Pass | Launch `zl64jpa82at4omxd` was `running` as `cci-omp-cci-e2e-fggzsz` in about 2 s. Emacs had the Session row. |
| 2 | Pass | Remote Launches ran in `v12dev:~/wt/cci-e2e/launch-<id>`, and Emacs showed the rows under `v12dev`. The request needs `"worktree": {}`, an object. `true` gives `400`. |
| 3 | Pass | The second call returned `200` with the same `id`. |
| 4 | Pass | `401`. |
| 5 | Pass | After `zmx kill` by hand, the Launch was `ended` within 14 s. |
| 6 | Pass | `200` and `ended`. The zmx session and the Emacs row were gone. The worktree and the branch stayed. |
| 7 | Pass | Three `queue` follow-ups were `sent` and arrived once each, in order. |
| 8 | Pass | `guide` joined the running turn. `stop` ended a long turn, then the text started a new turn. |
| 9 | Pass | YU-8 was created with the label (creation Trigger). After 56 s the Launch was `running` on branch `yu-8`, and the issue had one comment with the name and host. |
| 10 | Pass | The label removed and added again gave one `refused` Launch with `duplicate: issue YU-8 has launch … in state running`. No second Session and no comment. The Intake restarted between earlier polls. |
| 11 | Pass | `/omp  Also reply with the single word PELICAN.` arrived without the prefix, and the Agent replied PELICAN. The comment with no prefix (WALRUS) and the Intake's comment were not delivered. |
| 12 | Pass | The user's ID was replaced in `allow` for the test. The label event gave `untrusted: actor … is not on the allow-list`, no Session, and no comment. |
| 13 | Pass | With `ssh = "cci-unreachable.invalid"`, the push recorded `failed`. Emacs adopted the Session from the stream in about 1 s, once. The first try adopted nothing: the client name was `(system-name)`, not `mac`. The Intake now refuses an unknown client with `400`, and Emacs shows "Intake refused …" with the option names (checked live). |
| 14 | Pass | Rerun with 20 local Launches and `max_sessions = 24` (N = 3). All 20 were `running` within 10 s. Each name was in the Emacs registry once, and `zmx list` showed `clients=1` for each. 11 pushes failed with "emacsclient: can't connect … Connection refused" under the load, 9 returned `skipped`, and the stream adopted every Session. An earlier run of 15 Launches (12 local, 3 `v12dev`) also gave each Session once. |
| 15 | Pass | Local: N = 3 and `max_sessions = 6`. Of 4 Launches, 2 ran and 2 stayed `queued`. A count each second for 35 s never went over 5 (N + 2). After one stop, a queued Launch started, and Emacs adopted it once (`clients=1`). `v12dev` (N = 8, `max_sessions = 11`) gave the same result, also over an Intake restart. The adoption of the queued `v12dev` Launch was not checked. |
| 16 | Pass | After `zmx kill` and a new label event, one Launch started on `yu-8-2` as `cci-omp-yu-8-2-kxw6qx`. Branch `yu-8` did not change. |

Two defects found in this run were fixed, each with a test that fails before the fix:

- An adopt timer that ran while a remote file buffer was current read that buffer's connection-local `shell-file-name` (`/usr/bin/zsh`) and failed to start the local attach. `claude-code-ide--create-terminal-with-command` now reads the shell in the new buffer.
- An old label event on an issue that changed later became a Trigger. The label poll now ignores history nodes older than `cursor - 2 min` (research D14).

The Intake service runs the omp binary that its `PATH` finds. An older npm `omp` in `/opt/homebrew/bin` has no `launch-session`, so the configuration names the omp path in full.

## Test gates

```sh
cd ~/agents/cci-intake && bun test
cd ~/agents/oh-my-pi/packages/coding-agent && bun test test/session/sibling-spawn.test.ts && bun run check && bun run test
cd ~/.spacemacs.d-30/site-lisp/claude-code-ide.el && ./scripts/compile-and-test.sh
```

All three must pass with zero unexpected results (SC-008).
