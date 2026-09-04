---
status: accepted
---

# Agent state is one field; viewing a result folds `done`/`failed` into `idle`

Oh My Pi reports its turn state (`idle`, `working`, `needs-input`, `done`, `failed`) over MCP, and the manager shows it as a gutter glyph and row face. We keep a single buffer-local value, `claude-code-ide-session-agent-state`, and let Emacs rewrite `done` and `failed` to `idle` when the session buffer is visible in a focused frame, either at arrival or on a later visibility change. `needs-input` is never rewritten. The gutter therefore answers "do I need to look", and a seen result vanishes.

## Considered option: separate `unread` flag

Reference tools (cmux `markUnread`, herdr's `unseen`/`seen` ranking) keep the reported state intact and overlay an unread bit. That would keep `✓` visible after viewing, allow "N unread" counts and a "jump to newest unread" command, and let `needs-input` lose emphasis once seen while keeping its red face. Rejected for now: the counts and jump command are not wanted yet, the current model is simpler, and notifications can still fire from the setter at the moment a `done`/`failed`/`needs-input` report lands while the buffer is not visible. Revisit only if unread counts or a jump command become a real need; do not "fix" the `done → idle` rewrite in isolation.

## Consequences

- Emacs never tells Oh My Pi about the rewrite. Oh My Pi reconnects its SSE session every few minutes and re-announces `done` or `failed` under a new owner; Emacs keeps the acknowledged report across that owner change and ignores the unchanged replay. A new `working` report starts a new turn, so its later result remains visible.
- `idle` still arrives from Oh My Pi on its own: aborted turn, focus of a non-streaming session, startup, and reconnect re-announce.
- Oh My Pi publishes the turn result at `turn_end`, when the final text is on screen, not at `agent_end` after advisor catch-up (up to 30s). Emacs cannot detect that gap itself, so a late `done` would mark a result the user already read.
- Output idle (`claude-code-ide-session-idle-p`, the bell) is a separate field and path. It is untouched by this decision.
