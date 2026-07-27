# AGENTS.md

This file provides guidance to coding agents working in this repository.

If an instruction here becomes incorrect or outdated, update this file in the same change. `CLAUDE.md` is a compatibility symlink to this canonical guide.

## Project overview

This Emacs package provides project-aware terminal sessions for Claude Code, Codex, OpenCode, Pi, and Oh My Pi (`omp`). Session management, terminal integration, and window workflows are shared across agents; MCP integration is currently specific to Claude Code.

## Architecture

**Core files:**

- `claude-code-ide.el` — entry points, CLI dispatch, process tracking, and window workflows
- `claude-code-ide-session.el` — shared terminal-session setup and interaction
- `claude-code-ide-session-idle.el` — idle and working-state tracking
- `claude-code-ide-manager.el` — global and repository-local session sidebars and persisted layouts
- `claude-code-ide-transient.el` — transient menus

**Claude Code MCP files:**

- `claude-code-ide-mcp.el` — WebSocket server, JSON-RPC handling, and MCP session state
- `claude-code-ide-mcp-handlers.el` — file, diff, diagnostics, and editor-state tools
- `claude-code-ide-mcp-server.el` — MCP tools server framework
- `claude-code-ide-mcp-http-server.el` — HTTP transport
- `claude-code-ide-emacs-tools.el` — xref, project, tree-sitter, and Imenu tools
- `claude-code-ide-diagnostics.el` — Flycheck and Flymake integration

**Development files:**

- `claude-code-ide-debug.el` — debug logging
- `claude-code-ide-tests.el` — ERT test suite and dependency mocks
- `scripts/compile-and-test.sh` — byte compilation and full test suite
- `scripts/format-and-clean.sh` — formatting and whitespace cleanup

## Development workflow

Run the full verification suite with:

```bash
./scripts/compile-and-test.sh
```

Run ERT directly when needed:

```bash
emacs -batch -L . -l ert -l claude-code-ide-tests.el -f ert-run-tests-batch-and-exit
```

Add tests for new logic. The suite mocks optional dependencies such as vterm and WebSocket so it can run in batch mode.

Claude Code hooks in `.claude/settings.json` format edited Elisp and run the verification script on stop. Other agents must run the equivalent checks explicitly.

For WebSocket debugging, record traffic between VS Code and Claude Code with:

```bash
./record-claude-messages.sh [working_directory]
```

Debug logging can also be enabled in Emacs; ask the user for the resulting log when local reproduction is insufficient.

## Editing guidelines

- Treat formatter indentation as a syntax diagnostic: unexpected indentation usually indicates unbalanced parentheses or quotes.
- Keep agent-specific command construction isolated while routing shared behavior through the session layer.
- Do not add model or agent self-references to source code or commit messages.
- Work on the current branch; do not create a worktree unless the user requests one.
- Prefer subagent-driven development when executing a written implementation plan.
- Keep `docs/superpowers/` local and uncommitted.
- Respect `.gitignore`; never use `git add -f` unless the user explicitly requests it.
- Never commit changes unless the user explicitly asks.
