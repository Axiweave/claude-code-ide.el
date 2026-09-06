# Context

Glossary for claude-code-ide.el. One term, one meaning.

## Terms

### Session
The Emacs-side object: keyed by session-id, holds the terminal buffer,
window state, and idle tracking. Without zmx, it owns the agent process
and dies with Emacs.

### Zmx session
A backend-owned persistent PTY managed by the external `zmx` program.
It survives Emacs restarts and buffer kills. Emacs is one attach client
among several; a plain terminal is another.

### Attach
Opening a terminal buffer (or terminal window) as a client of an
existing zmx session. The agent process does not restart.

### Detach
Closing an attach client while the zmx session and its agent process
keep running.

### Disconnected session
A Session whose connection to its zmx session has ended.
This does not establish whether the Agent has stopped or still runs.

### Adoption
Creating a Session for a zmx session that was launched outside Emacs,
so it gains a buffer, idle tracking, and manager visibility.

### Agent
One of the supported CLIs: Claude Code, Codex, OpenCode, Pi, Oh My Pi.

### Remote agent
An Agent that runs inside a zmx session on another machine owned by the user.
The user accesses it through an attached terminal in local Emacs.

### Configured host
A user-approved SSH destination for remote Agent access.
Its name identifies the host in the manager.

### Agent state
The lifecycle of a turn as the Agent itself reports it: idle, working,
needs input, done, or failed. Absent when the Agent does not report.

### Output idle
A Session whose terminal has produced no output for a while. Inferred
by Emacs, independent of Agent state.

## Known limitation
Environment variables (for example MCP/SSE ports) are fixed when the
zmx session is created. Attaching from a different Emacs instance, or
moving between Emacs and a terminal, keeps the original environment, so
port-based integrations break after such a switch. Accepted; not worked
around.
