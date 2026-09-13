# Quickstart: validating zmx-backed agent sessions

Runnable validation guide. Contracts: [contracts/commands.md](./contracts/commands.md).
Data shapes: [data-model.md](./data-model.md).

## Prerequisites

- Emacs 28.1+ with this package on `load-path`.
- `zmx` on PATH for the interactive scenarios (`which zmx`).
  The automated suite does NOT need zmx (SC-003).
- Ghostel installed (this package's terminal backend).

## Automated gate

```bash
./scripts/compile-and-test.sh
```

Expected: byte-compilation clean, full ERT suite passes, including the new
`claude-code-ide-zmx` tests, with zmx mocked (SC-002, SC-003).

## Scenario 1: survive Emacs (User Story 1, SC-001)

1. `(setq claude-code-ide-use-zmx t)`
2. `M-x claude-code-ide` in a project → agent runs; `zmx list` in a shell
   shows one `cci-<agent>-<project>-…` session.
3. Kill the terminal buffer → no prompt; `zmx list` still shows the session.
4. Quit Emacs. In a terminal: `zmx attach cci-<agent>-<project>-…` → same
   conversation continues.

## Scenario 2: restart reattach (User Story 2)

1. Restart Emacs with `claude-code-ide-use-zmx` non-nil.
2. `M-x claude-code-ide` in the same project → completing-read offers the
   surviving session plus "create new".
3. Pick the session → buffer opens attached; idle tracking updates as the
   agent produces output.
4. Repeat `M-x claude-code-ide`: the already-attached session is NOT offered
   again (clarification 1); with `C-u` continue flag, no offer appears at all
   (clarification 2).

## Scenario 3: adopt a terminal-launched session (User Story 3, SC-004)

1. In a terminal, inside some project: `zmx attach demo omp`, then detach.
2. In Emacs: `M-x claude-code-ide-attach` → `demo` listed, annotated with its
   directory and `omp` command.
3. Select it → buffer opens; CLI type inferred as omp; session appears in the
   manager.
4. Round trip: kill the Emacs buffer, `zmx attach demo` in the terminal again.

## Scenario 4: explicit stop (User Story 4, SC-005)

1. With a zmx-backed session open: `M-x claude-code-ide-stop`.
2. Prompt names the zmx session. Answer no → `zmx list` unchanged.
3. Run again, answer yes → session gone from `zmx list`, buffer cleaned up.

## Negative checks

- `(setq claude-code-ide-use-zmx nil)` → start a session; verify no zmx
  process appears (FR-001).
- Rename zmx away (`claude-code-ide-zmx-program` = "definitely-missing") with
  zmx mode on → session start signals a `user-error` naming zmx (FR-009).
- Kill the zmx session from a terminal while attached in Emacs → the buffer's
  process exits; the Session cleans up like any process exit today.
