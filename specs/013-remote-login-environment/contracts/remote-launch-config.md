# Remote Launch Configuration Contract

## Configuration Interface

`claude-code-ide-remote-launch-config` remains an alist keyed by exact configured host.

A shell-enabled entry has this shape:

```elisp
("ramhorn"
 :executable "omp"
 :args ()
 :environment ("SKIP_TMUX=1")
 :shell "/usr/bin/zsh"
 :shell-args ("-lic"))
```

`:executable` and `:args` retain their current meaning. `:environment` contains optional literal assignments within a shell preference. `:shell` and `:shell-args` are required when `:environment` appears.

When the shell pair is absent, fresh launch uses the current direct behavior. When the pair is present, every fresh launch on that exact host initializes the selected environment.

The package applies assignments before shell startup. It appends its complete command after `:shell-args`. For zsh, `("-lic")` requests login, interactive, and command modes.

## Validation Rules

1. The host must pass the existing exact configured-host validation.
2. The configuration value must be a proper property list.
3. Only `:executable`, `:args`, `:environment`, `:shell`, and `:shell-args` are accepted.
4. Each key can occur once.
5. `:environment` must be a proper list of unique literal `NAME=VALUE` strings.
6. Environment names must use shell variable syntax and cannot be `ZMX_SESSION` or `ZMX_SESSION_PREFIX`.
7. `:environment` requires `:shell` and `:shell-args`.
8. `:shell` must be an absolute, nonempty literal path without control characters.
9. `:shell-args` must be a nonempty proper list of literal strings without control characters.
10. `:shell` and `:shell-args` must appear together.
11. The launch specification must copy every returned string and list.
12. Configuration parsing must not contact the host or inspect local shell state.

A remote missing shell or unsupported argument set fails during that host's launch. The package does not infer another shell.

## Fresh Sibling Launch

A shell-enabled sibling launch follows this order:

1. Validate the host and launch configuration.
2. Build the target command from literal directory, target, Agent executable, Agent arguments, and environment assignments.
3. Apply environment assignments.
4. Start the configured shell with the configured arguments.
5. Run the target command as the shell's next command argument.
6. Change to the exact remote directory after shell initialization.
7. Clear `ZMX_SESSION` and `ZMX_SESSION_PREFIX` immediately before `zmx` starts.
8. Create and attach the new zmx target.
9. Let the Agent inherit the resulting environment and configured assignments.

The remote command has this logical shape:

```text
exec env ENV... SHELL SHELL-ARGS "cd DIRECTORY && exec env -u ZMX_SESSION -u ZMX_SESSION_PREFIX ENV... zmx attach NAME AGENT ARG..."
```

The displayed double quotes describe one command argument. The implementation uses the existing POSIX literal quoting helper for every data value.

A launch without shell settings keeps the current direct command shape.

## Remote Worktree Launch

A shell-enabled Worktree launch preserves the existing ownership protocol.

1. Capture environment, shell, and Agent settings with the operation's immutable launch selection.
2. Apply environment assignments before shell startup.
3. Resolve the Agent executable inside the configured shell environment before confirmation.
4. Keep resolver stdout separate from shell startup output.
5. Require one absolute executable result.
6. Create the zmx target through the existing verified Worktree bootstrap.
7. Execute the generated bootstrap inside that target.
8. Save the bootstrap's canonical starting directory.
9. Apply the same environment assignments.
10. Replace the bootstrap with the configured shell and arguments.
11. After shell initialization, restore the saved directory.
12. Invoke the unchanged runner Agent entry with literal positional arguments.
13. Let the runner retain identity, branch, repository, claim, and receipt checks.
14. Execute the resolved Agent without another shell parse.

The outer Worktree worker keeps its verified absolute zmx executable. This is required by its collision and ownership checks. The Agent still receives the selected login environment.

The generated bootstrap uses a fixed command string. The saved directory and runner arguments travel as positional arguments. No user value becomes shell syntax.

## Output and Failure Contract

- Shell startup output remains terminal output.
- Emacs does not parse warnings, banners, prompts, or errors as Agent state.
- Login initialization failure does not trigger a direct-launch retry.
- A missing shell or Agent produces a host-qualified failure.
- Existing sibling rollback and Worktree outcome handling remain authoritative.
- A failed launch does not create a replacement ordinary shell.
- Failure on one host does not change another host's launch or Session.

Worktree preflight can redirect startup output away from its result channel. The real target initialization runs again inside the terminal, where the user can see that output.

## Literal-Value Contract

All user and remote values remain data:

- Host
- Remote directory
- Target name
- Agent executable
- Agent arguments
- Shell executable
- Shell arguments
- Environment assignments

Each value must pass existing control-character checks. Each command layer applies the existing POSIX single-quote encoder. The fixed shell command refers to variable positional arguments instead of interpolating data.

## Existing-Target Contract

The shell preference applies only when a workflow creates a fresh remote Agent.

These paths remain unchanged:

- Attach an existing target
- Reattach a remembered target
- Detach a client
- Stop a target
- Display or restore a manager row

No existing Agent restarts. No Session gains a shell field. No manager persistence schema changes.
