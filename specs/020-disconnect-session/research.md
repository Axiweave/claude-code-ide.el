# Research: Disconnect Session

The Technical Context has no NEEDS CLARIFICATION items. This file records the design decisions and their evidence in the code.

## R1. Lifecycle path

**Decision**: Disconnect kills the live Session buffer and lets the existing `kill-buffer-hook` run `claude-code-ide--cleanup-on-exit SESSION-ID t PROCESS`. If the Session is still registered after the kill, Disconnect calls `claude-code-ide--cleanup-on-exit SESSION-ID t` itself.

**Rationale**:
- With a nil disposition, `--cleanup-on-exit` (`claude-code-ide.el:1239`) calls `claude-code-ide-manager--remember-session` for a zmx-backed Session before it unregisters the Session. Then the row stays as a Disconnected session row, with the zmx name, directory, Agent type, host, presentation fields, and Saved layout (FR-003, FR-004).
- For a local Session, `--cleanup-on-exit` then calls `--verify-remembered-target`. That function forgets the row only when `zmx list` confirms the zmx session is gone. A disconnect ends only the attach client, so the zmx session stays listed and the row stays.
- `claude-code-ide--cleanup-session-resources` clears idle timers and activity (spec 003 T022), so FR-016 needs no new code.
- `claude-code-ide-manager-session-ended` without FORGET calls `claude-code-ide-remote-project-invalidate … 'session-ended`, not Project-view cleanup (FR-012).
- The test `claude-code-ide-test-local-zmx-stop-and-detach-disconnected-rows` already states that "a plain buffer kill would keep" a live local row.

**Alternatives considered**:
- Copy `claude-code-ide-manager-detach-at-point` without the forget step. Rejected. Detach captures and runs Project-view cleanup and calls `session-ended KEY t`. A copy would duplicate about 70 lines to remove two of them.
- Add a `disconnect` disposition to `--cleanup-on-exit`. Rejected. The nil disposition already gives the required result.

## R2. Guards

**Decision**: Disconnect signals `user-error` and changes nothing in these cases, in this order:

1. No target. Manager: "No manager session at point". `M-x`: "No Session in the current buffer".
2. The row is already disconnected (no live Session in the registry and no live Session buffer): "Session is already disconnected. Press c to reattach".
3. The Session has no zmx name: "Session is not zmx-backed".
4. A remote request is in flight (`claude-code-ide--remote-target-pending-reason`): "Cannot disconnect NAME on HOST. REASON is already in progress".

**Rationale**: Guard 3 protects the Agent (spec US3). A buffer kill on a plain Session ends its process. Guards 1, 2, and 4 follow the messages of `detach-at-point` and `reattach-at-point`, so the user sees one vocabulary.

**Alternatives considered**: Ask for confirmation. Rejected. Disconnect ends no Agent, and `c` reverses it (spec Assumptions).

## R3. Command placement

**Decision**: The core command is `claude-code-ide-disconnect (&optional session-id)` in `claude-code-ide.el`. It is autoloaded and interactive. Without SESSION-ID, it uses `claude-code-ide--session-for-buffer` only, with no project or directory fallback. The manager command `claude-code-ide-manager-disconnect-at-point` resolves the row at point, calls the core command with the row's key, and moves point back to the row.

**Rationale**: `claude-code-ide-stop` and `claude-code-ide-manager-stop-at-point` already use this split. A project fallback could disconnect a Session that the user did not mean (FR-015 says "the Session of the current buffer").

**Alternatives considered**: One manager-only command. Rejected by clarification Q1.

## R4. Local and remote differences

**Decision**: There is one code path. Guard 4 can fire only for remote rows, because only remote targets start request processes. The local zmx check after the kill (R1) is spec 019 behavior and is not new to this feature.

**Rationale**: Constitution principle VI requires the plan to name each difference and its constraint. The constraint is that remote reattach and stop run as asynchronous request processes, and a buffer kill during one of them races with it.

## R5. Window and active Session

**Decision**: Disconnect adds no window code. The buffer kill reaches `claude-code-ide--close-session-windows` through `--cleanup-on-exit` and `--cleanup-session-resources`. That function deletes every window that shows the terminal, split and side windows included. Emacs refuses to delete a frame's sole main window, so that window shows the buffer that the kill picks. `session-ended` clears `:active-session-key` for the key and activates nothing else.

**Rationale**: Clarification Q2 chose the buffer-kill result.

## R6. IDE link of a local claude Session

**Decision**: Disconnect keeps the buffer-kill teardown. For a local `claude` Session, `claude-code-ide--cleanup-session-resources` stops the Session's MCP server (claude-code-ide.el:1217). Reattach starts a new MCP server, but the running Agent keeps the old port from its zmx environment. The IDE link of that Agent is lost until it restarts. This is the existing README known limitation for a buffer kill or an Emacs restart. Oh My Pi rediscovers the SSE endpoint and reconnects.

**Rationale**: The user asked for the Emacs-restart result, and a restart loses the same link. A kept MCP server without its buffer would hold a port that no reattach uses.

**Alternatives considered**: Skip the MCP teardown for a Disconnect. Rejected: reattach would still bind a second server, so the Agent gains nothing without a port handoff.
