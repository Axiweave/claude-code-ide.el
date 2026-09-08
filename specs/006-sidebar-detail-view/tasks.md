---

description: "Task list for feature implementation"
---

# Tasks: Sidebar Detail View

**Input**: Design documents from `specs/006-sidebar-detail-view/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/elisp-surface.md](contracts/elisp-surface.md), [quickstart.md](quickstart.md)

**Tests**: Test tasks are included and are NOT optional here. Constitution
principle II requires new logic to ship with ERT tests in
`claude-code-ide-tests.el`, passing in batch mode with no optional package
installed.

**Organization**: Tasks are grouped by user story so each story can be
implemented and tested on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel. Different file, no dependency on an incomplete task.
- **[Story]**: The user story the task serves (US1, US2, US3).
- Every task names its exact file path.

## Path Conventions

This package is a flat set of `claude-code-ide-*.el` files at the repository
root. There is no `src/` or `tests/` directory. Line numbers below refer to the
files as read on 2026-09-08 and will shift as tasks land, so re-read before
each edit.

## Parallelism warning, read before planning work

Almost every production change lands in one file,
`claude-code-ide-manager.el`. Concurrent edits to one file are not guaranteed
to merge, so those tasks are strictly sequential. The same applies to every
test task, because all tests live in `claude-code-ide-tests.el`.

Only three tasks touch a different file and are genuinely parallel: T010
(`claude-code-ide-transient.el`) and T017 (`README.md`). Do not manufacture
more parallelism than that. See [Parallel Opportunities](#parallel-opportunities).

---

## Phase 1: Setup

**Purpose**: Establish a known-good baseline, so any later failure is
attributable to this feature.

- [X] T001 Run `./scripts/compile-and-test.sh` from the repository root and record the baseline result. Expected: no unexpected byte-compilation warning and `All tests passed!`. If the baseline already fails, stop and report it before changing any code.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The title lookup and the face that every rendered detail line
needs. No user story can render a correct line until both exist.

**CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 Add the private helper `claude-code-ide-manager--item-title (item)` to `claude-code-ide-manager.el`, immediately after `claude-code-ide-manager--pin-order-item-names` (currently ending at line 2207). It resolves the item's Session with `claude-code-ide-manager--session-record`, reads `claude-code-ide-session-title`, flattens every newline run with `(replace-regexp-in-string "[\r\n]+" " " title)`, and returns `nil` for a missing Session record, a `nil` title, an empty string, or a whitespace-only string. Contract: [contracts/elisp-surface.md](contracts/elisp-surface.md#added-internal-helper).
- [X] T003 Change `claude-code-ide-manager--pin-order-item-names` in `claude-code-ide-manager.el` (lines 2194-2207) to call `claude-code-ide-manager--item-title` instead of performing the record lookup and the newline flattening inline. This MUST be behavior-preserving: the `claude-code-ide-manager-pin-order-show-titles` gate and the `> 1` duplicate-name condition stay exactly as they are. Rationale: D9 in [research.md](research.md#d9-one-place-normalizes-the-title).
- [X] T004 Add `defface claude-code-ide-manager-session-title-face` to `claude-code-ide-manager.el` at the end of the face block (after line 279), inheriting `shadow`, in group `claude-code-ide-manager`. It MUST NOT set `:extend t`. Rationale: D5 in [research.md](research.md#d5-a-face-inheriting-shadow-without-extend).
- [X] T005 Add an ERT test for the helper to `claude-code-ide-tests.el`, appended to the manager test block. Assert the boundaries only: a plain title returns unchanged, a title containing `\n` and `\r\n` returns one line with no control character, an empty title returns `nil`, a whitespace-only title returns `nil`, a `nil` title returns `nil`, and an item whose Session is absent from the registry returns `nil` rather than signaling.

**Checkpoint**: The title resolves to a clean single line or `nil`, and the dim face exists. User story work can begin.

---

## Phase 3: User Story 1 - Turn the detail view on and off (Priority: P1) 🎯 MVP

**Goal**: Pressing `V` in the sidebar adds a dim title line under every Session
that has a title, and pressing `V` again removes it. The view is off by
default.

**Independent Test**: Open a sidebar with at least two Sessions that have
terminal titles. Press `V` twice and compare the rendered buffer against the
compact baseline. Delivers the whole observable feature on its own.

### Implementation for User Story 1

- [X] T006 [US1] Add `defcustom claude-code-ide-manager-show-session-titles` to `claude-code-ide-manager.el` beside the other display flags (near line 197), default `nil`, `:type 'boolean`, group `claude-code-ide-manager`. Do not add a `:set` function yet, that is T015. Docstring must state that the value is the startup view and that `V` changes only the running Emacs.
- [X] T007 [US1] Emit the detail line in `claude-code-ide-manager--insert-item` in `claude-code-ide-manager.el`. Insert it AFTER the two `add-text-properties` calls that close the row (currently lines 2582-2609), never before. Emit only when `claude-code-ide-manager-show-session-titles` is non-nil AND `claude-code-ide-manager--item-title` returns non-nil. The line is `(propertize " " 'display '(space :align-to 7))`, then the title, then a newline, with `claude-code-ide-manager-session-title-face` applied to that range. Insertion order is what keeps the row status face off the new line. Rationale: D1 and D4 in [research.md](research.md#d1-a-real-buffer-line-inserted-after-the-row-closes).
- [X] T008 [US1] Add the command `claude-code-ide-manager-toggle-session-titles` to `claude-code-ide-manager.el`, beside `claude-code-ide-manager-toggle-grouped-view` (near line 2644). Flip `claude-code-ide-manager-show-session-titles` with plain `setq`, never `customize-set-variable`. Do not touch scope state and do not call `claude-code-ide-manager--save-state`. Then redraw every live manager sidebar: iterate `claude-code-ide-manager--manager-buffers` and call `claude-code-ide-manager--render` for each buffer's scope, the pattern `claude-code-ide-manager-refresh-all` uses at line 3115. Report the result and the title count, for example `Manager session titles: on (3 of 5 Sessions have a title)`. The count is the constitution principle IV mitigation and is part of the contract.
- [X] T009 [US1] Bind `V` to `claude-code-ide-manager-toggle-session-titles` in the keymap block of `claude-code-ide-manager.el` (lines 1208-1246). Add one `define-key` line and edit none. Lowercase `v` keeps `claude-code-ide-manager-toggle-grouped-view`.
- [X] T010 [P] [US1] Add one entry for `V` to the "Arrange" group of `claude-code-ide-manager-dispatch` in `claude-code-ide-transient.el` (lines 697-741), using the dynamic-description form the `v` entry already uses so `?` shows the current state. Exact shape: [contracts/elisp-surface.md](contracts/elisp-surface.md#added-dispatch-entry).
- [X] T011 [US1] Add ERT tests to `claude-code-ide-tests.el` for this story. Assert: with the option `nil` the rendered buffer text is identical to the compact baseline; with the option `t` a Session that has a title gains exactly one extra line carrying that title; a Session with no title still occupies exactly one line and adds no blank line; a sidebar where no Session has a title renders identically in both views; the toggle command flips the value and re-renders an open sidebar; the toggle's message names the resulting view. Build items and Sessions directly, as the existing manager render tests do, so no display and no optional package is needed.

**Checkpoint**: User Story 1 is complete. `V` works, the default is unchanged, and a Session with no title degrades to one row.

---

## Phase 4: User Story 2 - Read the title without losing the row (Priority: P1)

**Goal**: The title line reads and behaves as subordinate to its row. It is
dim, it is not a navigation target, and it still resolves to its Session for a
click or a command.

**Independent Test**: Render a sidebar with the view on. Inspect the face at
each position, walk the rows with `n` and `p`, run the `g` jump, and click a
title line. Testable without touching the toggle or the setting.

### Implementation for User Story 2

- [X] T012 [US2] In `claude-code-ide-manager--insert-item` in `claude-code-ide-manager.el`, apply `claude-code-ide-manager-session-key` to the detail-line range added in T007, so a click or a command on it resolves to the same Session through `claude-code-ide-manager--item-at-point` (line 2118). Do NOT apply `claude-code-ide-manager-session-name-start`, which is what keeps the line out of the Avy candidates (line 4260). Change no navigation function: `claude-code-ide-manager--move-point-to-session-key` (line 3235) scans forward from `point-min`, and a Session's row always precedes its own detail line, so the scan cannot stop on one. Rationale and the ordering argument: D2 and D3 in [research.md](research.md#d2-the-detail-line-does-carry-the-session-key-and-navigation-needs-no-change).
- [X] T013 [US2] Append the title to the row `help-echo` in `claude-code-ide-manager--insert-item` in `claude-code-ide-manager.el` (currently lines 2589-2606), only when `claude-code-ide-manager-show-session-titles` is non-nil and the title exists. Gating on the option is what keeps the compact view's text properties unchanged, per FR-002. This satisfies FR-017, because the sidebar truncates a long title. Rationale: D7 in [research.md](research.md#d7-the-tooltip-gains-the-title-only-in-the-detail-view).
- [X] T014 [US2] Add ERT tests to `claude-code-ide-tests.el` for this story. Assert: the detail line carries `claude-code-ide-manager-session-title-face`; no row status face appears anywhere in the detail-line range, including for a working, idle, and current Session; the title text begins at display column 7, matching the row label above it; a title containing a newline renders on one buffer line; exactly one position per Session carries `claude-code-ide-manager-session-name-start` in the detail view; the Session row count equals the visible Session count in the detail view; `claude-code-ide-manager--item-at-point` on a detail line returns the item of the row above; the `help-echo` contains the title when the option is on and does not when it is off. Count rows by `claude-code-ide-manager-session-name-start`, not by `claude-code-ide-manager-session-key`, per D10 in [research.md](research.md#d10-existing-tests-stay-green-and-new-tests-need-a-different-row-count).

**Checkpoint**: User Stories 1 and 2 both work. The title line is dim, unreachable by navigation, and clickable.

---

## Phase 5: User Story 3 - Set the default without pressing a key (Priority: P2)

**Goal**: A saved setting decides the view at startup, a customize change
updates an open sidebar at once, and a `V` press never rewrites the saved
value.

**Independent Test**: Set and save the option to `t`, confirm an open sidebar
updates with no manual refresh, press `V` to turn it off, restart Emacs, and
confirm the sidebar opens with title lines.

### Implementation for User Story 3

- [X] T015 [US3] Add the setter `claude-code-ide-manager--set-show-session-titles (symbol value)` to `claude-code-ide-manager.el`, immediately before the T006 `defcustom`, and wire it with `:set`. It calls `set-default`, then redraws every live manager sidebar with the same enumeration T008 uses. This satisfies Story 3 scenario 3. The T008 command must keep using plain `setq`, which bypasses this setter and leaves the saved value alone, which is why the command performs its own redraw. Rationale: D6 in [research.md](research.md#d6-a-setting-with-a-redraw-setter-and-a-toggle-that-bypasses-it).
- [X] T016 [US3] Add ERT tests to `claude-code-ide-tests.el` for this story. Assert: the default value is `nil`; invoking the setter through `customize-set-variable` re-renders an open sidebar without any explicit refresh call; the toggle command changes the running value while the customize saved value is untouched, which is the behavior the restart rule depends on; and `claude-code-ide-manager--serialize-state` still returns only `:version`, `:scopes`, and `:layouts`, proving the view never leaked into the manager state file.

**Checkpoint**: All three user stories work independently.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T017 [P] Document the new option, face, and `V` binding. This repository has no `README.md`, so the documentation landed in `CONTEXT.md`, which already defines Grouped view and Flat view. Added the `Compact view` and `Detail view` entries.
- [X] T018 Run `./scripts/compile-and-test.sh` from the repository root. Required result: no unexpected byte-compilation warning and `All tests passed!`. This is the non-negotiable gate from constitution principle II, and it satisfies SC-007.
- [X] T019 Load the change into a running Emacs and walk [quickstart.md](quickstart.md) steps 3 through 11. Use `emacsclient --eval '(load-file "claude-code-ide-manager.el")'` and the same for `claude-code-ide-transient.el`. Do not restart Emacs and do not use the desktop-control tool. This is the smoke test that proves the feature on the real surface, which the batch suite cannot do.
- [X] T020 Update `AGENTS.md` only if a statement in it became incorrect through this change. Checked: its only manager statement is the one-line file description at line 19, which stays correct. No edit made.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependency. Start here.
- **Foundational (Phase 2)**: needs T001. Blocks every user story.
- **User Story 1 (Phase 3)**: needs Phase 2.
- **User Story 2 (Phase 4)**: needs T007, because T012 and T013 edit the line T007 adds and the tooltip beside it. This is a real dependency, not a priority ordering.
- **User Story 3 (Phase 5)**: needs T006, because T015 wires `:set` onto that `defcustom`. Independent of US2.
- **Polish (Phase 6)**: needs every story you intend to ship.

### File-level ordering, the real constraint

`claude-code-ide-manager.el` receives T002, T003, T004, T006, T007, T008, T009,
T012, T013, and T015. Run them one at a time in that order, and re-read the
file before each edit, because every landed edit shifts the line numbers quoted
in these tasks.

`claude-code-ide-tests.el` receives T005, T011, T014, and T016. Also one at a
time.

### Within Each User Story

- Production change before its tests, because the repository validates with one
  batch gate rather than a red-green loop. A test written first here would only
  fail on a missing symbol, which proves nothing.
- The `defcustom` (T006) before the emit (T007), because the emit reads it.
- The emit (T007) before the property work (T012) and the tooltip (T013).

### Parallel Opportunities

Genuinely parallel, different files and no ordering between them:

- T010 in `claude-code-ide-transient.el`, once T008 has defined the command symbol.
- T017 in `README.md`, at any time after the contract is settled.

Everything else is same-file and sequential. There is no third parallel track,
and inventing one risks a lost edit.

---

## Implementation Strategy

### MVP scope

Phase 1, Phase 2, and Phase 3, that is T001 through T011. That yields a working
`V` toggle, off by default, with the title line rendered in the dim face at the
right column. It is demonstrable and shippable.

### Incremental delivery

1. Phase 1 and Phase 2 → the title resolves cleanly and the face exists.
2. Phase 3 → the feature works. **Stop and validate.** MVP.
3. Phase 4 → the title line behaves as a subordinate line under scrutiny.
4. Phase 5 → the setting drives startup and survives a restart correctly.
5. Phase 6 → docs, gate, and the live smoke test.

### Single-developer note

The template's parallel-team strategy does not apply. One file holds nearly all
the work, so a second developer would block on the first. Run the phases in
order.

---

## Notes

- Re-read `claude-code-ide-manager.el` before each edit. The line numbers in
  these tasks are from 2026-09-08 and shift as tasks land.
- Every new public symbol uses the `claude-code-ide-manager-` prefix, and every
  internal symbol uses the `--` separator, per the constitution's Elisp
  Standards.
- Formatting must match `./scripts/format-and-clean.sh` output. Treat surprising
  formatter indentation as a sign of unbalanced parentheses.
- Do not commit unless the user asks.
- The nine unchanged-surface guarantees in
  [contracts/elisp-surface.md](contracts/elisp-surface.md#unchanged-contract-this-feature-must-not-break)
  are the review checklist for the finished diff.

---

## Phase 7: Convergence

Appended by `/speckit.converge` on 2026-09-08, after `/speckit.implement`
completed T001-T020 and a `reviewer` pass. Each task names the requirement it
traces to and the gap type. Every claim below was verified by direct
measurement, not taken from the review.

- [X] T021 Preserve the selected Session row when a redraw changes the line count, per FR-015 and SC-005 (partial). Delete `claude-code-ide-manager--redraw-all-sidebars` in `claude-code-ide-manager.el` and call the existing `claude-code-ide-manager--refresh-sidebar-state` (line 3397) from both `claude-code-ide-manager-toggle-session-titles` and `claude-code-ide-manager--set-show-session-titles`. That function already renders every manager buffer and calls `set-window-point`, which is what `claude-code-ide-manager-toggle-grouped-view` does by hand. Measured defect: with the sidebar visible in an unselected window and its window point on Session 5, one toggle left the window point on line 1, a group heading. Add one ERT test in `claude-code-ide-tests.el` that renders into a window, selects another window, toggles, and asserts the window point still carries the same `claude-code-ide-manager-session-key`.
- [X] T022 Narrow `claude-code-ide-manager--title-prefix-regexp` in `claude-code-ide-manager.el` to a known chrome-glyph set, per FR-003 (partial). Replace `[^[:ascii:]]` with an explicit class holding `>`, `*`, `π`, `✳`, `✻`, and the braille block `⠀-⣿`. Keep the existing shape of one glyph followed by spaces, repeated, with an optional final glyph at end of string. Measured defects with the current class: `• Fix parser` loses its bullet, `> quoted work` loses its quote marker, `✨ ship it` loses its emoji, and `日 work` loses its first word. Measured miss: a real single-glyph title, `⠋ pnpm run build` from `refs/cmux/cmuxTests/GhosttyTitleUpdateIngressTests.swift:67`, must reduce to `pnpm run build`. Extend `claude-code-ide-test-manager-item-title-drops-status-glyphs` with all six cases.
- [X] T023 Add the missing cross-file forward declarations to `claude-code-ide-transient.el`, per the constitution's Elisp Standards (missing). Add `(declare-function claude-code-ide-manager-toggle-session-titles "claude-code-ide-manager" ())` beside the other manager declarations (lines 55-95) and `(defvar claude-code-ide-manager-show-session-titles)` beside the other manager variables (lines 131-136). The dispatch entry references both symbols today with neither declaration. The batch gate cannot catch this, because it byte-compiles with `(not free-vars unresolved)`.
- [X] T024 Reject a title that holds only non-ASCII whitespace in `claude-code-ide-manager--item-title` in `claude-code-ide-manager.el`, per FR-004 (partial). `string-trim` trims only space, tab, LF, and CR, so a title of one U+00A0 currently returns a one-character string and renders a visually blank detail line. Measured. Treat an all-whitespace result as no title. Add a U+00A0 case and a U+3000 case to `claude-code-ide-test-manager-item-title-drops-status-glyphs`.
- [X] T025 Reconcile the pin-order editor title contract in `specs/006-sidebar-detail-view/contracts/elisp-surface.md` (contradicts). The shared helper now strips status glyphs for the editor as well, so an editor row reads `claude-code-ide.el - Add detailed view with toggle command` where it used to read `claude-code-ide.el - π ⠋ Add detailed view with toggle command`. Measured live. Keep the one shared helper, because a second normalization path would duplicate the rule that FR-003 defines. Update the `claude-code-ide-manager-pin-order-show-titles` row of the unchanged table to state that the editor keeps one line per Session and one setting, and that its title text now drops the same status glyphs. Add one ERT test on `claude-code-ide-manager--pin-order-item-names` with a prefixed title, pinning the stripped output.
- [X] T026 Record `:initialize #'custom-initialize-default` in the "Added: user option" block of `specs/006-sidebar-detail-view/contracts/elisp-surface.md` (partial). The code requires it: without it, `custom-initialize-reset` calls the `:set` function during load, before `claude-code-ide-manager--manager-buffers` is defined, and loading `claude-code-ide-manager.el` fails. State that reason in one line, so a later edit does not remove the key.

**Checkpoint**: run `./scripts/compile-and-test.sh`. Required: no unexpected
byte-compilation warning and `All tests passed!`. Then reload with
`emacsclient --eval '(load-file "claude-code-ide-manager.el")'` and repeat the
T021 window-point check on the live sidebar.

### Convergence findings that produced no task

- Caching a title for a remembered remote Session. `claude-code-ide-manager--remember-remote-session` keeps a manager item after the Session record is removed, so a disconnected Session shows no detail line. A title cache would need a new `claude-code-ide-manager-item` slot, which the unchanged-surface table forbids, and a new state store, which Out of Scope forbids. The spec edge case reads "shows its remembered title if one exists", and no title store exists, so the current behavior satisfies it.
