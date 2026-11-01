# Data Model: `/fork spawn`

This feature adds no new stored data. A B from `/fork spawn` is a spec 021 Sibling Session with fixed values.

## Forked Sibling Session

These are the spec 021 Sibling Session fields (`specs/021-spawn-session/data-model.md`), with the values that `/fork spawn` sets.

| Field | Value |
|---|---|
| name | `siblingName(<A's zmx name>, <A's cwd>, <6 random [a-z0-9]>)` |
| `cmd=` | `buildForkChildLaunch` argv with A's model and A's zmx executable, plus `--fork <A's flushed session file>` |
| `cwd=` | A's cwd (`sessionManager.getCwd()`) |
| env | builder env without `ZMX_SESSION`, `ZMX_SESSION_PREFIX`, and `EMACS_BUFFER_NAME`. It adds `OMP_SPAWN_PARENT=<A name>`. `OMP_SPAWN_START_FILE` is unset. |
| labels | `cci-parent=<A name>` only. There are no `cci-wt-*` labels. |
| first message | none. B waits for the user. |

## Request passed to `#spawnSibling`

`{ mode: "fork" }`. It has no `text`, `cwd`, `model`, `new_worktree`, or `branch`. The `confirm` argument is `false`.

## State transitions in A

`/fork spawn` changes no state in A:
- the spawn window stays as it was;
- `#spawnRunUsed` stays as it was;
- the tool set is unchanged;
- the conversation is unchanged.

A gets one status line: `Spawned <name>`.
