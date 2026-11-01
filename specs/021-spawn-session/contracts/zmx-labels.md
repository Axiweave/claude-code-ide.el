# Contract: zmx Labels on a Sibling Session

zmx 0.8.1 labels are in-memory `key=value` pairs that live as long as the session. `zmx list` prints them as more tab-separated fields after `cmd=`. Separate labels with spaces in `--labels` and `zmx set`.

## Encoding

Each value is unpadded base64url text (`Buffer.from(value).toString("base64url")`). zmx 0.8.1 accepts only `[A-Za-z0-9-_.]` in a label value, so percent-encoding fails. A reader decodes every `cci-*` value with `Buffer.from(value, "base64url")`. Keys are fixed ASCII.

## Keys

| Key | Writer | When | Value |
|---|---|---|---|
| `cci-parent` | A, through `zmx attach --labels` | create | A's `ZMX_SESSION` |
| `cci-wt-path` | A | create, `new_worktree` only | worktree absolute path |
| `cci-wt-branch` | A | create, `new_worktree` only | branch name |
| `cci-wt-base` | A | create, `new_worktree` only | base commit SHA |
| `cci-wt-source` | A | create, `new_worktree` only | A's checkout path (`sourceCwd`) |
| `cci-state` | B, through `zmx set $ZMX_SESSION` | the first `message_start` of a run and `agent_end`, only when `OMP_SPAWN_PARENT` is set | `working` or `idle` |
| `cci-work` | B, in the same `zmx set` call as `cci-state` | set with `working`, removed (`cci-work=`) at `agent_end`, only when `OMP_SPAWN_PARENT` is set | the first line of the first user or assistant message that is not only a tag, at most 80 characters |

## Readers

- `/despawn` in A: one `zmx list`. The children are the entries with `cci-parent` equal to A's `ZMX_SESSION`.
- The package does not read these labels. Both list parsers accept them as extra `k=v` fields.

## Failure rules

- A failed `zmx set` in B is logged at debug level and ignored. The remove confirmation then shows no working state.
- A missing or partial `cci-wt-*` set means "no spawned worktree". omp never touches that worktree.
