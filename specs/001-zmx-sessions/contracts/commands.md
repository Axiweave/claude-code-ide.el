# Contract: user-facing commands and options

Phase 1 output. This is the package's external interface for the feature:
Emacs commands, defcustoms, and the zmx invocations Emacs emits. Requirement
ids reference [spec.md](../spec.md).

## Defcustoms

| Symbol | Type | Default | Contract |
|---|---|---|---|
| `claude-code-ide-use-zmx` | boolean | nil | nil = zero zmx involvement, behavior identical to today (FR-001). Non-nil = every new session runs under zmx (FR-002). |
| `claude-code-ide-zmx-program` | string | `"zmx"` | executable name or path; resolved with `executable-find` at point of use (FR-009). |
| `claude-code-ide-zmx-session-prefix` | string | `"cci-"` | leading component of generated zmx session names (FR-003). |

## Commands

### Session start (existing commands, changed behavior when `claude-code-ide-use-zmx` is non-nil)

- Plain start: query `zmx list`; offer sessions named `<prefix><agent>-<project>-*`
  that have no live attached buffer in this Emacs instance, via
  `completing-read` including a "create new" candidate. No eligible match →
  create silently (FR-006).
- Start with continue/resume: never offer; always create a new zmx session
  running the flagged command (FR-006, clarification 2026-08-28).
- Creation runs the terminal with
  `zmx attach <name> <agent-argv...>` (FR-002, research R3).

### `claude-code-ide-attach` (new, interactive)

1. `zmx list` → candidates annotated with `start_dir` and `cmd` (FR-007).
2. Selection → CLI type inferred from `cmd` head; prompt on no match (FR-008).
3. Opens a terminal buffer running `zmx attach <name>`; mints a fresh
   session-id; registers a full Session (buffer, idle tracking, manager).
- Empty `zmx list` → message, no error. Missing zmx → `user-error` (FR-009).

### `claude-code-ide-stop` (existing, changed for zmx-backed sessions)

- Session has a `zmx-name` → `yes-or-no-p` naming the zmx session; on
  confirmation run `zmx kill <name>`, then normal cleanup (FR-005).
- Decline → no action. Session without `zmx-name` → unchanged behavior.

### Detach surfaces

- Buffer kill, window close, Emacs exit: detach only, never prompt, never
  kill (FR-004).
- Manager `X` detaches its selected zmx-backed session by killing only the
  local session buffer.

## Emitted zmx invocations (complete list)

| Invocation | Trigger |
|---|---|
| `zmx attach <name> <argv...>` | session creation (terminal command) |
| `zmx attach <name>` | reattach / adoption (terminal command) |
| `zmx list` (fallback `zmx list --short`) | start offer, `claude-code-ide-attach` |
| `zmx kill <name>` | confirmed `claude-code-ide-stop` |

No other zmx subcommand is invoked (research R1).
