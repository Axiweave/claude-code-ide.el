# Contract: `omp launch-session`

## Command

```text
omp launch-session --cwd DIR [--branch NAME] [--label KEY=VALUE]... [--json] -- CHILD_ARGV...
```

- stdin carries the opening prompt in UTF-8. Empty or blank stdin means no opening prompt: the Session starts idle.
- `--cwd` is an absolute path to a Git checkout on this host.
- `--branch` asks for a new worktree. The command uses `freeBranchName(DIR, NAME)`, so an existing branch gets the next free suffix, for example `eng-123-2` (FR-055). Without `--branch`, the Session runs in `DIR`.
- `--label` adds one zmx label. Keys must start with `cci-`. The command base64url-encodes each value, as spec 021 does.
- `CHILD_ARGV` is the omp command that runs in the zmx session, for example `omp --profile work --auto-approve`.

## Result

With `--json`, the command prints one line on stdout and exits.

| Exit | stdout |
|---|---|
| 0 | `{"name":"cci-omp-api-x1y2z3","dir":"/…/.worktrees/eng-123","branch":"eng-123"}`. `branch` is `null` without `--branch`. |
| 1 | `{"error":"<reason>"}`. No zmx session, no worktree, and no branch from this call remain (FR-003). |

Without `--json`, the command is for a person at a shell. Success prints the zmx session name and a newline on stdout and exits 0. A refusal or failure prints the reason and a newline on stderr and exits 1, with the same cleanup. The Intake always uses `--json`.

SIGTERM or SIGHUP stops a launch that runs. The command then removes the zmx session, the worktree, the branch, and the start file that this call made. It prints `{"error":"launch-session stopped by SIGTERM"}` (or `SIGHUP`) like other failures. Then it exits 143 for SIGTERM or 129 for SIGHUP, through the process-wide signal handler. The cleanup ends before the 5 s grace of the Intake timeout.

The command also has its own deadline of 25 s. The Intake waits 30 s for a local command and 40 s for a remote one, because its timer also covers the ssh `ConnectTimeout` of 10 s. So the deadline expires first on each host. When the deadline expires, the command aborts the same `signal` and runs the same cleanup. It prints `{"error":"launch-session timed out after 25000 ms"}` and exits 1. Over `ssh -T`, the SIGTERM of the Intake does not reach the remote command, so the deadline does this cleanup. Tests set `OMP_LAUNCH_SESSION_DEADLINE_MS` to a shorter deadline.

## Behavior

The command and `/spawn` call one shared function in `session/sibling-spawn.ts` (FR-002):

```ts
spawnSession({dir, branch?, text?, argv, env, labels, publishState, settings, signal?}): Promise<{name, dir, branch}>
```

The function runs these steps:

1. When `branch` is set, it runs `freeBranchName`, then `createSessionWorktree`.
2. It builds the name with `siblingName` (`cci-omp-<base>-<rand>`).
3. It writes `text` to a mode-0600 start file.
4. It runs `createSibling`. With `publishState`, `createSibling` sets `OMP_PUBLISH_STATE=1` in the child environment.
5. When any step fails, or when `signal` aborts, it removes everything that the earlier steps made, then throws. `launch-session` aborts `signal` on SIGTERM, on SIGHUP, or at its deadline.

`/spawn` passes `publishState: false` and its `cci-parent` label, so its behavior does not change. `launch-session` passes `publishState: true` and no `cci-parent` label.

## State labels

The publish gate in `interactive-mode.ts` becomes:

```ts
if ((process.env.OMP_SPAWN_PARENT || process.env.OMP_PUBLISH_STATE) && process.env.ZMX_SESSION) this.#publishSpawnState(event);
```

`cci-state` and `cci-work` keep the spec 021 format (FR-004).
