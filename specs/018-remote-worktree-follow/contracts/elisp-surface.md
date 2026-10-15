# Contract: Elisp Surface

**Feature**: `018-remote-worktree-follow` | **Date**: 2026-10-15

The feature adds no user option, command, or key binding. It changes one
public function and adds one internal manager helper.

## Changed: `claude-code-ide-session-relocate (buffer directory)`

| Aspect | Local Session (no host) | Remote Session (host set) |
|---|---|---|
| Accepted `directory` | Unchanged: absolute, not remote, existing local directory | A TRAMP name whose localname passes the data-model validation |
| Stored value | `--normalize-directory` result | Bare localname, one trailing `/` removed |
| Local file access | `file-directory-p`, `expand-file-name` | None (FR-002) |
| Metadata | Unchanged (local refresh probes again) | Rewritten as in [data-model.md](../data-model.md) |
| After the store | `claude-code-ide-manager-refresh-all` | `claude-code-ide-manager-refresh-all`, then `claude-code-ide-manager--note-remote-move` |
| Return | The moved Session, or nil | The moved Session, or nil |

A remote Session still ignores a local path. A local Session still ignores a
remote path.

## Added: `claude-code-ide-manager--note-remote-move (session)`

In this order:

1. Remove the Session directory from the `known` table of the host's metadata
   operation, when one exists.
2. Rebuild the global items: `(claude-code-ide-manager-refresh-items '(:type global) t)`.
3. Save: `claude-code-ide-manager--save-state`.
4. Enqueue: `claude-code-ide-manager--enqueue-remote-metadata`.

It never cancels a probe. It never opens a connection by itself.

## Changed: remote view request checks (FR-011)

These three functions no longer compare the request `:directory` with the
live Session directory. All other checks stay.

| Function | File |
|---|---|
| `claude-code-ide-manager--remote-layout-request-current-p` | `claude-code-ide-manager.el` |
| `claude-code-ide-remote-project--resume-layout-request` | `claude-code-ide-remote-project.el` |
| `claude-code-ide-remote-project--surviving-view` | `claude-code-ide-remote-project.el` |

## Unchanged

| Surface | Requirement |
|---|---|
| MCP `session_state_changed` | Local Sessions only |
| `claude-code-ide-manager-reset-layout` (`R`) | Builds a fresh request from the live directory |
| Buffer name, zmx name, Session ID, order | Not changed by a move (FR-010) |
| Structs and persisted keys | No new slot or key |
| Package dependencies | No new `require` |

## Behavioral invariants

These are the properties the tests prove.

1. **Bare path**: for every accepted remote report, the stored directory has
   no TRAMP prefix and no trailing `/` (except `/`).
2. **Idempotence**: a report equal to the current directory, with or without
   a trailing `/`, changes nothing and queues no probe.
3. **Rejection**: a relative path, a path with control characters, a local
   path for a remote Session, and a remote path for a local Session change
   nothing.
4. **Last move wins**: after any sequence of moves and probe replies, a row
   shows a branch only from a reply for its current directory.
5. **Group kept**: between a move and its reply, a git row keeps its group key.
6. **Persisted**: after a move, the saved remembered row has the new directory.
7. **View kept**: after a move, a switch to the Session shows the same view
   object, and starts no preparation. `R` then prepares the new directory.
