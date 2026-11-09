# Implementation Plan: Master Session for Chat Dispatch

**Branch**: `025-master-session` | **Date**: 2026-11-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/025-master-session/spec.md`

## Summary

The Master Session is an Intake Launch of kind `master`. It runs on the Intake host, in a directory from the Intake's `[master]` configuration. `POST /v1/master` returns the one live master, or starts it with no host slot. The master works through a small `cci` command line in the Intake repository. `cci` sends a master-only token, and the Intake gives the origin `master` to each request with that token (D4). Each command makes one HTTP call: list projects, launch, list, read recent output (`zmx history`), send, and stop.

The Intake marks Sessions with two zmx labels:

- `cci-role=master` on the master.
- `cci-origin=master` on each worker that the master started.

Emacs reads these labels in the one function where every adopted Session decides whether to switch. So a worker from the master never takes the focus, and the open command shows the master.

omp adds a `cci-turn` counter next to `cci-state=idle`. The Intake writes a fixed-format Notice when a worker reaches a new turn, ends, fails, or is refused. It keeps one row for each worker, and sends the row to whichever master is ready. A Notice holds no worker text. The optional confirmation holds master Launches in a new `held` state until the user answers in Emacs. See `research.md` D1–D16.

## Technical Context

**Language/Version**: TypeScript on Bun 1.4 (the Intake, and omp `packages/coding-agent`). Emacs Lisp for Emacs 28.1+ (package).

**Primary Dependencies**:

- The 024 stack, with nothing added: `Bun.serve`, `bun:sqlite`, `Bun.TOML`, `Bun.spawn`.
- zmx 0.8.1: `list`, `set`, `send`, `history`. `ssh`, `emacsclient`, `curl`.

**Storage**: The Intake SQLite file gets `launches.kind`, `launches.notified_turn`, the state `held`, and a new `notices` table (`data-model.md`). There is no migration. The old database is deleted once (D16). The new zmx labels are `cci-role`, `cci-origin`, and `cci-turn`. The package gets two struct slots.

**Testing**:

- Intake: `bun test` with `FakeZmx`. It gains `zmx history` and keeps `--label` values. The seeded property tests print their seed: Notice coalescing and turn reset, the master single-instance race, and Notice text fields.
- omp: `bun test` for `launch-session` and the state publish, then `bun run check`, then `bun run test`.
- Package: ERT through `./scripts/compile-and-test.sh`. Tests cover the switch-rule table, the Master section, the open command with mocked `curl`, and the confirm command.

**Target Platform**: macOS for the Intake, the master, and Emacs. macOS and Linux hosts for the workers.

**Project Type**: Changes in three repositories: the Intake daemon and its new command line, the omp CLI and its state labels, and the Emacs package.

**Performance Goals**:

- SC-001: from request to manager row in less than 10 s on the local host.
- A Notice arrives one reconcile tick (10 s) after the turn ends.

**Constraints**:

- No worker text in a Notice (FR-043).
- No token in a process argument (`cci`, `--curl`).
- A forgotten checkout choice fails closed (FR-015).
- The open command never starts a Session without the Intake (FR-009).

**Scale/Scope**: One user, one master, and tens of workers a day. One `notices` row for each master worker.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Note |
|---|---|---|
| I. Shared core, thin adapters | Pass | The package owns only protocol names (`cci-role`, `cci-origin`), two commands, the switch rule, and the Master section. The master directory, prompt, omp command, and `AGENTS.md` are in the Intake configuration and the user's files (FR-006, D15). The switch rule is in the shared adoption path, not in an agent adapter. |
| II. Batch-verifiable gate | Pass | All new Elisp has ERT tests that need no display. They reuse `claude-code-ide-tests--with-spawn-adoption`, `--with-remote-targets`, and `--with-intake`. These helpers already mock `make-process`, `yes-or-no-p`, and the manager switch. |
| III. Optional dependencies | Pass | No new package. `curl` is optional, as in 024. Both commands give a `user-error` when the Intake URL or `curl` is missing. |
| IV. Ghostel only | Pass | No terminal change. The master and the workers attach through the existing Ghostel zmx path. |
| V. Simplicity | Pass | No new runtime dependency in any repository. The `cci` command line is one file that uses only the Bun standard library (D9). The switch rule replaces one `when-let*` test. |
| VI. Local/remote parity | Pass | The switch rule and the master mark read the zmx entry, which has the same shape for local and remote hosts. Recent output uses `run(host, …)` for both. One required difference: the master runs only on the Intake host. Remote constraint: the `cci` command reads the Intake token file, which exists only there. Workers keep full parity. |

Re-check after Phase 1: still Pass. There is no Complexity Tracking entry.

FR-007 is a rule in the master's instructions. The master has the full omp tool set (spec Clarifications, D10).

## Project Structure

### Documentation (this feature)

```text
specs/025-master-session/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── intake-http.md
│   ├── notices.md
│   ├── omp.md
│   ├── emacs-master.md
│   └── cci-cli.md
├── checklists/requirements.md
└── tasks.md             # /speckit.tasks output
```

### Source Code

```text
~/agents/cci-intake/
├── package.json                     # + "bin": { "cci": "src/cli.ts" }
├── README.md                        # [master], cci, Notices
├── src/
│   ├── cli.ts                       # NEW: cci subcommands (contracts/cci-cli.md)
│   ├── config.ts                    # + [master] table (with token_file), projects.*.description
│   ├── db.ts                        # + kind, notified_turn, held, notices table and queries
│   ├── launches.ts                  # + requestMaster, master-token origin and main_checkout rules, held/confirm/decline,
│   │                                #   master slot bypass, master labels in startLoop,
│   │                                #   turn Notices in reconcile, sendNotices
│   ├── hosts.ts                     # + zmxHistory(host, name, lines)
│   ├── http.ts                      # + master token check, /v1/master, /v1/projects, /output, /confirm, /decline; kind field
│   └── main.ts                      # + Notice on ended/failed/refused for master origin; sendNotices on master ready
└── test/
    ├── helpers.ts                   # FakeZmx: zmx history, keep --label values
    ├── master.test.ts               # NEW: single master, slot bypass, origin rules, held/confirm/decline
    ├── notices.test.ts              # NEW: turn rule, coalescing, restart, master down, text fields
    ├── cli.test.ts                  # NEW: each subcommand's request, stdin, exit codes, no token in argv
    └── http.test.ts                 # + new routes and 400 cases

~/agents/oh-my-pi/packages/coding-agent/
├── src/commands/launch-session.ts   # Git check only with --branch
├── src/session/sibling-spawn.ts     # publishState(state, work, turn?)
├── src/modes/interactive-mode.ts    # turn counter; cci-turn on agent_end
├── test/                            # launch-session non-Git cwd; publish cci-turn
└── CHANGELOG.md

claude-code-ide.el/                  # this repository
├── claude-code-ide.el               # + master slot; --spawn-switch-p (Master rules); --master-open-pending;
│                                    #   label decode; attach sets master slot
├── claude-code-ide-manager.el       # + item master slot, serialize; Master section in --render
├── claude-code-ide-intake.el        # + --curl method/body/status; claude-code-ide-master;
│                                    #   claude-code-ide-intake-confirm; held message
├── claude-code-ide-tests.el         # + rule table, Master section, open command, confirm
├── README.org, docs/zmx.org         # Master Session setup
├── CONTEXT.md                       # + Master Session, Worker Session, Notice
└── AGENTS.md                        # if a listed file or rule changes
```

**Structure Decision**: The same three repositories as in 024. The Intake owns the master's life, the Notices, and the `cci` command line, because it already owns Launches and delivery. omp changes only what the Intake cannot see: the turn counter and the `--cwd` check. The package reads labels at the one place where every adoption decides about the switch, so the Master rules stay in one function (FR-022). The open and confirm commands go in `claude-code-ide-intake.el`, because they need the Intake URL and `--curl`.

## Before Implementation

- Feature 024 must be done first (spec Assumptions). Its `tasks.md` has all boxes checked. This session did not run the 024 gates (ERT, `bun test`, `bun run check`), so run them before 025 work starts.
- `.specify/feature.json` points to `specs/024-session-launch-intake`, so the 024 session keeps its feature. Run 025 steps with `SPECIFY_FEATURE_DIRECTORY=specs/025-master-session`. Note that this variable also rewrites `feature.json` unless the script runs without persist.

## Complexity Tracking

No violations.
