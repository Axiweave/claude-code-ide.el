# Research: Remote Login Environment

## R1. Extend the existing per-host launch configuration

**Decision**: Add optional `:environment`, `:shell`, and `:shell-args` fields to `claude-code-ide-remote-launch-config`.

`:environment` is an optional part of a shell preference. It is a list of literal `NAME=VALUE` strings. Names are unique and cannot replace zmx identity variables. `:shell` is an absolute executable path. `:shell-args` is a nonempty ordered list of literal strings. Both shell fields must appear together. Their absence keeps direct launch.

**Rationale**: The existing setting already owns exact-host Agent executable and argument choices. One plist keeps one immutable launch selection for sibling and Worktree workflows. Environment assignments let startup files select the intended non-multiplexed path without a host-specific package branch.

**Alternatives considered**:

- Add a second per-host setting. Rejected because it creates a second host lookup and permits conflicting launch choices.
- Read `$SHELL`. Rejected because it can be unset or differ from the workflow the user wants.
- Hard-code zsh. Rejected because hosts can use different shells.
- Enable login shells globally. Rejected because startup can be slow, noisy, or broken.

## R2. Treat shell arguments as the complete command-mode prefix

**Decision**: The package appends one package-owned command string after `:shell-args`. The configured arguments must tell the selected POSIX-compatible shell to execute that next argument.

For the confirmed `ramhorn` workflow, the setting is:

```elisp
("ramhorn"
 :environment ("SKIP_TMUX=1")
 :shell "/usr/bin/zsh"
 :shell-args ("-lic"))
```

The package applies environment assignments before startup and Agent execution. It does not append another `-c`. It does not split or interpret combined options.

**Rationale**: `/usr/bin/zsh -lic COMMAND` reads the login and interactive startup files that supply `/home/yufu/.cargo/bin`. `SKIP_TMUX=1` keeps the host's startup files from replacing this package-owned zmx launch. Appending another `-c` would make the first `-c` consume the wrong argument.

**Alternatives considered**:

- Always append `-c`. Rejected because a configured `-lic` already contains command mode.
- Configure only `-l`. Rejected because the observed Cargo path comes from interactive startup.
- Accept a free-form wrapper string. Rejected because it loses literal argument boundaries and adds template parsing.

## R3. Reuse literal POSIX quoting at one shared seam

**Decision**: Build the downstream command from individually quoted literals. Pass that complete command as one final shell argument.

A shared private helper in `claude-code-ide-zmx.el` returns the direct command unchanged when no shell exists. With a shell, it returns this shape:

```text
exec 'SHELL' 'SHELL-ARG'... 'PACKAGE-OWNED COMMAND'
```

The package-owned command uses `claude-code-ide-zmx--exec-command` and `claude-code-ide-zmx--quote`. User paths and Agent arguments never resume as shell syntax.

**Rationale**: The existing quote helper already protects spaces, quotes, substitutions, separators, and glob characters across SSH. Reuse avoids another escaping format.

**Alternatives considered**:

- Concatenate user values into a command template. Rejected because command data could become syntax.
- Add a shell adapter module. Rejected because two launch paths can use one existing command-building seam.

## R4. Wrap the complete direct sibling launch

**Decision**: For direct sibling creation, initialize the configured shell before directory selection and target creation. Then change to the exact directory, clear inherited zmx identity variables, and invoke `zmx attach`.

```text
ssh ... HOST "exec SHELL SHELL-ARGS 'cd DIRECTORY && exec env -u ZMX_SESSION -u ZMX_SESSION_PREFIX zmx attach NAME AGENT ARG...'"
```

The current direct command remains byte-for-byte unchanged when the shell fields are absent.

**Rationale**: First target creation inherits the login environment. Clearing identity variables after startup prevents startup files from restoring stale target identity.

**Alternatives considered**:

- Wrap only the Agent executable. Rejected because `zmx` would still use the non-login command environment.
- Clear identity variables before shell startup only. Rejected because startup files can set them again.

## R5. Resolve Worktree Agents inside the selected environment

**Decision**: Keep the current direct executable probe when no shell exists. When a shell exists, run the probe through that shell and preserve a clean result channel.

A fixed `/bin/sh` wrapper saves original stdout on file descriptor 3. It redirects login startup output to stderr. The resolver writes only the validated absolute Agent path to file descriptor 3.

The resolver command receives the configured Agent name as a positional argument. It never interpolates that name as syntax.

**Rationale**: The current direct `command -v` cannot see paths added by interactive startup. Deferring all resolution until target creation would weaken approval and turn a missing Agent into a late bootstrap failure.

**Alternatives considered**:

- Keep the direct preflight for all modes. Rejected because it reproduces the reported missing-path problem.
- Defer command lookup to the Agent process. Rejected because confirmation would not show the selected absolute executable.
- Parse the last stdout line. Rejected because arbitrary startup output could be mistaken for the result.

## R6. Initialize the Worktree Agent inside the new persistent target

**Decision**: Keep the runner protocol unchanged. Extend the existing generated `bootstrap.sh` only.

The direct bootstrap remains unchanged. A shell-enabled bootstrap records its starting directory, then replaces itself with the configured shell. The shell receives a fixed command plus positional arguments. That command restores the starting directory and invokes the existing runner Agent entry.

```text
bootstrap.sh token check
  -> save canonical current directory
  -> exec SHELL SHELL-ARGS FIXED-COMMAND SENTINEL DIRECTORY /bin/sh RUNNER agent ...
  -> fixed command changes to DIRECTORY and execs its positional arguments
  -> existing runner validates ownership and execs the absolute Agent
```

**Rationale**: Worktree creation discovers its final directory only during the claimed operation. The existing bootstrap already runs inside the new target and retains terminal output.

The outer Worktree worker still uses its verified absolute `zmx` path. This is a required ownership constraint. The Agent receives the selected login environment before its runner validation and execution.

**Alternatives considered**:

- Extend the runner wire protocol with shell argument counts. Rejected because the generated bootstrap can wrap the unchanged runner interface.
- Start the shell before the Worktree target exists. Rejected because a created Worktree path is not available then.
- Initialize the shell twice. Rejected because it duplicates startup side effects and delay.

## R7. Preserve output, failure, and existing-target behavior

**Decision**: Do not suppress or interpret shell startup output. Do not retry direct launch after shell failure. Keep attach, reattach, detach, and Stop commands unchanged.

Direct sibling output already reaches Ghostel. Worktree startup output remains in the new zmx terminal and appears when Emacs attaches. Existing rollback and retained-operation paths report failures with their host context.

**Rationale**: Output helps the user diagnose startup files. A fallback would silently start an Agent with the wrong environment.

**Alternatives considered**:

- Hide startup warnings. Rejected because the user explicitly chose environment parity.
- Retry without the shell. Rejected because success with the wrong environment is a false success.

## R8. Verify behavior at command and workflow seams

**Decision**: Add focused ERT coverage for configuration validation, command shape, Worktree preflight, bootstrap rendering, host isolation, direct fallback, and unchanged attachment.

Keep the runner unchanged. Existing runner tests remain the regression guard for ownership and literal Agent argv.

Use the live `ramhorn` scenario to compare command lookup, `PATH`, one selected variable, locale, umask, and working directory. Treat the observed zplug warnings and startup error as visible user configuration output.

**Rationale**: Command-shape tests prove literal safety. Live comparison proves the environment outcome that batch mocks cannot establish.

**Alternatives considered**:

- Assert source text only. Rejected because it does not prove argument boundaries or behavior.
- Add a new test framework. Rejected because ERT and the existing shell runner tests cover the changed seams.
