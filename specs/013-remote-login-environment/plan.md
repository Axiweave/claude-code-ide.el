# Implementation Plan: Remote Login Environment

**Branch**: `013-remote-login-environment` | **Date**: 2026-09-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/013-remote-login-environment/spec.md`

The setup script returned `013-remote-login-environment` as the feature identifier. Planning creates feature artifacts and does not create a commit.

## Summary

Add optional environment assignments, a shell executable, and ordered shell arguments to each exact host's existing remote launch configuration. Use those settings for direct sibling and managed Worktree Agent creation. Keep direct launch as the default. Preserve literal command data, fresh target identity, Worktree ownership checks, visible startup output, and failure without fallback.

## Technical Context

**Language/Version**: Emacs Lisp on Emacs 28.1 or later. The existing remote Worktree bootstrap uses POSIX `/bin/sh`.

**Primary Dependencies**: Existing remote zmx launch helpers, OpenSSH, zmx, the remote Worktree runner, and Ghostel. Ghostel remains optional and is the sole terminal runtime. No new package dependency.

**Storage**: User configuration in `claude-code-ide-remote-launch-config`. No Session field, manager state, persistence schema, or new remote data store.

**Testing**: Focused ERT behavior checks in `claude-code-ide-tests.el`, existing shell-runner regressions, the full `./scripts/compile-and-test.sh` gate, and a live `ramhorn` parity walkthrough.

**Target Platform**: Supported Emacs hosts connected to user-approved POSIX remote hosts with SSH, zmx, and an explicitly configured POSIX-compatible shell.

**Project Type**: Emacs package with remote terminal launch and a package-owned POSIX Worktree runner.

**Performance Goals**: Direct launch adds no shell initialization. Parity launch adds one configured startup sequence and remains within existing 30-second control deadlines. A prepared user completes one launch within two minutes.

**Constraints**: Preserve exact-host approval, strict SSH options, literal argument boundaries, fresh zmx identity, Ghostel-only terminals, and no fallback. Shell startup can emit output or fail. The package cannot repair user startup files.

**Scale/Scope**: One optional shell preference per configured host. Two fresh-launch workflows change. Existing attach, reattach, detach, Stop, manager persistence, and local launch remain unchanged.

No technical context item remains unresolved.

## Constitution Check

*GATE: Passed before Phase 0 research and after Phase 1 design.*

| Gate | Before research | After design | Evidence and planned compliance |
|---|---|---|---|
| I. Shared Session core | Pass | Pass | Extend the shared remote launch specification and command seam. Add no Agent-specific session path. |
| II. Batch-verifiable quality | Pass | Pass | ERT covers configuration, command framing, Worktree preparation, bootstrap behavior, failures, and unchanged direct paths. The full gate remains required. |
| III. Optional dependencies | Pass | Pass | Add no dependency or hard require. Ghostel remains optional until terminal creation. |
| IV. Ghostel-only terminals | Pass | Pass | Reuse the existing Ghostel Session path. Add no terminal choice or fallback. |
| V. Simplicity and compatibility | Pass | Pass | Add two optional fields to one existing setting. Reuse quoting, launch selection, rollback, and bootstrap modules. |
| VI. Local and remote workflow parity | Pass | Pass | Every selected fresh Agent receives the configured environment. Direct sibling launch initializes it before zmx. Worktree ownership requires a verified bootstrap first. |
| ADR 0003 | Pass | Pass | Keep remote directories as bare host metadata until command construction. Build no TRAMP path. |
| Remote Worktree ownership | Pass | Pass | Keep launch selection capture, absolute Agent approval, collision checks, private staging, runner identity checks, and receipts. |
| Repository workflow | Pass | Pass | Work on the current checkout. Planning creates only feature artifacts and no commit. |

The Worktree path keeps its verified outer zmx bootstrap outside the login environment. This remote ownership constraint prevents unapproved target creation. The generated target bootstrap initializes the selected environment before Agent resolution, runner validation, and execution.

No gate violation or unresolved clarification remains.

## Project Structure

### Documentation (this feature)

```text
specs/013-remote-login-environment/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── remote-launch-config.md
└── checklists/
    └── requirements.md
```

`tasks.md` belongs to `/speckit.tasks` and is not created by this command.

### Source Code (repository root)

```text
claude-code-ide-zmx.el             # Host launch configuration, validation, quoting, SSH command shape
claude-code-ide.el                 # Fresh remote sibling launch call path and rollback
claude-code-ide-remote-worktree.el # Immutable launch capture, shell-aware preflight, generated bootstrap
claude-code-ide-tests.el           # Focused ERT behavior and regression coverage
README.org                         # User configuration and direct-launch guidance
docs/remote.org                    # Remote workflow, startup output, and troubleshooting
scripts/compile-and-test.sh        # Required implementation gate, unchanged
```

The package-owned `scripts/remote-worktree-runner.sh` remains unchanged. The generated bootstrap wraps its existing Agent entry.

**Structure Decision**: Extend the three modules that already own host launch settings, fresh Session creation, and Worktree launch preparation. Add no shell module, adapter registry, Session field, or runner protocol.

## Phase 0: Research Results

See [research.md](research.md).

Resolved decisions:

- Store `:environment`, `:shell`, and `:shell-args` beside existing per-host Agent settings.
- Accept `:environment` as an optional list of unique literal `NAME=VALUE` strings.
- Reserve `ZMX_SESSION` and `ZMX_SESSION_PREFIX` for fresh target identity.
- Require an absolute shell path and a nonempty argument list as an optional pair.
- Treat shell arguments as the complete prefix before one package-appended command argument.
- Use `:environment ("SKIP_TMUX=1")` and `:shell-args ("-lic")` for the confirmed `ramhorn` workflow. Do not append another `-c`.
- Reuse the existing POSIX literal quoting helper. Do not accept a free-form wrapper string.
- Apply environment assignments before both configured shell startups and fresh Agent execution.
- Wrap the complete direct sibling target command. Clear inherited zmx identity after login initialization and immediately before target creation.
- Resolve a Worktree Agent executable inside the selected login environment while isolating the machine-readable stdout result.
- Initialize the Worktree shell inside the newly created zmx target through the existing generated bootstrap.
- Keep the Worktree runner wire protocol unchanged.
- Preserve visible startup output and refuse direct fallback.

## Phase 1: Design

### Host Launch Configuration

Extend `claude-code-ide-remote-launch-config` with:

```elisp
:environment ("NAME=VALUE")
:shell "/absolute/remote/shell"
:shell-args ("command-mode-options")
```

`:environment` is optional within a shell preference. It contains unique literal assignments and cannot set reserved zmx identity names. The shell fields form an optional pair. `:shell` must be an absolute nonempty literal. `:shell-args` must be a nonempty proper list of literal strings. Unknown and duplicate keys remain errors.

`claude-code-ide-zmx--remote-launch-spec` validates and copies all fields. It returns them with the existing CLI type, Agent executable, and Agent arguments. It makes no remote request.

The package appends its command after the configured shell arguments. The user owns shell-specific option semantics. The documented zsh example uses `:shell-args ("-lic")`.

### Shared Login-Command Seam

Add one private command builder in `claude-code-ide-zmx.el`. Its interface accepts a complete package-owned command plus optional shell path and shell arguments.

With no shell, it returns the command unchanged. With a shell, it produces an `exec` command whose program, arguments, and final command argument use existing literal quoting.

Do not parse the shell arguments. Do not interpolate directory, target, Agent, or user argument values into fixed shell syntax.

### Direct Sibling Creation

Extend `claude-code-ide-zmx--remote-create-command` and its only production caller to pass the shell pair.

Build the current directory-qualified `env -u ... zmx attach ...` command first. Wrap that complete command only when the host has shell settings.

The identity clearing stays inside the wrapped command. Login startup therefore completes before `ZMX_SESSION` and `ZMX_SESSION_PREFIX` are removed immediately before `zmx` starts.

Keep the absent-shell command exactly compatible with current behavior. Reuse existing local-state rollback when the shell or target command exits before readiness.

### Worktree Agent Resolution

Keep the current direct `/bin/sh` executable resolution when the host has no shell preference.

For a shell-enabled host, extend `claude-code-ide-remote-worktree--prepare-launch` to invoke the selected shell with its arguments and a fixed resolver command. Pass the Agent name as a positional argument.

Use a fixed `/bin/sh` wrapper to save original stdout on file descriptor 3. Redirect shell startup stdout to stderr. Write only the resolved absolute Agent path to file descriptor 3.

Validate that result with the current absolute executable checks. Store the absolute Agent path in the operation snapshot before confirmation. A missing shell, failed startup, noisy malformed result, or missing Agent refuses preparation without dispatch.

The immutable launch-selection string already compares the full launch plist. Adding the shell fields makes a later shell change invalidate the operation before dispatch.

### Worktree Bootstrap

Extend `claude-code-ide-remote-worktree--render-bootstrap` without changing the staged-file or runner protocol.

The shell-enabled bootstrap performs these actions:

1. Validate the existing attempt token.
2. Record the canonical current directory before shell startup.
3. Replace the bootstrap process with the configured shell and arguments.
4. Pass a fixed package command as the shell's command argument.
5. Pass a private sentinel, saved directory, and existing runner command as positional arguments.
6. After login initialization, change back to the saved directory.
7. Replace the shell with the existing `/bin/sh runner.sh agent ...` invocation.

All dynamic values remain positional arguments. The fixed command uses only `cd`, `shift`, and `exec "$@"`. The runner keeps repository, branch, directory, claim, ownership receipt, and final literal Agent execution checks.

The absent-shell bootstrap remains unchanged.

### Output and Failure Behavior

Direct shell startup output flows through the current Ghostel process. Worktree startup output is retained in the new zmx terminal before normal attachment.

Do not classify startup text as Agent state. Keep existing readiness and outcome rules.

Do not retry direct launch. Keep sibling rollback and Worktree retained outcomes authoritative. A failed host does not change another host or an existing Session.

### Data and Interface

- [data-model.md](data-model.md) defines host preference fields, validation, identity, and lifecycle.
- [contracts/remote-launch-config.md](contracts/remote-launch-config.md) defines command order, literal-value rules, failures, and unchanged paths.
- [quickstart.md](quickstart.md) defines focused batch checks and live parity validation.

### Verification Design

Add focused ERT cases for observable contracts:

1. A valid shell pair is copied into the launch specification.
2. Missing pair members, relative shell paths, malformed lists, duplicate keys, and control characters are rejected.
3. Direct launch remains byte-compatible without a shell preference.
4. Shell-enabled sibling launch places the complete directory and zmx command after configured shell arguments.
5. Startup files cannot restore inherited zmx identity before fresh target creation.
6. Spaces, quotes, dollar signs, substitutions, and separators remain literal through both quoting layers.
7. Worktree preparation resolves the Agent through the configured environment and stores one absolute path.
8. Worktree startup stdout cannot contaminate the resolver result channel.
9. A missing shell, failed initialization, or missing Agent refuses Worktree dispatch without direct fallback.
10. A captured Worktree operation refuses dispatch after shell configuration changes.
11. Shell-enabled bootstrap restores the pre-start directory and invokes the unchanged runner Agent entry.
12. Direct Worktree bootstrap remains unchanged without shell settings.
13. Attach, reattach, detach, and Stop command shapes do not read or apply the shell preference.

Test behavior through launch specifications, final command strings, operation transitions, and generated bootstrap execution. Do not assert incidental whitespace or duplicate runner ownership tests.

During implementation, run the focused ERT selector first. Then run `./scripts/compile-and-test.sh`. After success, reload changed Elisp with `emacsclient` and perform the live steps in [quickstart.md](quickstart.md).

## Post-Design Constitution Check

The design still passes every gate above.

- The shared launch specification is the only user configuration seam.
- Two real fresh-launch paths use one command builder and one preference shape.
- The Worktree bootstrap stays behind its existing ownership checks.
- No optional dependency becomes mandatory.
- Direct and existing-target behavior remain unchanged.
- The full batch gate and live environment comparison provide proof.

## Complexity Tracking

No constitution violation requires an exception.
