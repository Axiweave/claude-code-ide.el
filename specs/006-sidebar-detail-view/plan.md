# Implementation Plan: Sidebar Detail View

**Branch**: `006-sidebar-detail-view` | **Date**: 2026-09-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/006-sidebar-detail-view/spec.md`

## Summary

Add an optional second line under each manager sidebar Session row that shows
that Session's terminal title in a dim face. The view is off by default. One
`defcustom` selects the startup view, and one command bound to `V` switches it
for the running Emacs.

The whole feature fits in one render function and one new option. The Session
already stores its terminal title, `claude-code-ide-manager.el` already
declares the accessor, and the sidebar already truncates long lines. So the
change adds no reader, no timer, no network call, and no new dependency.

The one non-obvious piece is column 7. The compact row reaches the Session
label at display column 7, so the detail line reuses the existing
`(space :align-to N)` idiom to start there.

## Technical Context

**Language/Version**: Emacs Lisp, `lexical-binding: t`, target Emacs 28.1+ per
`Package-Requires`.

**Primary Dependencies**: None new. The feature uses `cl-lib` and the manager's
own helpers. `claude-code-ide-session-title` is already forward-declared at
`claude-code-ide-manager.el:34`, so the title reads without a hard require.

**Storage**: One `defcustom`, saved by the customize interface. The manager
state file is not touched. `claude-code-ide-manager--serialize-state`
(`claude-code-ide-manager.el:1454-1460`) writes `:version`, `:scopes`, and
`:layouts`, and this feature adds no key to any of them.

**Testing**: ERT in `claude-code-ide-tests.el`, run in batch by
`./scripts/compile-and-test.sh`. Tests must pass headless with no optional
package installed.

**Target Platform**: Emacs 28.1+, GUI and TTY.

**Project Type**: Emacs package, single flat source tree at the repository
root.

**Performance Goals**: One extra `insert` per titled Session inside the
existing single render pass. The toggle calls the cheap redraw
(`claude-code-ide-manager--render`), never the item rebuild
(`claude-code-ide-manager-refresh-items`). Zero process starts and zero
network requests, per SC-006.

**Constraints**:

- `claude-code-ide-manager-window-width` defaults to 22
  (`claude-code-ide-manager.el:143`). The label column is 7. So about 15
  columns remain for the title at the default width. This is an accepted
  consequence of the indent decision, not a defect. A user who wants more
  title widens the sidebar.
- `truncate-lines` is already `t` in the sidebar mode
  (`claude-code-ide-manager.el:1304`), so a long detail line truncates with no
  new code. This satisfies the spec requirement that the line never wraps.
- The row status faces carry `:extend t`
  (`claude-code-ide-manager.el:242-271`). The detail line must be a separate
  buffer line with its own face, so the status highlight cannot bleed into it.

**Scale/Scope**: Tens of Sessions per sidebar. One production file changes, plus
the transient help and the test file.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Verdict | Evidence |
|---|---|---|
| I. Shared Session Core, Thin Agent Adapters | PASS | The feature reads one shared struct field, `claude-code-ide-session-title`. It adds no agent-specific branch and no CLI-specific code. The title is filled once, by the terminal title observer at `claude-code-ide.el:911-923`, which this feature does not touch. |
| II. Batch-Verifiable Quality Gate | PASS | New ERT tests cover the render, the toggle, and the no-title case. They construct items and Sessions directly, as the existing manager render tests do, so they need no display and no optional package. `./scripts/compile-and-test.sh` is the gate. |
| III. Optional Dependencies Stay Optional | PASS | No new `require`. The title accessor is already a `declare-function`. |
| IV. Terminal-Backend Neutrality | PASS with mitigation | The rendering code contains no `derived-mode-p` branch and behaves identically on vterm, eat, and ghostel. What differs is data: only ghostel reports a terminal title today, so vterm and eat Sessions have none and keep a single row. Principle IV requires an explicit, user-visible message rather than a silent difference, so the toggle reports how many Sessions have a title. Turning the view on in a sidebar with no titles says so, instead of appearing broken. |
| V. Simplicity and Compatibility | PASS | One new option, one new face, one new command, one new private helper, and two private constants that hold the title rules. No new runtime dependency, so the Complexity Tracking table stays empty. The duplicated title-normalization expression is extracted into the shared helper, and the feature reuses the existing sidebar refresh instead of adding a redraw function, so total code goes down, not up. |
| VI. Local and Remote Workflow Parity | PASS | The detail line renders the same way for a local and a remote Session. A disconnected remote Session shows its remembered title, because the title lives on the session struct in memory. The feature issues no SSH request and needs no host approval. |

**Result**: gate passes. No violation needs justification, so Complexity
Tracking below stays empty.

## Project Structure

### Documentation (this feature)

```text
specs/006-sidebar-detail-view/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # refs/ survey plus Phase 0 technical decisions
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── elisp-surface.md # Phase 1 output: public Elisp surface
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (repository root)

This package is a flat set of `claude-code-ide-*.el` files at the repository
root. There is no `src/` or `tests/` directory. The feature touches:

```text
claude-code-ide-manager.el     # all production changes
├── ~line 200                  #   new defcustom + :set setter, calls the
│                              #   existing --refresh-sidebar-state
├── ~line 298                  #   new defface, after the existing faces
├── ~line 1238                 #   new define-key for V
├── ~line 2231                 #   two title constants: whitespace and prefix
├── ~line 2251                 #   new --item-title helper; pin-order reuses it
├── 2613-2682                  #   --insert-item: emit the detail line
└── ~line 2720                 #   new toggle command, beside toggle-grouped-view

claude-code-ide-transient.el   # one dispatch entry in the "Arrange" group,
                               # plus its declare-function and defvar
claude-code-ide-tests.el       # new ERT tests, appended to the manager block
CONTEXT.md                     # document the option, face, and key
```

**Structure Decision**: no new file. The feature is a rendering variation of an
existing sidebar, so it belongs in `claude-code-ide-manager.el` beside the code
it varies. A new file would split one render path across two files for no gain.

## Implementation Approach

Six changes, in dependency order. All in `claude-code-ide-manager.el` unless
noted.

### 1. Title helper

Add `claude-code-ide-manager--item-title (item)`. It resolves the item's
Session record with the existing `claude-code-ide-manager--session-record`,
reads `claude-code-ide-session-title`, flattens every whitespace run to one
space, drops the leading agent status glyphs FR-003 names, and returns `nil`
for a missing, empty, whitespace-only, or glyph-only title.

`claude-code-ide-manager--pin-order-item-names`
(`claude-code-ide-manager.el:2194-2207`) already performs exactly this lookup
and exactly this newline flattening inline. Change it to call the helper. One
helper holds the rule FR-003 defines, so a second normalization path never
appears.

The extraction preserves what the spec non-goal protects: the pin-order editor
keeps one line per Session, one title control, and its own
`pin-order-show-titles` setting. It does change one thing. An editor row now
reads `repo - Alpha work` where it read `repo - π ⠋ Alpha work` before,
because the shared helper strips the glyphs for every caller. That deviation
is recorded in
[contracts/elisp-surface.md](contracts/elisp-surface.md#unchanged-contract-this-feature-must-not-break)
and pinned by
`claude-code-ide-test-manager-pin-order-titles-drop-status-glyphs`.

### 2. Face

Add `claude-code-ide-manager-session-title-face`, inheriting `shadow`, in the
face block at `claude-code-ide-manager.el:242-279`. It must NOT set
`:extend t`. The status faces extend to the window edge to paint a full-width
row highlight, and the detail line must not look like a row.

`shadow` is the Emacs equivalent of the cmux reference: a foreground blended
toward the background rather than a different hue. It also tracks the user's
theme, which a hard-coded hex color would not.

### 3. Option

Add `claude-code-ide-manager-show-session-titles`, default `nil`, `:type
'boolean`, with a `:set` function that calls `set-default` and then redraws
every live manager sidebar. The redraw is required by Story 3 scenario 3, which
says a customize change updates an open sidebar with no manual refresh.

Redraw with `claude-code-ide-manager--refresh-sidebar-state`
(`claude-code-ide-manager.el:3401`), the existing display refresh. Called with
no argument it iterates `claude-code-ide-manager--manager-buffers`, calls
`claude-code-ide-manager--render` on each buffer's scope, and then syncs each
owned sidebar window's point. Use it, and not `refresh-items`, which rebuilds
items from the session registry. The window-point sync is what keeps the
selected row under the user's cursor when the line count changes, per FR-015.
A private helper of our own would render without that sync, so this feature
adds no redraw function.

### 4. Emit the detail line

In `claude-code-ide-manager--insert-item`, after the two
`add-text-properties` calls that close the row (`claude-code-ide-manager.el:2582-2609`),
append the detail line when the option is on and the helper returns a title:

- Insert `(propertize " " 'display '(space :align-to 7))`, then the title, then
  a newline. This reuses the idiom already at line 2567, which is the file's
  only existing use of `(space :align-to N)`.
- Apply `claude-code-ide-manager-session-title-face` to the inserted range.
- Apply `claude-code-ide-manager-session-key` to the range, so a click or a
  command on the detail line resolves to the same Session, per FR-009.
- Do NOT apply `claude-code-ide-manager-session-name-start`. Avy filters
  candidates on that property (`claude-code-ide-manager.el:4260-4279`), so
  omitting it keeps the detail line out of the `g` jump targets, per FR-008.

Insertion must come after the row's property calls, not before. Those calls use
`start` through `(point)`, so a detail line inserted first would be inside the
range and would receive the row status face.

The column-7 arithmetic: 1 column for the active marker, 2 for the fixed-width
marker gutter, normalized by `(space :align-to 3)`, then 3 for the `%2d.` slot,
then 1 separator space. That is 1 + 2 + 3 + 1 = 7.

### 5. Extend the tooltip

FR-017 requires a truncated title to stay fully readable through the row
tooltip. The current `help-echo` (`claude-code-ide-manager.el:2589-2606`) holds
the path, branch, zmx name, and reattach hint, but not the title. Append the
title to that string only when the option is on and a title exists. Gating on
the option keeps the compact view's rendering byte-identical, per FR-002.

### 6. Command, binding, and help

Add `claude-code-ide-manager-toggle-session-titles`, modeled on
`claude-code-ide-manager-toggle-grouped-view` (`claude-code-ide-manager.el:2623-2644`)
with three differences:

- Flip the value with plain `setq`, not `customize-set-variable`. This changes
  the running value and leaves the saved custom value alone, which is what
  clarification 1 requires. It also bypasses the `:set` redraw, so the command
  redraws itself.
- Do not touch scope state and do not call
  `claude-code-ide-manager--save-state`. The view is not manager state.
- Report the result and the title count, for example
  `Manager session titles: on (3 of 5 Sessions have a title)`. This satisfies
  FR-011 and is the principle IV mitigation.

Bind it to `V` in the keymap block (`claude-code-ide-manager.el:1208-1246`).
`V` is unbound in every `.el` file in the repository, and lowercase `v` holds
`toggle-grouped-view`, so the pair reads naturally. Add a matching entry to the
"Arrange" group of `claude-code-ide-manager-dispatch`
(`claude-code-ide-transient.el:697-741`), using the dynamic-description form
that the `v` entry already uses, so `?` shows the current state.

### Deliberately not done

- No overlay or `after-string`. A real buffer line is what the existing render
  tests can read with `buffer-substring`, and what `truncate-lines` already
  handles.
- No change to any navigation function. See decision D2 in
  [research.md](research.md#phase-0-technical-decisions) for the ordering
  argument that makes this safe.
- No change to the pin-order editor's behavior or its setting.
- No new state, no new hook, no new timer. The existing refresh triggers
  already redraw the sidebar when a title changes.

## Complexity Tracking

No Constitution Check violation, so this table is empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| None | — | — |

## Post-Design Constitution Re-check

Re-evaluated after Phase 1 produced the data model and the contract.

- The design adds no file, no dependency, and no state key. Principles III and
  V still pass.
- The design adds no `derived-mode-p` branch and no agent-specific path.
  Principles I and IV still pass, with the toggle message as the principle IV
  mitigation.
- The contract in [contracts/elisp-surface.md](contracts/elisp-surface.md)
  lists four new public symbols and one new key. All use the
  `claude-code-ide-manager-` prefix, and the private helper and its two
  constants use the `--` separator, per the Elisp Standards section.
- Remote and local render through the same path with no network call, so
  principle VI still passes.

**Result**: gate still passes.
