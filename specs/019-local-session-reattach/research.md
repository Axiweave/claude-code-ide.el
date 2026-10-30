# Research: Local Session Reattach

All findings come from the current source. Line numbers are approximate and refer to the working tree on 2026-10-29.

## R1. Which rows the manager retains

**Decision**: The manager retains a row when the row has a zmx name. Today it retains a row only when the row has a host.

**Rationale**: Every remote row has a zmx name, because `--deserialize-item` rejects a remote row without a valid one. A local row has a zmx name only when it runs inside zmx. So "has a zmx name" covers remote rows as today, adds local zmx rows, and excludes plain local Sessions (FR-016). These sites now test the host and must test the zmx name instead:

| Site | File | Today |
|---|---|---|
| `--cleanup-on-exit` | `claude-code-ide.el` ~1242 | calls `--remember-remote-session` only for a host |
| `--remember-remote-session` | manager ~2092 | returns nil without a host |
| `--build-items` | manager ~2084 | merges remembered items only with a host |
| `claude-code-ide-manager-session-ended` | manager ~3732 | retains only with `--session-host` |
| `--item-visible-name` | manager ~2675 | `[disconnected]` only with a host |
| help-echo text | manager ~3150 | "Press c" text only with a host |
| `--navigate-project-group` | manager ~4084 | disconnected message only with a host |

**Alternatives considered**: A separate local store, or a new `remembered` flag on the item. Both were rejected because they duplicate the state that remote rows already use (advisory: "local reattach should be the remote path with host nil").

## R2. Persistence across a restart

**Decision**: No new state key and no new item slot.

**Rationale**: `--serialize-item` already writes local items, with `:zmx-name` and `:live-p`, while they are live. Emacs exit does not run `kill-buffer-hook`, so the saved state at exit still holds every live local row. Today the rows are lost only because `--build-items` drops local items that are not live. After R1, it keeps them, and it already sets `live-p` to nil for each remembered item. Saved layouts are keyed by Session ID, so they come back with the row (FR-002).

**Alternatives considered**: Write rows from `kill-emacs-hook`. This was rejected because the state is already on disk.

## R3. Reattach path

**Decision**: Rename `claude-code-ide--reattach-remote-target` to `claude-code-ide--reattach-target`, and rename `--reattach-remote-session` to `--reattach-session`. Remove the host requirement. With no host, the function:

1. calls `claude-code-ide-zmx--ensure`. A missing zmx gives a `user-error`, and the row stays (FR-013).
2. reads `claude-code-ide-zmx-list-sessions` once. If the name is absent, it logs, forgets the row with `claude-code-ide-manager-session-ended KEY t`, and signals a `user-error` (FR-012).
3. calls `claude-code-ide--attach-zmx-entry (list :name NAME) DIRECTORY CLI-PATH SESSION-ID`.

`--attach-zmx-entry` already routes an entry without `:host` to the local zmx server. Two more changes complete the path:

- `claude-code-ide--create-session` passes `reusable-session-id` to the local path too.
- `claude-code-ide--create-local-session` takes an optional `reusable-session-id`. When it is set, the function uses that Session ID and also takes `order` and `created-at` from the remembered item. This copies `--create-remote-session` (~2019–2030).

The local directory check in `--create-local-session` stays. A missing directory gives a `user-error`, and the row stays. The spec edge case was updated to match.

**Rationale**: This gives one reattach function for both hosts. `c` (`claude-code-ide-manager-reattach-at-point`) loses its local refusal (~5443) and calls the renamed function.

**Alternatives considered**: A local-only reattach function. This was rejected as a second copy of the same flow.

## R4. `a` and `A` reuse a remembered row

**Decision**: Remove the `host` guards in the identity lookups and compare hosts with `equal`, so that nil matches nil:

- `claude-code-ide--live-session-for-target` (~1753): remove the `(when host ...)` wrapper.
- `claude-code-ide--attach-zmx-entry` (~2487–2490): look up `live` and the remembered Session ID for every entry, with or without a host.

`--remembered-target-session-id` already compares `(equal item-host host)`. With host nil, it matches only local rows, so a local name never matches a remote row (spec edge case).

The pickers stay unchanged. `--zmx-adoptable-sessions` hides only names with a live local Session, so a disconnected row's zmx session is still listed (FR-008). Adoption then reuses the row (FR-009).

**Alternatives considered**: Hide remembered names in the picker. This was rejected because the user asked to keep `a`/`A` as an attach path after a restart.

## R5. A local Agent exits

**Decision**: Rename `--verify-remembered-remote-target` to `--verify-remembered-target`. Give it a local branch: one synchronous `zmx list`. If the name is absent, forget the row. If the list fails, keep the row. `--cleanup-on-exit` calls it for a local zmx Session after it remembers the row.

**Rationale**: A client ends when the Agent exits, when the user kills the buffer, or when a detach runs. Only the zmx list tells these cases apart. A local list is a fast local process call, so a synchronous call in the sentinel or kill hook is acceptable. The remote branch stays asynchronous and is unchanged (FR-017).

**Alternatives considered**: Read the client exit status. This was rejected because the remote path already uses a list check for the same question, and one method keeps parity. It is also not verified that a client exit status tells an Agent exit from a detach.

## R6. Startup cleanup (clarification A)

**Decision**: A defvar `claude-code-ide-manager--local-rows-checked`, nil at load. On the first `--build-items` for the global scope that has at least one remembered local row, the manager reads `zmx list` once and sets the flag. It removes each remembered local row whose name is absent. A missing zmx, or a failed list, keeps all rows (FR-011, FR-013). Live rows are never checked.

**Rationale**: `--build-items` is where the manager first shows remembered rows. The flag keeps the check to one call for each Emacs instance. Package load and batch tests that never open the manager make no call.

**Alternatives considered**: Run the check in `--initialize` at package load. This was rejected because it starts a process at load time for users who never open the manager.

## R7. Selection and the auto-reattach option

**Decision**: Rename the uncommitted `claude-code-ide-manager-auto-reattach-remote` to `claude-code-ide-manager-auto-reattach`. `--ensure-live-target` (~5182) uses it for any remembered row:

- A remote row with a host that is not configured gives the existing "restore host" error.
- When the option is on, the function reattaches.
- When the option is off, it gives "Session is disconnected. Press c to reattach".

The docstring loses its remote-only wording and keeps the note about the SSH deadline for remote rows.

**Rationale**: FR-006 requires one preference. The option is not committed yet, so a rename needs no alias (AGENTS.md: no backward compatibility).

## R8. Stop and detach on a disconnected local row

**Decision**:

- `claude-code-ide-stop` (~2298) builds its stub Session from any remembered item with a zmx name, not only from an item with a host.
- `--stop-local-session` kills the buffer only when the buffer is live. Today it calls `(kill-buffer nil)` for a stub, which kills the current buffer. After `claude-code-ide-zmx-kill` succeeds, it calls `claude-code-ide-manager-session-ended KEY t`. A failed kill signals an error and keeps the row (FR-015).
- `claude-code-ide-manager-detach-at-point` (~5504) accepts a remembered local row. It always forgets the row with `session-ended KEY t`, for local rows too, because after R1 a buffer kill alone keeps the row (FR-014).

## R9. Session order after a restart

**Decision**: `claude-code-ide--next-session-order` also takes the maximum `order` of remembered manager items with the same project key.

**Rationale**: The order counters are empty in a new Emacs. Without this change, a new Session in a project that has disconnected rows can get the same order, and the two rows get the same label. Remote rows have the same gap today. The fix is in the one shared function, so it covers both.

## R10. Documentation

**Decision**: Update `README.org`, where it says that disconnected rows are remote only (~265, 563, 601, 710, 737, 794). Update `docs/remote.org` (~365) for the selection behavior from R7. Add one sentence to `CONTEXT.md` under "Disconnected session": local zmx-backed Sessions also become disconnected rows.
