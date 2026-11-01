# Data Model: Spawn and Remove Sibling Sessions

This feature adds no persistent store. zmx labels hold all state that crosses a process boundary. See `research.md` D10.

## Spawn request (omp tool arguments)

The `spawn_session` tool takes these arguments. See `contracts/omp-spawn.md`.

| Field | Type | Rule |
|---|---|---|
| `mode` | `fresh` \| `fork` \| `fork_handoff` \| `handoff_summary` | Required. |
| `text` | string | `fresh`: the opening prompt. `fork_handoff`: the handoff note. `handoff_summary`: optional focus instructions for the summary. `fork`: MUST be empty. Required and non-empty for `fresh` and `fork_handoff`. |
| `cwd` | absolute path | Optional. MUST name an existing directory on A's host. MUST NOT be set together with `new_worktree`. Default: A's current directory. |
| `new_worktree` | boolean | Optional. When true, omp creates a branch and worktree from A's current commit (FR-023). |
| `branch` | string | Optional. Used only with `new_worktree`. Default: `defaultSessionWorktreeBranch()`. |
| `model` | string (`provider/id`) | Optional. The model writes it only when the request names a model that differs from A's. It replaces the `--model` value that the shared builder takes from A. Default: A's model. |

Refusals (FR-020): A has no `ZMX_SESSION`, A's child argv has `--api-key`, or a fork mode runs on a session with no saved file.

## Spawn window (omp, in memory)

| State | Enter | Exit |
|---|---|---|
| closed | default | — |
| open | `/spawn` sets the window flag and adds `spawn_session` to the active tools | the first `spawn_session` call, a Session switch, or `agent_end` whose messages have no `spawn_session` and no `ask` call |

On exit, omp clears the window flag and restores the tool set from before `/spawn`. The spawn handler is not part of the window. InteractiveMode sets it once at startup, so the tool works whenever it is in the tool set (FR-018).

## Sibling Session (zmx session B)

| Attribute | Source |
|---|---|
| name | `<prefix>omp-<sanitized basename of cwd>-<6 random [a-z0-9]>`. The prefix comes from A's `ZMX_SESSION`. Default: `cci-`. |
| `cmd=` | the shared `/fork` builder argv, plus `--fork <file>` in the fork modes |
| `cwd=` | B's directory |
| env | builder env, minus `ZMX_SESSION`, `ZMX_SESSION_PREFIX`, and `EMACS_BUFFER_NAME`, plus `OMP_SPAWN_PARENT=<A name>` and `OMP_SPAWN_START_FILE=<start file>` (unset in fork mode) |
| labels | see below |

Lifecycle: created by `zmx attach` → running → ended by `/exit`, `/quit`, or `/despawn` (`zmx kill`). zmx ends the session when omp exits.

## Labels on B (see `contracts/zmx-labels.md`)

| Label | When | Meaning |
|---|---|---|
| `cci-parent` | always | A's zmx name (the parent link, FR-006) |
| `cci-wt-path`, `cci-wt-branch`, `cci-wt-base`, `cci-wt-source` | only with `new_worktree` | the spawned worktree record (FR-023). It rebuilds a `SessionWorktree` |
| `cci-state` | B sets it at the first `message_start` of each run and at `agent_end` | `working` or `idle` (FR-015) |
| `cci-work` | B sets it with `working` and removes it at `agent_end` | the first line of the first user or assistant message that is not only a tag, at most 80 characters (FR-015) |

## Announcement (omp → Emacs)

One OSC 52 `e` message with one argument: B's zmx name. See `contracts/osc-spawn-announce.md`.

## Package option

| Symbol | Type | Default | Effect |
|---|---|---|---|
| `claude-code-ide-switch-on-spawn` | boolean | `t` | After the attach, show B with `claude-code-ide-manager-switch-to-session` (FR-013). |

## omp setting

| Id | Type | Default | Effect |
|---|---|---|---|
| `spawn.confirm` | boolean | `false` | Before it creates B, omp shows the mode, the directory, and the start content, and asks yes/no (FR-022). |
