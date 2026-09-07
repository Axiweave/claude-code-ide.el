<!--
Sync Impact Report
Version change: 1.0.0 -> 1.1.0 (new principle)
Modified principles: none
Added section: VI. Local and Remote Workflow Parity
Removed sections: none
Dependent templates and commands: unchanged, read constitution at runtime
Deferred feature work: apply confirmed interview decisions to 005-remote-rpc-magit
after the user confirms shared understanding. Keep the active feature unchanged.
Deferred placeholders: none
-->

# claude-code-ide.el Constitution

Governing principles for changes to this Emacs package. It provides
project-aware terminal sessions for Claude Code, Codex, OpenCode, Pi, and
Oh My Pi (omp), plus MCP integration for Claude Code. When a spec, plan, or
task conflicts with this document, this document wins.

## Core Principles

### I. Shared Session Core, Thin Agent Adapters

All agents route through the shared layers: session setup and interaction
(`claude-code-ide-session.el`), idle/working tracking
(`claude-code-ide-session-idle.el`), and window/sidebar workflows. Code that
constructs an agent-specific CLI command stays isolated in its adapter; it
never leaks into the shared layers. A feature for one agent must not fork
session, terminal, or window logic — extend the shared layer with a
dispatch point instead. The agent list and CLI paths are user configuration,
not package policy: `claude-code-ide-agent-definitions` stays a `defconst`
baseline and the package ships no agent-selection command.

### II. Batch-Verifiable Quality Gate (NON-NEGOTIABLE)

Every change passes `./scripts/compile-and-test.sh`: byte-compilation of all
`*.el` files, then the full ERT suite in batch mode. New logic ships with
ERT tests in `claude-code-ide-tests.el`. Tests must run without a display
and without optional packages installed — mock vterm, websocket, and other
optional dependencies the way the existing suite does. A change that only
passes interactively, or only with optional packages present, is not done.

### III. Optional Dependencies Stay Optional

Hard `require` is allowed only for the declared `Package-Requires`
dependencies. Terminal backends (vterm, eat), diagnostics providers
(flycheck, flymake), and transport packages loaded at feature boundaries
(websocket, web-server) load via soft require — `(require 'foo nil t)` or
`condition-case` — and fail at the point of use with an actionable
`user-error` naming the missing package. The package must load, byte-compile,
and pass tests with none of them installed.

### IV. Terminal-Backend Neutrality

Backend-specific behavior dispatches on the live buffer (`derived-mode-p`
checks) inside the session layer. A new session feature works on vterm, eat,
and ghostel, or it degrades with an explicit, user-visible message for the
unsupported backend. Silent per-backend behavior differences are defects.

### V. Simplicity and Compatibility

Target Emacs 28.1+ per `Package-Requires`. No new runtime dependency without
written justification in the plan's Complexity Tracking table. Prefer the
smallest working change; delete code the change obsoletes in the same
change. No model or agent self-references in source code or commit messages.

### VI. Local and Remote Workflow Parity

For enabled capabilities, remote attachment and managed views MUST match
the corresponding local workflow unless a concrete remote constraint requires
a difference. Use local behavior as the reference for commands, layout,
focus, view reuse, and navigation. This avoids a separate workflow merely
because an Agent runs on another host.

Feature specifications and plans MUST identify each required difference and
its remote constraint. Preserve existing local behavior and disabled remote
behavior when adding optional capabilities. Preserve the local distinction
between initial project-view preparation and later layout restoration.

Parity MUST preserve explicit host approval, optional dependencies, and safe
session ownership. Remote project-access failures MUST leave terminal
attachment independent and usable. Report unavailable capabilities explicitly
instead of silently changing security, installing software, or replacing the
requested operation.

## Elisp Standards

- Every file uses `lexical-binding: t` and the GPL-3+ header block.
- Public symbols use the `claude-code-ide-` prefix; internal symbols use a
  `--` separator (e.g. `claude-code-ide--get-session-buffer`).
- Formatting is what `./scripts/format-and-clean.sh` produces: standard
  Emacs Lisp indentation, spaces only, no trailing whitespace. Treat
  unexpected formatter indentation as a syntax diagnostic (unbalanced
  parentheses or quotes).
- Cross-file references to non-required code use `declare-function` and
  `defvar` forward declarations, not hard requires.

## Development Workflow

- Specs and tasks live in spec-kit under `.specify/`; create features with
  `.specify/scripts/bash/create-new-feature.sh`. There is no external issue
  tracker.
- Domain vocabulary and decisions live in `CONTEXT.md` and `docs/adr/` per
  `docs/agents/domain.md`; create them lazily, and flag ADR conflicts
  instead of silently overriding them.
- Work on the current branch. Never commit unless the user asks. Respect
  `.gitignore`. Keep `docs/superpowers/` local and uncommitted.
- When a change makes AGENTS.md incorrect, update AGENTS.md in the same
  change.

## Governance

This constitution supersedes other practice documents for spec-kit work.
The `/speckit.plan` Constitution Check gate verifies plans against the Core
Principles; violations require a Complexity Tracking entry justifying why no
simpler alternative works. Amendments edit this file, bump the version
below (semver: principle removals or reversals are MAJOR, new principles or
sections MINOR, wording fixes PATCH), and update AGENTS.md if the two
diverge.

**Version**: 1.1.0 | **Ratified**: 2026-08-28 | **Last Amended**: 2026-09-06
