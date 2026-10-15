# Research: Remote Worktree Follow

**Feature**: `018-remote-worktree-follow` | **Date**: 2026-10-15

All findings come from reading the code and one live query of the running
Emacs. Line numbers are from the tree on 2026-10-15.

## R1. Where the remote move signal comes from

- **Decision**: Use the existing Ghostel OSC 7 path:
  `ghostel-directory-change-hook` → `claude-code-ide--record-ghostel-directory`
  (`claude-code-ide.el:800`) → `claude-code-ide-session-relocate` (`:705`).
- **Rationale**: The live Session `*claude-code[v12x@v12dev]*<2>` had
  `default-directory` `/rpc:v12dev:/home/yufu/wt/v12x/feat-030-target-checkout/`
  after `wtmove`. So the report reaches Emacs. `relocate` then drops it at the
  `(not (file-remote-p directory))` guard (`:714`).
- **Alternatives considered**:
  - The MCP `session_state_changed` report. A remote Agent has no MCP
    connection (`docs/remote.org` Scope Limits, SSE binds to `127.0.0.1`).
    `--session-buffer-for-agent` (`:764`) also skips remote Sessions. Rejected.
  - Polling `zmx list` for a live cwd. zmx reports the start directory, and a
    poll adds an SSH round trip per tick. Rejected.

## R2. How to convert the report to a Session directory

- **Decision**: For a Session with a host, take
  `(file-remote-p directory 'localname)`, remove one trailing `/` (keep `/`
  alone), and accept it only when `claude-code-ide-zmx--valid-directory-p`
  accepts it. Do not compare the TRAMP host with the Session host.
- **Rationale**:
  - ADR 0003 says the Session directory is a bare path on the host.
  - `claude-code-ide-remote-project-rpc-directory` always adds a trailing
    `/` (`claude-code-ide-remote-project.el:810-826`). Session creation stores
    the path without one (`claude-code-ide.el:1953`). Without the trim, a
    report of the same directory looks like a move, and the metadata queue
    treats `/a` and `/a/` as two targets (test at `claude-code-ide-tests.el:23667`).
  - `--valid-directory-p` (`claude-code-ide-zmx.el:121`) already rejects
    relative paths and control characters (FR-003).
  - `--normalize-directory` (`claude-code-ide.el:668`) and `file-directory-p`
    use the local file system. FR-002 and ADR 0003 forbid them here.
  - When the buffer has no RPC prefix, Ghostel builds
    `/<method>:<reported-hostname>:` (`ghostel/lisp/ghostel.el:3984-3990`).
    That hostname can differ from the Session host alias. The terminal runs on
    the Session host by construction, so the path part is still correct.
- **Alternatives considered**: Require the TRAMP host to equal the Session
  host. This drops every move on a host without an RPC method, and it protects
  against nothing an Agent can do. Rejected.

## R3. Row group and label while the probe runs (FR-006, FR-008)

- **Decision**: On a remote move, rewrite the Session `group-metadata`:
  - `:kind git`: set `:directory` to the new path, and set `:branch` and
    `:worktree-path` to nil. Keep `:host`, `:common-dir`, `:project-path`.
  - Any other kind, or no metadata: set nil.
- **Rationale**: `--valid-group-metadata` (`claude-code-ide-manager.el:588-618`)
  requires `:directory` to equal the item directory. The old plist is invalid
  after a move, so the row falls to `(unresolved HOST DIR)` (`:628`). The
  rewritten git plist passes. Its group key stays `(git HOST COMMON-DIR)`. The
  label is the basename of the new directory (`:760-766`). A non-git plist
  needs project equal to directory for a remote host (`:609`), so it cannot
  keep its old group.
- **Failure (FR-008)**: A probe failure only logs (`:5686-5694`). The row
  keeps the rewritten plist: new path, no branch, previous group. The spec
  edge case now states this.
- **Alternatives considered**: Clear the metadata for every move. The row
  then jumps to a separate group for one SSH round trip. Rejected for git
  rows, which is the reported case.

## R4. Getting the new branch (FR-004, FR-005, FR-007)

- **Decision**: After the move, rebuild the global items, save the state,
  then call `claude-code-ide-manager--enqueue-remote-metadata` for the Session.
  Before the enqueue, remove the new directory from the host operation's
  `known` table.
- **Rationale**:
  - The apply check (`:5638-5668`) compares the snapshot directory with the
    global *item* directory. `claude-code-ide-manager-refresh-all` rebuilds
    items only inside an open manager buffer (`:3680`). The move path must call
    `(claude-code-ide-manager-refresh-items '(:type global) t)` itself, or the
    correct result is refused as stale.
  - The same check drops a result for the old directory (FR-005). No cancel
    is needed, and other Sessions' probes on the host keep running.
  - Enqueue queues behind an in-flight probe (`:5787`).
  - `known` (`:5763-5774`) skips a snapshot equal to one seen in the same
    operation. For A → B → A inside one operation, the A result can arrive
    while the row is at B and is dropped. The return to A is then skipped, and
    the row never gets a branch. Removing the directory from `known` for a
    move fixes this with one line.
- **Alternatives considered**: `claude-code-ide-manager--cancel-remote-metadata`
  plus a full host refresh. It kills other Sessions' probes. Rejected.

## R5. Persistence (FR-009)

- **Decision**: Call `claude-code-ide-manager--save-state` after the item
  rebuild in the remote move path.
- **Rationale**: `refresh-items` saves only when it adopts a legacy row
  (`:2559`). Remote rows are the only copy after a restart, and
  `--reattach-remote-session` (`claude-code-ide.el:2364`) attaches with the
  stored directory. `--save-state` writes only when the serialized state
  changed (`:1832-1843`). The probe callback saves again when it applies
  (`:5698`).
- **Alternatives considered**: Rely on a later save. A crash or restart in
  between restores the old directory. Rejected.

## R6. Project view and Magit view after a move (FR-011)

- **Decision**: Remove the live Session directory comparison from three
  remote checks:
  - `claude-code-ide-manager--remote-layout-request-current-p`
    (`claude-code-ide-manager.el:5025-5028`)
  - `claude-code-ide-remote-project--resume-layout-request`
    (`claude-code-ide-remote-project.el:1438-1441`)
  - `claude-code-ide-remote-project--surviving-view`
    (`claude-code-ide-remote-project.el:1642-1644`)
- **Rationale**: Today these checks make a switch back to a moved Session drop
  the old view, rebuild the layout, and prepare a view for the new directory.
  FR-011 forbids that. The remaining guards still protect ownership: Session
  key, attachment `eq`, host admission, frame epoch, and request `eq` to the
  frame intent. The request's own `:directory` stays the input of the worker
  (`begin-attempt` at `:1480`, `prepare-shell` at `:1319`). Before this
  feature, a remote Session directory never changed, so the checks guarded
  only the test fixtures that change it by hand.
- **Local reference**: A local relocate touches no layout state. A switch
  restores the saved window state, so the old Magit or Dired buffer stays. A
  new companion starts only from `build-default-layout`, `reset-layout`, or a
  first display. Each uses the new directory. FR-011 therefore matches local
  behavior. Constitution principle VI needs no recorded difference.
- **Reset (`R`)**: `claude-code-ide-manager-reset-layout` (`:5292`) builds a
  fresh request from the live directory and advances the frame epoch. It
  already shows the new worktree. No change.
- **Alternatives considered**: Store a captured directory on the request and
  compare with that. The request already carries its directory. Rejected as
  duplicate state.

## R7. Companion shell (FR-012)

- **Decision**: No code change.
- **Rationale**: Only `allow-create` requests make a shell. Those come from
  `build-default-layout`, `reset-layout`, and first display, and each reads the
  live directory. An open shell is reused as it is. After R6, a shell creation
  that started before the move finishes in the old directory. That matches
  FR-011, and the spec edge case now states it.

## R8. Tests that encode the old behavior

- `claude-code-ide-test-manager-layout-preset-remote-stale-directory`
  (`claude-code-ide-tests.el:23991`) asserts that a directory change replaces
  a ready view. Rewrite it to assert FR-011.
- `claude-code-ide-test-remote-project-layout-keeps-exact-view-object`
  (`~:25467`) asserts `should-not surviving-view` after a directory change.
  Flip it.
- `claude-code-ide-mcp-sse-test-dispatch-session-directory` (`:2348`) asserts
  that `relocate` refuses a remote path for a *local* Session. Keep it.
