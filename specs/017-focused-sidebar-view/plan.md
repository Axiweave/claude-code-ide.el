# Implementation Plan: Focused Sidebar View

**Branch**: `017-focused-sidebar-view` | **Date**: 2026-10-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/017-focused-sidebar-view/spec.md`

## Summary

Add a focused view to the manager sidebar. `f` toggles it, and a `defcustom`
selects it at startup. The view shows only Sessions with a monitored status
(session priority rank < 5), plus the active Session when it earned a row
during its current activation. It numbers the rows from 1.

The approach has three parts:

- **One choke point.** A new `claude-code-ide-manager--displayed-items` returns
  the sorted items and filters them when the view is on. Render, quick numbers,
  number keys, row and group navigation, and row moves use it, so all of them
  agree by construction.
- **One capture before acknowledgment.** Two paths acknowledge a Session
  before the sidebar renders. A manager switch acknowledges its target. The
  idle visibility handler acknowledges a Session that becomes visible by a
  window change, and it runs before the manager's window hook. So each path
  records that the target "earned" its row before anything acknowledges it.
  The switch commands do this as their first statement. A
  `window-configuration-change-hook` function at depth -90 does it for window
  changes (research R4). One variable holds the record. A stale record is
  harmless, because membership also requires that the Session is current.
- **No new status source, no persistence, no timer.**

## Technical Context

**Language/Version**: Emacs Lisp, Emacs 28.1+ (`Package-Requires`)

**Primary Dependencies**: none new. Uses the manager (`claude-code-ide-manager.el`), the idle tracking (`claude-code-ide-session-idle.el`, read only), and transient (`claude-code-ide-transient.el`, menu entry)

**Storage**: none. The customize setting only. The manager state file is unchanged

**Testing**: ERT in `claude-code-ide-tests.el`, batch through `./scripts/compile-and-test.sh`. The tests reuse the `claude-code-ide-tests--with-priority-sessions` fixture, which performs real switches

**Target Platform**: Emacs on macOS and Linux, with local and remote (zmx and SSH) Sessions

**Project Type**: Emacs package (single project)

**Performance Goals**: no change that a user can see. The filter is one rank lookup per Session per render, and the render already does that lookup for row faces

**Constraints**: no network or SSH request (FR-018). No change to switch acknowledgment (ADR 0002). Rendering with the option off must stay byte-identical (SC-004)

**Scale/Scope**: tens of Sessions. About 60 lines of Elisp in the manager, a 5-line transient entry, and docs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|---|---|---|
| I. Shared core, thin adapters | Pass | The manager and the idle layer are shared. No agent-specific code. The status rank already covers every agent |
| II. Batch-verifiable gate | Pass | New ERT tests use the existing mocks and switch fixture, with no display or optional package. The gate is `./scripts/compile-and-test.sh` |
| III. Optional dependencies stay optional | Pass | No new `require`. The transient entry lives in the file that already loads transient |
| IV. Ghostel-only terminal | Pass | Not affected. Status comes from the existing buffer-local state |
| V. Simplicity | Pass | No new dependency. One setter is renamed, not duplicated. The rename removes the old name in the same change |
| VI. Local and remote parity | Pass | The same membership rule applies to local and remote Sessions. A disconnected remote Session has no live buffer and therefore no status, the same as a local Session with no status. The headings come from the existing renderer. This is not a remote-specific difference |

**Post-design re-check**: Pass. The design adds one `defcustom`, one runtime
variable, four internal functions, one command, one key, and one menu entry. It
adds no Complexity Tracking entry.

**ADR check**: ADR 0002 (state acknowledged by viewing) stays in force. This
feature reads status before both existing acknowledgment paths: the manager
switch and the idle visibility handler. It never acknowledges on its own, and
it does not reorder or change the idle handler.

## Design

See [research.md](research.md) for the evidence and the rejected alternatives,
[data-model.md](data-model.md) for the membership rule and its state
transitions, and [contracts/elisp-surface.md](contracts/elisp-surface.md) for
the surface.

### Changes in `claude-code-ide-manager.el`

1. Rename `--set-show-session-titles` to `--set-and-refresh`, and update its
   one `:set` user.
2. Add the `defcustom claude-code-ide-manager-focused-view` with
   `custom-initialize-default` and `:set #'claude-code-ide-manager--set-and-refresh`.
3. Add the `defvar claude-code-ide-manager--focus-kept-session-key`.
4. Add `--focus-member-p` and `--note-focus-activation`, next to
   `--session-priority`.
5. Add `--displayed-items (scope &optional view)`, next to `--sorted-items`.
6. Route these callers through `--displayed-items`: `--render`,
   `--visible-session-keys`, `--displayed-groups`, `--neighbor-in-bucket`,
   `switch-by-slot`, and `switch-by-slot-preserve-focus`. Leave the pin-order
   editor, `--materialize-order-keys`, and `--swap-order` on the full list.
7. In `--render`, when the view is on, insert the dim
   `Focused: N of M` or `Focused: no Session needs attention` first line, with
   no Session key.
8. Call `--note-focus-activation` at the start of
   `claude-code-ide-manager-switch-to-session` and
   `claude-code-ide-manager-reset-layout`, before the current Session changes.
   For window-change activation, factor `--window-change-session-key` out of
   `--refresh-on-window-configuration-change`. Add
   `--note-focus-on-window-change` and install it at depth -90 in
   `--install-window-config-refresh-hook`. Do not call the note inside the
   refresh hook itself (research R4).
9. Add `claude-code-ide-manager-toggle-focused-view` and bind it to `f`.

### Other files

- `claude-code-ide-transient.el`: one "Arrange" entry for `f` (the key is free
  in `claude-code-ide-manager-dispatch`), a `declare-function` for the command,
  and a `defvar` for `claude-code-ide-manager-focused-view`, as for `V`.
- `claude-code-ide-tests.el`: the tests listed in
  [quickstart.md](quickstart.md#test-coverage-expected-in-claude-code-ide-teststel).
- `README.org`: add `f` to the sidebar key list and the `?` menu notes, and
  describe the focused view in one short paragraph near the grouped-view text.
- `CONTEXT.md`: add the "Focused view" term.

## Project Structure

### Documentation (this feature)

```text
specs/017-focused-sidebar-view/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── elisp-surface.md
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit.tasks output, not created here
```

### Source Code (repository root)

```text
claude-code-ide-manager.el     # setting, state, filter, render line, command, key
claude-code-ide-transient.el   # ? menu entry
claude-code-ide-tests.el       # ERT tests
README.org                     # key list and short description
CONTEXT.md                     # glossary term
```

**Structure Decision**: This is a single-package repository with flat `*.el`
files at the root. All logic goes into the existing manager file, next to the
code that it filters. No new file.

## Complexity Tracking

No constitution violations. This section is empty.
