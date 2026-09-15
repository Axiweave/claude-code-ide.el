# Quickstart: Validate Remote Login Environment

## Prerequisites

- Use Emacs 28.1 or later with Ghostel available.
- Configure two exact remote hosts with working noninteractive SSH and trusted host keys.
- Install zmx on both hosts.
- Use one host whose interactive login adds a private executable directory.
- Keep one second host without a shell preference for direct-mode comparison.
- Fix or knowingly accept startup warnings before judging Agent output.

For the observed `ramhorn` workflow, use:

```elisp
(setq claude-code-ide-remote-launch-config
      '(("ramhorn"
         :environment ("SKIP_TMUX=1")
         :shell "/usr/bin/zsh"
         :shell-args ("-lic"))))
```

## Batch Gate

Run the focused feature checks:

```sh
emacs -batch -L . -l ert -l claude-code-ide-tests.el \
  --eval '(ert-run-tests-batch-and-exit "remote-login-environment")'
```

Expected result: the selector runs the feature's behavior tests and reports zero unexpected results.

Run the repository gate:

```sh
./scripts/compile-and-test.sh
```

Expected result: byte compilation succeeds with zero warnings, and the full ERT suite reports zero unexpected results.

## Scenario 1: Measure Environment Parity

1. Choose the remote directory used for the fresh Agent.
2. Start a normal interactive login on the parity host.
3. Change to that same remote directory.
4. Record command lookup for `zmx`, the Agent, and one private command.
5. Record `PATH`, one selected variable, locale, umask, and working directory.
6. Start a fresh remote sibling Agent in the selected directory.
7. Use the Agent's normal command tool to record the same values.

Expected results:

- All selected commands resolve to the expected paths.
- `PATH`, the selected variable, locale, umask, and working directory match.
- On `ramhorn`, `/home/yufu/.cargo/bin` appears in `PATH`.
- Startup warnings remain visible before Agent output.

## Scenario 2: Preserve Direct Launch by Default

1. Leave host B without `:shell` and `:shell-args`.
2. Start a fresh remote Agent on host B.
3. Capture the terminal command in focused ERT or inspect the resulting environment.

Expected results:

- Host B uses the existing direct launch command.
- Host B does not load the parity host's startup files.
- The parity host's configuration does not affect host B.

## Scenario 3: Cover Both Fresh-Launch Workflows

1. Start a sibling Agent with `s` on the parity host.
2. Start another fresh Agent through remote Worktree open or create.
3. Compare the six parity values in both Agents.

Expected results:

- Both Agents receive the selected login environment.
- Each Agent starts in its exact selected Worktree.
- The Worktree operation retains its normal confirmation, collision checks, and ownership receipts.

## Scenario 4: Preserve Literal Values

Use a controlled fixture host and repository whose directory contains spaces and a single quote. Configure Agent arguments containing spaces, quotes, dollar signs, and command-substitution text.

Expected results:

- The Agent receives every argument unchanged.
- No punctuation expands or executes as shell syntax.
- The selected directory remains one literal path.

Do not use command-like fixture text on a host with valuable writable data.

## Scenario 5: Fail Without Fallback

1. Configure a nonexistent absolute shell path on a fixture host.
2. Request a fresh sibling launch.
3. Repeat through a remote Worktree launch.
4. Restore the valid shell path.

Expected results:

- Each failure identifies the selected host.
- Neither path retries direct launch.
- No replacement Agent or ordinary shell remains.
- Existing Sessions on all hosts remain usable.

## Scenario 6: Keep Existing Targets Unchanged

1. Attach an existing remote Agent.
2. Detach and reattach that target.
3. Cancel one Stop request.
4. Confirm Stop only on a disposable target.

Expected results:

- Attach and reattach do not run the configured login shell.
- Reattach keeps the existing target and Agent process.
- Canceling Stop sends no kill request.
- The preference affects only fresh Agent creation.

## Scenario 7: Configuration Changes During Worktree Preparation

1. Start a remote Worktree launch and pause at confirmation.
2. Change that host's shell path or arguments.
3. Continue the captured operation.

Expected result: the operation refuses dispatch because its approved launch selection changed.

See [data-model.md](data-model.md) for field and lifecycle rules. See [contracts/remote-launch-config.md](contracts/remote-launch-config.md) for command behavior.
