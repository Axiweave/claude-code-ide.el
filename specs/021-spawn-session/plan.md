# Implementation Plan: Spawn and Remove Sibling Sessions

**Branch**: `021-spawn-session` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/021-spawn-session/spec.md`

## Summary

omp gets `/spawn <request>`. It opens a short spawn window in which the model can call the hidden `spawn_session` tool once. The tool builds B's command with the `/fork` builder, then creates B with `zmx attach --labels` on A's host. After that, omp writes one OSC 52 `e` announcement with B's zmx name. The package handler checks the buffer and the name, then reuses the `attach-all` path to adopt that one entry. It shows B when `claude-code-ide-switch-on-spawn` is on. `/despawn` lists A's children by the `cci-parent` label, confirms, and ends one child with `zmx kill`. For a spawned worktree, it applies omp's existing worktree exit plan. FR-021 already holds, so the package has no exit-path change. See `research.md` D1–D13.

## Technical Context

**Language/Version**: Emacs Lisp for Emacs 28.1+ (package). TypeScript on Bun (omp, `packages/coding-agent`).

**Primary Dependencies**: Ghostel (optional, `ghostel-eval-cmds`) and zmx 0.8.1 labels. In omp: `ptree.exec`, `writeTerminalSequence`, and `session-worktree.ts`. No new dependency.

**Storage**: zmx session labels in memory. Start content in mode-0600 temp files.

**Testing**: ERT through `./scripts/compile-and-test.sh`. omp: `bun test` for each changed file, then `bun run check`, then the full suite with `bun run test` (SC-007).

**Target Platform**: macOS and Linux hosts with zmx. Local and remote (principle VI).

**Project Type**: Emacs package plus a CLI Agent change in a second repo.

**Performance Goals**: B is visible within 5 s of the spawn call (SC-001). The OSC handler does no I/O.

**Constraints**: One-way announcement. No answer from Emacs to omp. One spawn for each `/spawn`. A's conversation and checkout do not change.

**Scale/Scope**: A few children for each Session. A linear `zmx list` scan is enough.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Note |
|---|---|---|
| I. Shared core, thin adapters | Pass | The handler lives in the shared session layer next to the editor request. It only adopts zmx entries, so it adds no Agent-specific command code. The `omp` CLI-type check is the same gate that the editor request uses. |
| II. Batch-verifiable gate | Pass | Each new path gets ERT tests with Ghostel, zmx, and the manager mocked through the existing editor-handoff and remote-target fixtures. |
| III. Optional dependencies | Pass | The registration stays under `with-eval-after-load 'ghostel`. No hard `require`. |
| IV. Ghostel only | Pass | The only terminal channel is Ghostel OSC 52 `e`. |
| V. Simplicity | Pass | It reuses `attach-zmx-entries`, `/fork`'s builder, `planWorktreeExit`, and the `loop` gate. One new predicate, one handler, and one defcustom in the package. No new dependency. |
| VI. Local/remote parity | Pass | One handler and one timer path. Only the list call differs: local uses a sync `zmx list`, and remote uses the existing async discovery. That difference already exists for attach. omp runs on A's host in both cases. |

Re-check after Phase 1: still Pass. The design adds no Complexity Tracking entry.

## Project Structure

### Documentation (this feature)

```text
specs/021-spawn-session/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── osc-spawn-announce.md
│   ├── zmx-labels.md
│   └── omp-spawn.md
└── tasks.md             # /speckit.tasks output
```

### Source Code

```text
claude-code-ide.el/                      # this repo
├── claude-code-ide-zmx.el               # + claude-code-ide-zmx--package-name-p
├── claude-code-ide-session.el           # + spawn-announce handler and its ghostel-eval-cmds entry
├── claude-code-ide.el                   # + claude-code-ide-switch-on-spawn, adopt-one-entry timer body
├── claude-code-ide-tests.el             # + handler, adopt, switch, and name tests
├── README.org, docs/zmx.org             # user docs for the announcement and the option
└── CONTEXT.md                           # domain term: Sibling Session

~/agents/oh-my-pi/packages/coding-agent/src/
├── modes/controllers/command-controller.ts   # /fork uses the extracted child builder
├── cli/fork-child.ts                         # NEW: shared child argv/env builder (moved from command-controller)
├── session/sibling-spawn.ts                  # NEW: name, labels, zmx create/list/kill, announcement
├── tools/spawn-session.ts                    # NEW: hidden spawn_session tool
├── prompts/tools/spawn-session.md            # NEW: tool prompt
├── prompts/spawn/spawn-kickoff.md            # NEW: /spawn kickoff prompt ({{#if askEnabled}})
├── tools/builtin-names.ts, tools/index.ts    # hidden tool entry + isToolAllowed gate
├── sdk.ts, session/agent-session.ts          # spawn handler wiring + generateHandoffDocument
├── modes/interactive-mode.ts, modes/types.ts # spawn handler at startup, window begin/end, /spawn and /despawn handlers, cci-state/cci-work publish
├── slash-commands/builtin-session.ts         # /spawn and /despawn specs
├── tools/settings.ts                         # spawn.confirm
└── utils/external-editor.ts                  # export quoteOscArg
```

**Structure Decision**: Two repositories, as in spec 010. The omp zmx logic goes in one new module, `session/sibling-spawn.ts`, so the tool and `/despawn` share it. The package change stays in the existing files.

## Complexity Tracking

No violations.
