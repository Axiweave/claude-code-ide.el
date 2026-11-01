# Implementation Plan: Fork into a Sibling Session with `/fork spawn`

**Branch**: `main` (spec dir `022-fork-spawn`) | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/022-fork-spawn/spec.md`

## Summary

`/fork spawn` creates a Sibling Session B with a copy of A's conversation. It runs no model turn, and A and B get no new message. omp already does this work in the fork mode of `/spawn`: the `#handleSpawnRequest` handler in `interactive-mode.ts`. The plan splits that handler in two:

- The tool part keeps the one-spawn-per-run guard and closes the spawn window.
- A new private `#spawnSibling(request, confirm)` keeps the creation steps.

`/fork spawn` calls `#spawnSibling({ mode: "fork" }, false)` directly. So it never touches the spawn window, the run guard, or `spawn.confirm`. The `/fork` slash command gets a `spawn` subcommand. The package needs no change, because it already attaches every announced Sibling Session (spec 021).

## Technical Context

**Language/Version**: TypeScript on Bun (omp `packages/coding-agent`). No Emacs Lisp change.

**Primary Dependencies**: zmx 0.8.x (`zmx attach --labels`), the spec 021 modules `session/sibling-spawn.ts` and `cli/fork-child.ts`.

**Storage**: omp session JSONL files. B gets its copy through `--fork <A's session file>`.

**Testing**: `bun test` with the `test/spawn-command.test.ts` InteractiveMode harness (`createSibling` stubbed) and `test/slash-commands/fork.test.ts`. Full gate: `bun run check` and `bun run test` in `packages/coding-agent`. Package gate `./scripts/compile-and-test.sh` must stay green, with no package change.

**Target Platform**: macOS and Linux hosts that run omp inside zmx under Emacs/Ghostel, local and remote.

**Project Type**: CLI agent (omp) plus an Emacs package (claude-code-ide.el).

**Performance Goals**: B has focus within 5 s on a local host (SC-002). No model request (SC-003).

**Constraints**: same as `/spawn`: no secret on B's command line, B never inherits A's zmx name or Emacs buffer, and a failed creation leaves no zmx session.

**Scale/Scope**: one subcommand, about 40 changed lines in omp, two test files, and three doc files.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Result |
|---|---|
| I. Shared Session Core, Thin Agent Adapters | Pass. No package code changes. Emacs attaches B through the spec 021 announcement path. |
| II. Batch-Verifiable Quality Gate | Pass. The package gate runs unchanged. The omp tests run without a display (harness with stubbed zmx). |
| III. Optional Dependencies Stay Optional | Pass. No new dependency. |
| IV. Ghostel-Only Terminal Support | Pass. No terminal change. |
| V. Simplicity and Compatibility | Pass. This feature reuses the `/spawn` creation steps through one extracted method. It adds no new module and no setting. |
| VI. Local and Remote Workflow Parity | Pass. omp runs on A's host in both cases. The remote flow is the same as the spec 021 remote spawn. No remote difference is needed. |

Post-design re-check: still Pass. The design adds one private method, one public context method, and one subcommand case.

## Project Structure

### Documentation (this feature)

```text
specs/022-fork-spawn/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── fork-spawn.md
└── tasks.md             # /speckit.tasks
```

### Source Code

```text
~/agents/oh-my-pi/packages/coding-agent/
├── src/modes/interactive-mode.ts       # split #handleSpawnRequest; add handleForkSpawnCommand
├── src/modes/types.ts                  # InteractiveModeContext.handleForkSpawnCommand
├── src/slash-commands/builtin-session.ts  # /fork "spawn" subcommand and usage text
├── test/spawn-command.test.ts          # /fork spawn behavior through the harness
├── test/slash-commands/fork.test.ts    # subcommand routing and usage
├── CHANGELOG.md                        # Unreleased: Added
└── ../../docs/session-operations-export-share-fork-resume.md  # /fork table and text
~/agents/oh-my-pi/UPSTREAM_DIVERGENCES.md   # /spawn entry names /fork spawn
```

**Structure Decision**: The change is in omp only. This repo holds only the spec documents.

## Complexity Tracking

No violations.
