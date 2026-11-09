# Implementation Plan: Launch Agent Sessions from Outside Events

**Branch**: `024-session-launch-intake` | **Date**: 2026-11-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/024-session-launch-intake/spec.md`

## Summary

A new Bun service, the Intake, accepts Launch requests over HTTP and polls Linear for a trigger label and for comments. It records each Trigger in SQLite, applies a gate with fixed rules, and starts omp Sessions in zmx with `omp launch-session`, locally or through SSH. That command shares one spawn function with `/spawn`. It reads the prompt from stdin and labels the session with its Launch ID for crash recovery. A `zmx list` loop on each host gives the Launch state and the free host slots. Emacs adopts a running Launch by push and by pull:

- **Push**: The Intake runs `emacsclient --eval '(claude-code-ide-adopt-session HOST NAME)'`.
- **Pull**: The optional `claude-code-ide-intake-mode` follows the SSE stream through `curl`.

A pending set in the adopt command makes adoption happen once. Follow-ups reach a live Session as a new APC packet `pi:send;<mode>.<base64url>` through `zmx send`. omp maps `queue`, `guide`, and `stop` to its existing `followUp`, `steer`, and `abort` paths. A Linear comment becomes a follow-up only when it starts with the follow-up prefix (default `/omp`), so the Agent's own replies do not loop back. Each Trigger that fails the gate gets a `refused` Launch, so the list shows the reason. See `research.md` D1–D19.

## Technical Context

**Language/Version**: TypeScript on Bun 1.4 (the Intake, and omp `packages/coding-agent` and `packages/tui`). Emacs Lisp for Emacs 28.1+ (package).

**Primary Dependencies**:

- Intake: `Bun.serve`, `bun:sqlite`, `Bun.TOML`, `Bun.spawn`, and no npm package.
- Outside programs: zmx 0.8.1, `ssh`, `emacsclient`, and `curl`. `curl` is needed only for the pull path.
- Linear GraphQL API with a personal API key.

**Storage**: One SQLite file in WAL mode for the Intake (`data-model.md`). zmx labels on each Session. No package storage.

**Testing**:

- Intake: `bun test` with a fake command runner and a local fake Linear server. The seeded property tests print their seed.
- omp: `bun test` for the changed files, then `bun run check`, then `bun run test`.
- Package: ERT through `./scripts/compile-and-test.sh`.

**Target Platform**: macOS (the usual Intake and Emacs host) and Linux launch hosts with zmx and omp. Local and remote (principle VI).

**Project Type**: A small daemon in a new repository, a CLI command and an input packet in the omp fork, and two public entry points in this Emacs package.

**Performance Goals**:

- Request to Emacs row: at most 15 s local and 30 s remote (SC-001).
- Label to issue comment: at most 90 s, with a 30 s poll (SC-004).
- Pull adoption: at most 10 s (SC-007).

**Constraints**:

- The Intake uses only outgoing connections to Linear, so it works behind NAT.
- The Intake listens only on configured private addresses.
- No prompt or token appears in a process argument.
- No retry of a step whose result is unknown: follow-up send, push, kill.

**Scale/Scope**: One user, a few hosts, and tens of Launches a day. One `zmx list` per host every 10 s, and two Linear queries every 30 s.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Note |
|---|---|---|
| I. Shared core, thin adapters | Pass | The adopt command wraps the shared spawn adoption path. The pull mode only calls the adopt command. The package builds no omp command and owns no agent list or CLI path: the omp command is in the Intake configuration (FR-022). |
| II. Batch-verifiable gate | Pass | ERT tests cover the adopt command (validation with `refused` and one message, pending set, `skipped`), the SSE parser, list catch-up, and reconnect. They mock `make-process` for `curl` and reuse `claude-code-ide-tests--with-spawn-adoption` and `--with-remote-targets`. No display and no optional package is needed. |
| III. Optional dependencies | Pass | The pull path needs no Elisp package. `curl` is an outside program, like `ssh` and `zmx`. The mode gives a `user-error` when `curl` is missing. The file loads and compiles without `curl`. |
| IV. Ghostel only | Pass | No terminal change. Launched Sessions attach through the existing Ghostel zmx path. |
| V. Simplicity | Pass | No new runtime dependency in the package. It adds one public function, one small file with three options and one minor mode, and one pending list. omp reuses `createSibling`, `freeBranchName`, `createSessionWorktree`, and `session.prompt`. The Intake uses only the Bun standard library. |
| VI. Local/remote parity | Pass | One adopt path for local and remote hosts. Remote differences: (1) Emacs adopts only Configured hosts, as before. (2) A remote adopt is async after one `ssh … zmx list`, as before. (3) The Intake runs host commands through `ssh` with single-quoted arguments, and the spike proved that this carries the same bytes. (4) A push to an Emacs on another machine goes through `ssh`. |

Re-check after Phase 1: still Pass. The design adds no Complexity Tracking entry.

## Project Structure

### Documentation (this feature)

```text
specs/024-session-launch-intake/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── intake-http.md
│   ├── intake-config.md
│   ├── omp-launch-session.md
│   ├── omp-send-packet.md
│   └── emacs-adopt.md
├── checklists/requirements.md
└── tasks.md             # /speckit.tasks output
```

### Source Code

```text
~/agents/cci-intake/                         # NEW repository
├── package.json                             # scripts: start, test. No dependencies.
├── README.md                                # setup, config, curl examples
├── src/
│   ├── main.ts                              # load config, open db, start server and loops
│   ├── config.ts                            # TOML load, validation, secret-file mode check
│   ├── db.ts                                # schema, transactions, queries
│   ├── hosts.ts                             # run(host, argv): local or ssh; zmx list/kill/send; launch-session
│   ├── launches.ts                          # gate, queue, host slots, reconcile, stop, follow-ups
│   ├── emacs.ts                             # push adoption, host map
│   ├── http.ts                              # routes, bearer check, SSE fan-out
│   └── linear.ts                            # label and comment polls, project map, prompt, comment outbox
└── test/
    ├── launches.test.ts                     # dedupe, restart recovery, slots, state (property tests)
    ├── followups.test.ts                    # order, once-only, refusal, packet bytes
    ├── http.test.ts                         # auth, status codes, SSE, client host map
    ├── linear.test.ts                       # history parsing, gate, mapping order, self-skip, cursor
    └── emacs.test.ts                        # push form, name and host checks

~/agents/oh-my-pi/packages/
├── coding-agent/src/session/sibling-spawn.ts       # + spawnSession (moved from #spawnSibling), publishState option
├── coding-agent/src/commands/launch-session.ts     # NEW: headless command (template: commands/commands.ts)
├── coding-agent/src/cli-commands.ts                # + launch-session entry
├── coding-agent/src/cli/command-help.ts            # + launchSessionHelp
├── coding-agent/src/modes/interactive-mode.ts      # #spawnSibling calls spawnSession; publish gate; onSend handler
├── tui/src/prompt/composer.ts                      # + `send` APC kind, onSend callback
└── coding-agent/test/                              # sibling-spawn, launch-session, composer send tests

claude-code-ide.el/                          # this repo
├── claude-code-ide.el                       # + claude-code-ide-adopt-session, claude-code-ide--pending-adoptions
├── claude-code-ide-intake.el                # NEW: pull options, claude-code-ide-intake-mode, curl SSE client
├── claude-code-ide-tests.el                 # + adopt command and pull tests
├── README.org, docs/zmx.org                 # adopt command, pull setup
└── CONTEXT.md                               # domain terms: Intake, Launch, Trigger
```

**Structure Decision**: Three repositories, as in specs 010 and 021. The Intake is a new repository because it is not part of the Emacs package or omp. omp gets one shared spawn function, so `/spawn` and `launch-session` cannot drift apart. The package keeps the adopt command in the main file next to the spawn adoption code. The pull client goes in its own file because it is optional and has its own options.

## Complexity Tracking

No violations.
