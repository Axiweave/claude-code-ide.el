# Invariants: Worktree Features (Local and Remote)

**Audited**: 2026-09-29, against the package, `scripts/remote-worktree-runner.sh`, the user config (`init-magit.el:1154-1629`, `site-lisp/magit-ww/magit-ww.el`), and the live Emacs.

**Scope**: `claude-code-ide-remote-worktree.el`, the runner script, the local Worktree code in `claude-code-ide-manager.el:3808-4420`, `claude-code-ide-remote-project.el:1830-2110`, `claude-code-ide-zmx.el:400-600`, the transient (`claude-code-ide-transient.el:705-738`), and the user Magit advice.

**Method**: 12 audit slices, then 8 adversarial verification slices. Each claim below survived verification or has a reproduction. The "Refuted" section lists claims that verification rejected.

Status values: **Holds**, **Fixed** (it failed, and the fix is in this change), **Open** (it can fail, and it has no fix yet).

## Operation lifecycle (Elisp)

| ID | Invariant | Status | Evidence |
| --- | --- | --- | --- |
| L1 | Every asynchronous callback runs at most once, and only for the current attempt. | Holds | `--current-p` checks the operation entry, `attempt-id`, and `generation` before each callback (`--control`, `--start`). |
| L2 | Every synchronous error during preparation reaches `--fail`. No operation stays in `preparing`. | Holds | `--control` wraps the callback in `condition-case`. `--start` wraps preparation. |
| L3 | A retry never replays a step that was entered, and every retry needs a fresh approval. | Holds | `--retry-ready` (`:3380`) rebuilds the plan. `--approved-p` checks the signature and `--launch-current-p` (`:225`). |
| L4 | A failed control request names the request. | **Fixed** | The message was "The control request failed with status N: STDERR" for all 16 control purposes. It now uses the purpose, for example "The worktree-merge-target request failed with status 1: …" (`:327-332`). |
| L5 | A retry after an Agent switch explains why it refuses. | **Open** (low) | `--retry-ready` reuses the old `:launch`. `--launch-current-p` rejects it, and the user sees only "The operation changed during confirmation" (`:1427`). |
| L6 | Retained operations have a bound. | **Open** (by design) | `--operations` is never pruned. `docs/remote.org` says that results stay until Emacs exits. |
| L7 | `--fail` clears `request`, and `--release` guards a double call. | **Open** (low) | No failure path depends on either today. |

## Remote preparation scripts (`/bin/sh -c`)

Every preparation script runs with `set -eu`. POSIX `set -e` ignores a failure of any command in an `&&` list except the last one. A final check such as `[ ! -e "$d" ] && [ ! -L "$d" ];` is therefore a no-op when the first test fails.

| ID | Invariant | Status | Evidence |
| --- | --- | --- | --- |
| P1 | Native move preparation refuses an occupied destination before confirmation. | **Fixed** | `--prepare-move` (`:2109`) ended with `[ ! -e … ] && [ ! -L … ];`. An existing file, directory, or dangling symlink passed. Git then failed only after confirmation, and the operation ended `unknown` instead of `refused`. The check is now an explicit `if … exit 1` with a diagnostic. Regression test: `claude-code-ide-test-remote-worktree-move-refuses-occupied-destination`. |
| P2 | The Agent program resolver accepts only an executable regular file. | **Fixed** | The resolver (`:1544`) had the same `&&` form. Under dash (the Linux `/bin/sh`), `command -v` of a directory path passed, and the launch used a directory as the program. Reproduced: dash exit 0 for `/tmp`. It now ends with `|| exit 1`. |
| P3 | A missing merge destination branch gives a diagnostic. | **Fixed** | The merge-target script (`:1991`) ran a bare `show-ref --verify --quiet`. It exited 1 with empty stderr. It now prints "No local branch NAME for the merge destination". Smoke-tested against a temp repo. |
| P4 | Shell values are passed as positional arguments and quoted with `zmx--quote`. | Holds | All `--control` callers pass argv lists. No value reaches the script text. |
| P5 | The publication preview does not publish. | Holds | `push --dry-run --porcelain --no-verify` with `credential.interactive=false` (`:2064`). |
| P6 | A Lane push uses `--force-with-lease --force-if-includes`. | Holds | Lane planner. |

## Runner (`scripts/remote-worktree-runner.sh`)

| ID | Invariant | Status | Evidence |
| --- | --- | --- | --- |
| R1 | A failed authority write leaves no temp file. | **Fixed** | `cci_atomic_kv` removed the temp file after a failed validation, but not after a failed `mv` (`:284`). Reproduced with a missing parent directory. The `mv` failure now removes the temp file. |
| R2 | A duplicate `run` executes a step once. | Holds | `mkdir "$CCI_PRIVATE_DIR/claimed"` (`:907`) is atomic. |
| R3 | `dispatch` does not wait for step completion. | Holds | `claude-code-ide-test-remote-worktree-dispatch-waits-for-owned-admission`. |
| R4 | The protection check reads live inventory, not the plan snapshot. | Holds | `cci_protect_inventory_check` (`:601`). |
| R5 | The Agent-protection boundary covers descendants but not same-prefix siblings. | Holds | Path checks compare `"$dir"/*`, not a bare prefix. |
| R6 | Concurrent operations on one host and repository are serialized. | **Open** | Nothing serializes them. The runner claims only a per-attempt directory. Git serializes each ref and index write with its own lock files. Each step re-checks its captured ref and worktree preconditions before it runs (`--render-plan`, `:966`). [INFERENCE] A conflicting interleave therefore fails a step and ends `unknown` with a diagnostic, and it does not corrupt state silently. Upgrade path: a `mkdir` lock per repository common dir in the runner admission. |
| R7 | The bootstrap name cannot change between check and use. | **Open** (uncertain) | A TOCTOU window exists at `:1014-1022`. It needs a second writer in the same private directory, which is mode 0700. |
| R8 | A truncated diagnostic says so. | **Open** (low) | The runner sends at most 64 KiB (`:1116`) and adds no marker. |
| R9 | A diagnostic with raw bytes above `#x10ffff` displays safely. | **Open** (low) | The decode (`:2454`) and `--display-text` keep raw bytes. Authority files reject them (`--parse-authority`). |

## Magit integration

| ID | Invariant | Status | Evidence |
| --- | --- | --- | --- |
| M1 | The package and the user config advise disjoint Magit commands. | Holds | The package advises `magit-worktree-move` and the push suffixes (`:4432-4441`), and the capture primitives only while it captures. The user config advises `magit-worktree-branch`, `magit-worktree-checkout`, `magit-worktree-delete`, and `magit-run-git` (prune). `magit-ww` routes only local buffers (depth -90). |
| M2 | Native capture does not depend on the statement order inside `magit-worktree-move`. | **Open** (fragile) | `--capture-native` (`:3957`) advises `magit-call-git`, `magit-run-git-async`, `magit-process-git`, and `file-directory-p`. It does not advise `expand-file-name` or `file-exists-p`. A Magit change that reads the file system before the Git call can capture the wrong argv or fail. |
| M3 | Push-suffix advice uses the current interactive form. | **Open** (low) | The interactive forms are read once at load time (`:4436-4441`). A later redefinition of a suffix is not seen. |
| M4 | The confirmation deferral has an upper bound. | **Open** (low) | The confirmation waits for the user with no timeout. The approval signature check still prevents a stale plan from running (L3). |

## Local Worktrees and the manager

| ID | Invariant | Status | Evidence |
| --- | --- | --- | --- |
| G1 | Manager render and refresh make no synchronous remote round trip. | Holds | Measured: 0 remote calls per render. Remote metadata is batched, at most 32 directories per batch (`zmx.el:383`). |
| G2 | Snapshots from different hosts do not mix. | Holds | The snapshot key is `(host dir backend)`. |
| G3 | The repository scope refreshes local branch metadata. | **Open** (partial) | Only the global scope refreshes it (`manager.el:2411`). |
| G4 | After a remote move, the Session `:directory` follows the Worktree. | **Open** (uncertain) | Not reproduced. |

## Performance

Measured in the live Emacs with 8 Sessions (3 local):

| Path | Cost |
| --- | --- |
| `--repo-worktree-directories` | 4.6 ms |
| `claude-code-ide-worktree-backend` | 5.5 ms |
| `--local-group-metadata` | 15-17 ms per directory, 9 calls (0.155 s) per global refresh |
| `target-for-file` | 1.5 µs |
| `--bounded-read` wait | Runs in the capture worker thread. The main thread does not block. |

Open performance items:

- PF1. For the wt backend, `--prepare-merge` reads the merge target, then the merge settings (`:1960`, `:1945`). The two reads are independent. A parallel read saves one round trip.
- PF2. `--read-extra-conditions` (`:2914`) sends its postcondition reads one after the other. They are asynchronous, so the UI does not block.

## Refuted claims

Verification rejected these first-pass claims. Do not report them again.

- A base64 padding mismatch. The second argument of `base64-encode-string` only drops line breaks.
- BSD `stat %Lp`, and `ps -o lstart` failures on macOS.
- A plan.sh TOCTOU. The runner re-validates the file after the claim.
- A weak token. It is the md5 of pid, time, sequence, and random data.
- Injection through the `eval` idiom or the Worktrunk default branch.
- Approval drift, a stale protection check, or an unprotected main Worktree.
- Wrong invalidation from the group key. The group key is for display only, and the view key is per directory.
- Symlink identity errors. Paths are canonical through `pwd -P` and `file-truename`.
- Confirm and cancel races, an orphaned observe timer, and a double-advice TOCTOU.
- Git-read quoting and sentinel parsing errors.

## Regression tests

- `claude-code-ide-test-remote-worktree-move-refuses-occupied-destination` (P1). It fails on the old code.
- `claude-code-ide-test-remote-login-environment-user-story-3-worktree-failure-refuses` now pins the named diagnostic (L4).
