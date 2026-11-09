# Quickstart: Start the Intake from Emacs

These scenarios prove the feature from end to end. The rules are in `contracts/emacs-commands.md`.

## Prerequisites

- The Intake at `~/agents/cci-intake`, with a valid `~/.config/cci-intake/config.toml`, and `cci` on `PATH`.
- No Intake runs outside Emacs. Stop the detached `cci-intake` service before scenario 1. Check with `lsof -nP -iTCP:7311 -sTCP:LISTEN`, which must print nothing.
- In the live Emacs, set:

```elisp
(setq claude-code-ide-intake-url "http://127.0.0.1:7311"
      claude-code-ide-intake-client "mac"
      claude-code-ide-intake-command
      '("/Users/fuyu0425/.asdf/installs/bun/1.4.2/bin/bun" "run" "/Users/fuyu0425/agents/cci-intake/src/main.ts"))
```

## Automated

1. Run `./scripts/compile-and-test.sh`. There are 0 unexpected results.

## Live scenarios

1. **Start (US1/AC1, FR-005)**: `M-x claude-code-ide-intake-start`. The message `Intake answers at http://127.0.0.1:7311` appears within 10 seconds. `cci projects` answers.
2. **Log (US1/AC4, FR-006)**: `M-x claude-code-ide-intake-log`. The buffer shows `cci-intake: listening on 127.0.0.1:7311`, and its mode line shows `run`.
3. **No second Intake (US2/AC2)**: Run `M-x claude-code-ide-intake-start` again. The message says that the Intake that Emacs started already runs. `lsof` shows one listener.
4. **Restart (US1/AC3)**: `M-x claude-code-ide-intake-restart`. The listener has a new PID, and `cci projects` answers.
5. **Stop (US1/AC2, FR-008)**: `M-x claude-code-ide-intake-stop`. The message says `Intake stopped`. `lsof` prints nothing. `cci projects` fails to connect.
6. **Outside Intake (US2/AC1)**: Start the Intake in a terminal. In Emacs, run start, then stop. Start says that an Intake already answers. Stop says that Emacs did not start it. The terminal Intake still runs. Stop it in the terminal.
7. **Bad configuration (FR-007, SC-005)**: Add `[hosts.default]` with `max_sessions = 3` to the config. Run start. The message is `Intake ended (exit 1): error: hosts.default: "default" is reserved …`. Remove the line.
8. **Start with pull (US3, FR-009)**: With no Intake running, run `(claude-code-ide-intake-mode -1)`, then `(claude-code-ide-intake-mode 1)`. The Intake starts, and within 10 seconds the mode receives events. A `cci launch` of a test project attaches its Session in Emacs.
9. **Emacs exit (FR-010, SC-003)**: In a separate `emacs -Q` with this package on the load path and the same settings, run start, then quit Emacs with `C-x C-c`. Emacs asks no question about the process. Then `lsof` prints nothing.
10. **Fresh Emacs, no terminal step (US3, SC-004)**: Make sure no Intake runs (`lsof` prints nothing). Start a new `emacs -Q` with an init file that puts this package on the load path, sets the three settings above, and runs `(claude-code-ide-intake-mode 1)`. Do nothing else. Within 10 seconds, `cci projects` answers, and the mode receives events. A `cci launch` of a test project attaches its Session in that Emacs. Quit that Emacs, and `lsof` prints nothing. This stands in for a reboot, because a reboot only removes the running Intake.

For scenarios 9 and 10, start the Emacs binary itself (`/opt/homebrew/Cellar/emacs-plus@31-native/31.1/Emacs.app/Contents/MacOS/Emacs -Q -nw -l INIT`). The `~/bin/emacs` wrapper adds `--with-profile`. With `-Q`, Emacs does not know that option and skips the `-l` file.

## Cleanup

Stop the test Launches. Start the Intake again the way you normally run it.
