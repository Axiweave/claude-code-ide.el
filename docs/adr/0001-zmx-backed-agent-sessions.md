# zmx-backed agent sessions, Emacs as attach client

Status: accepted (2026-08-28)

Agent processes die with Emacs, and a terminal user cannot reach an
agent that Emacs started. We adopt zmx as an opt-in process owner
(`claude-code-ide-use-zmx`, default nil): Emacs wraps the built CLI
command in `zmx attach <name> <cmd>` and becomes one attach client
among several. Names follow `cci-<agent>-<project>-<id-short>` with a
configurable prefix.

## Considered options

- **Depend on term-sessions.el** (refs/emacs-term-sessions): rejected.
  Its own README calls the API unstable, it is not on MELPA, and it
  ships frontends, Org links, and a list UI we already have. The zmx
  surface we need is about five subprocess calls.
- **detached.el**: rejected. It is job-centered (captured logs, exit
  status), not interactive-terminal-centered.
- **Self-build a thin zmx adapter in the session layer**: chosen.

## Consequences

- Stop semantics invert: killing a buffer or exiting Emacs detaches
  and leaves the process running. Only the explicit stop command runs
  `zmx kill`, after a prompt naming the session.
- Terminal-launched sessions are adoptable: `claude-code-ide-attach`
  reads `zmx list` (fields include `start_dir` and `cmd`), infers the
  CLI type from `cmd`, takes the directory from `start_dir`, and mints
  a fresh session-id. On session start, matching `cci-<agent>-<project>-*`
  sessions are offered for reattach via completing-read, with a
  "create new" option.
- Environment is frozen at zmx-session creation. Attaching from a
  different Emacs instance or from a terminal keeps stale MCP/SSE
  ports. Accepted limitation, not worked around.
- Missing zmx fails at the point of use with a `user-error` naming the
  program, per the constitution's optional-dependency principle.
