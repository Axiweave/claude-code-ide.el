# Implementation Plan: Fix Remote Session Toggle

**Branch**: `main` | **Date**: 2026-09-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/011-fix-remote-toggle/spec.md`

The setup script returned `011-fix-remote-toggle` as its feature identifier. The active Git branch is `main` and remains unchanged.

## Summary

Make `claude-code-ide-toggle` select the exact live Session associated with the invoking terminal or managed project view before it uses local directory fallback. Preserve host identity, existing layout behavior, local project lookup, and the no-session error. Add no remote request, state field, dependency, or new user command.

## Technical Context

**Language/Version**: Emacs Lisp, Emacs 28.1 or later.

**Primary Dependencies**: Existing Session accessors, manager layout state, and window-toggle helpers. Ghostel remains optional and is the sole supported terminal runtime. No new package dependency.

**Storage**: Existing in-memory Session registry and manager layout table. No persistence or schema change.

**Testing**: Focused ERT regressions in `claude-code-ide-tests.el`, followed during implementation by `./scripts/compile-and-test.sh`.

**Target Platform**: Supported Emacs hosts with local Sessions or attached remote Agent Sessions.

**Project Type**: Emacs package with interactive commands and managed terminal layouts.

**Performance Goals**: Resolve and toggle one Session in one invocation. Use only in-memory lookups and buffer identity checks.

**Constraints**: No network access, discovery, attachment, reattachment, Agent start, new prompt, alternate terminal, or local behavior change. Remote Session directories remain bare host metadata.

**Scale/Scope**: One interactive command, one private manager context resolver, focused ERT coverage, and existing command documentation if it becomes inaccurate.

## Constitution Check

*GATE: Passed before Phase 0 research and after Phase 1 design.*

| Gate | Before research | After design | Evidence and planned compliance |
| --- | --- | --- | --- |
| I. Shared Session core | Pass | Pass | The shared toggle command resolves a Session once. No Agent-specific path or adapter changes. |
| II. Batch-verifiable quality | Pass | Pass | Public-command ERT regressions cover terminal, managed view, collisions, fallback, and no-session behavior. The full script remains the implementation gate. |
| III. Optional dependencies | Pass | Pass | No new dependency or hard require. Toggle resolution uses existing in-memory state. |
| IV. Ghostel-only terminals | Pass | Pass | The plan changes Session selection only. It adds no terminal implementation or fallback. |
| V. Simplicity and compatibility | Pass | Pass | Reuse Session ownership, manager layout state, and the existing window-toggle helper. Add one private resolver only where view ownership varies. |
| VI. Local/remote parity | Pass | Pass | The same command and layout behavior apply locally and remotely. Host-qualified identity prevents cross-host selection. |
| ADR 0003 | Pass | Pass | Keep remote host and bare directory separate. Do not treat remote metadata as a local path. |
| Repository workflow | Pass | Pass | Work stays on `main`. Planning creates only feature artifacts and no commit. |

No gate violation or unresolved clarification remains.

## Project Structure

### Documentation (this feature)

```text
specs/011-fix-remote-toggle/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── session-toggle.md
└── checklists/
    └── requirements.md
```

`tasks.md` belongs to `/speckit.tasks` and is not created by this command.

### Source Code (repository root)

```text
claude-code-ide.el          # Interactive toggle resolution
claude-code-ide-manager.el  # Exact managed-view Session resolver
claude-code-ide-tests.el    # Public-command regression coverage
README.org                  # Update only if existing toggle guidance becomes inaccurate
scripts/compile-and-test.sh # Required implementation gate, unchanged
```

**Structure Decision**: Extend the two existing modules that already own Session commands and managed layout state. Do not add a context module, remote toggle command, state table, or transport logic.

## Phase 0: Research Results

See [research.md](research.md).

Resolved decisions:

- The reported failure comes from directory-first resolution that skips exact terminal ownership and loses host identity.
- `claude-code-ide-stop` provides the existing exact-Session-first pattern.
- A managed project view must resolve through exact saved-layout buffer ownership, not host and directory recency.
- Local project buffers retain the current directory fallback.
- Disconnected targets remain outside the live Session registry and never trigger reattach.

## Phase 1: Design

### Session Context Resolution

Add one private manager accessor with this interface:

```elisp
(claude-code-ide-manager--session-for-project-view-buffer &optional buffer)
```

The accessor reads the manager's existing active Session key. It returns that live Session only when its saved `:project-view-buffer` is exactly `buffer` and its terminal is live. It returns nil for unrelated buffers, dead views, and disconnected targets.

This is a constant-size lookup through the existing active key and layout table. It does not scan layouts, call remote-project internals, make a remote call, or mutate manager state. Add only the required cross-file declaration. Do not add a new `require`.

### Toggle Command

Update `claude-code-ide-toggle` to:

1. Resolve the Session that directly owns the current terminal buffer, following the established `claude-code-ide-stop` hierarchy.
2. If no terminal owns the buffer, ask the manager accessor for an exact managed project-view owner.
3. If a Session is found, preserve its host, live terminal buffer, and bare directory.
4. If no Session is found and the current buffer is remote, signal the existing no-session `user-error` without directory fallback.
5. Otherwise, call the existing attached-working-directory and local session-buffer fallback unchanged.
6. Pass the selected buffer and directory to `claude-code-ide--toggle-existing-window` unchanged.

Do not change `claude-code-ide--get-session-buffer`. Its broader callers do not need this feature, and changing it would widen the regression surface. If a future host-qualified non-view context needs directory lookup, pass the preserved host to `claude-code-ide--preferred-session` at that caller.

### Data and Interface

- [data-model.md](data-model.md) documents the existing Session and layout values used by resolution.
- [contracts/session-toggle.md](contracts/session-toggle.md) defines target precedence, errors, side-effect limits, and compatibility.
- [quickstart.md](quickstart.md) defines focused batch and live validation.

### Verification Design

Add focused public-command ERT cases:

1. A remote terminal wins over a local Session with identical directory text.
2. Each of two remote terminals with the same directory and Session name selects its own host-specific Session.
3. The active managed remote project view selects its exact layout Session, including when a sibling shares host and directory.
4. An unrelated RPC buffer does not inherit the manager's active Session or fall back to a same-path local Session.
5. A disconnected remembered target does not attach and produces the existing no-session result.
6. A local terminal still selects itself.
7. A local project buffer still uses the existing directory fallback.

Capture the buffer and directory passed to `claude-code-ide--toggle-existing-window`. Do not assert internal scan order or exact error wording.

During implementation, run focused ERT coverage first. Then run `./scripts/compile-and-test.sh`. After success, reload changed Elisp with `emacsclient` and perform the live steps in [quickstart.md](quickstart.md).

## Complexity Tracking

No constitution violation requires an exception.
