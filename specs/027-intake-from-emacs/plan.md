# Implementation Plan: Start the Intake from Emacs

**Branch**: `027-intake-from-emacs` | **Date**: 2026-11-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/027-intake-from-emacs/spec.md`

## Summary

A new user option, `claude-code-ide-intake-command`, holds the program and arguments that start the Intake. Its default is `nil`. Four commands in `claude-code-ide-intake.el` start, stop, and restart the Intake, and show its output buffer. Emacs keeps at most one managed Intake process. Before a start, Emacs makes a non-blocking connect to the host and port of `claude-code-ide-intake-url`. When an Intake answers, Emacs starts no second one. Emacs starts the Intake only for a loopback URL.

After a start, Emacs checks every 0.5 seconds, for up to 10 seconds, and shows one result message. An end that the user did not ask for gives one message with the exit status and the Intake's `error:` line. When the Intake command setting is set, `claude-code-ide-intake-mode` runs the start step when it turns on. The process is `:noquery`, so Emacs stops it at exit without a question. See `research.md` D1–D9.

## Technical Context

**Language/Version**: Emacs Lisp. Emacs 28.1+ per `Package-Requires`.

**Primary Dependencies**: None added. The connect check uses the built-in `make-network-process` and `url-generic-parse-url`.

**Storage**: None. The managed process lives in one variable for the life of this Emacs.

**Testing**:
- ERT in `claude-code-ide-tests.el`, with `make-network-process`, `signal-process`, and `accept-process-output` mocked inside `claude-code-ide-tests--with-intake`, which already mocks `make-process` and `run-at-time`.
- The tests drive the sentinels directly.
- `./scripts/compile-and-test.sh` is the gate.
- The live check is `quickstart.md` scenarios 1–10.

**Target Platform**: Emacs on macOS, with the Intake on the same machine.

**Project Type**: An Emacs package. Only this repository changes. The Intake does not change.

**Performance Goals**: The Intake answers within 10 seconds of a start (SC-001). No command blocks Emacs, except that a stop waits up to 5 seconds.

**Constraints**:
- At most one managed Intake.
- Emacs never starts an Intake while one answers at the URL.
- Emacs starts the Intake only for a loopback URL.

**Scale/Scope**: One process, four commands, and one option.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Note |
|---|---|---|
| I. Shared core, thin adapters | Pass | The Intake is not an Agent. The code goes into the existing optional `claude-code-ide-intake.el` and changes no shared session layer. The Intake command setting is user configuration with a `nil` default. The package names no path. |
| II. Batch-verifiable gate | Pass | New ERT tests mock the process, the network, and the timers, and they need no display. |
| III. Optional dependencies | Pass | No new dependency. The start commands need neither `curl` nor the token file. |
| IV. Ghostel only | Pass | No terminal is involved. The output goes to a plain buffer. |
| V. Simplicity | Pass | One option, with no separate directory option and no `kill-emacs-hook` (research D1, D4). The mode reuses its existing reconnect, not a new wait (D8). |
| VI. Local/remote parity | Pass | There is one required difference: Emacs starts the Intake only on this machine (FR-004). The constraint is that the program in the Intake command setting runs locally, so it cannot start an Intake on another host. Remote Worker Sessions do not change. |

Re-check after Phase 1: still Pass. There is no Complexity Tracking entry.

## Project Structure

### Documentation (this feature)

```text
specs/027-intake-from-emacs/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── emacs-commands.md
├── checklists/requirements.md
└── tasks.md             # /speckit.tasks output
```

### Source Code (repository root)

```text
claude-code-ide-intake.el   # option, managed process, connect check, 4 commands, mode hook
claude-code-ide-tests.el    # ERT tests for each contract row
docs/zmx.org                # Intake section: the option, the commands, the one-Intake rule
AGENTS.md                   # intake.el line names the new commands
```

**Structure Decision**: Everything goes into the existing `claude-code-ide-intake.el`, beside the pull client that it serves. No new file.

## Complexity Tracking

No violations.
