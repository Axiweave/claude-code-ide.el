# Quickstart: Sidebar Detail View

**Feature**: `006-sidebar-detail-view` | **Date**: 2026-09-08

How to validate the feature. Read [plan.md](plan.md) for the approach,
[contracts/elisp-surface.md](contracts/elisp-surface.md) for the surface under
test, and [data-model.md](data-model.md) for the entities.

## Prerequisites

- Emacs 28.1 or later.
- This repository checked out, and the package loaded in a running Emacs with
  an `emacsclient` server.
- At least two live Sessions in the manager sidebar. For the detail line to
  appear, at least one Session must run on the Ghostel backend, because only
  Ghostel reports a terminal title today.

## 1. Batch quality gate

The non-negotiable gate from constitution principle II. Run it from the
repository root.

```bash
./scripts/compile-and-test.sh
```

Expected: no unexpected byte-compilation warning, and `All tests passed!`.

## 2. Run only this feature's tests

Faster loop while iterating.

```bash
emacs -batch -L . -l ert -l claude-code-ide-tests.el \
  --eval '(ert-run-tests-batch-and-exit "session-title")'
```

Expected: every selected test passes, and none is skipped.

## 3. Load the change into the running Emacs

Do not restart Emacs. Load the edited files with `emacsclient`.

```bash
emacsclient --eval '(load-file "claude-code-ide-manager.el")'
emacsclient --eval '(load-file "claude-code-ide-transient.el")'
```

Expected: each call returns `t`.

## 4. Prove the default changed nothing

This is SC-001, and it is the check most worth doing first.

1. Open the manager sidebar.
2. Confirm one line per Session, with the same marker, gutter, number, and
   label as before the change.
3. Confirm the option is off:

   ```bash
   emacsclient --eval 'claude-code-ide-manager-show-session-titles'
   ```

   Expected: `nil`.

## 5. Toggle the view on

1. Put point in the sidebar.
2. Press `V`.

Expected:

- A dimmer line appears under each Session that has a terminal title.
- The title line starts in the same column as the Session name above it.
- A Session with no title keeps one line, with no blank line added.
- The echo area reports the state and the count, for example
  `Manager session titles: on (3 of 5 Sessions have a title)`.
- The active Session, the window layout, and the selected row are unchanged.

Press `V` again. Expected: the sidebar returns to one line per Session.

## 6. Check the dim face and the row highlight

With the view on:

1. Put point on a title line and run:

   ```bash
   emacsclient --eval '(get-text-property (point) (quote face))'
   ```

   Expected: `claude-code-ide-manager-session-title-face`.

2. Find a Session that is working or idle, so its row carries a status
   highlight. Confirm the highlight paints the Session row and stops there. The
   title line below it must stay dim, not colored as a status row.

## 7. Check navigation and clicks

With the view on:

1. Press `n` and `p` repeatedly. Expected: point moves between Session rows
   only. It never rests on a title line, and no Session is skipped.
2. Press `g` for the Avy jump. Expected: one candidate per Session row, and no
   candidate on a title line.
3. Click a title line with the mouse. Expected: it switches to the Session on
   the row above, the same as clicking the row.
4. Confirm the Session numbers still run 1, 2, 3 with no gap, and that each
   number belongs to a Session row.

## 8. Check the tooltip

With the view on, hover a Session row whose title is too long for the sidebar.

Expected: the tooltip shows the full title alongside the path information it
already showed. This is FR-017.

## 9. Check the restart rule

This is clarification 1, and it is the behavior most likely to regress.

1. Set and save the option to `t` through `M-x customize-option`.
2. Confirm an open sidebar gains title lines with no manual refresh. This is
   Story 3 scenario 3.
3. Press `V` to turn the view off for this Emacs.
4. Restart Emacs and open the sidebar.

Expected: the sidebar opens WITH title lines, because the saved value is `t`
and the `V` press was never saved.

## 10. Check the pin-order editor is untouched

With the view on, press `E` to open the pin-order editor.

Expected: one line per Session, exactly as before. The editor's own title
behavior still follows `claude-code-ide-manager-pin-order-show-titles` and
ignores the new option.

## 11. Check the grouped arrangement

With the view on, press `v` to switch between the flat and grouped
arrangements.

Expected: title lines appear in both. Group headings gain no title line.
`C-j` and `C-k` still jump between groups.

## Test coverage expected in `claude-code-ide-tests.el`

Each test below defends an observable contract, and each would fail on a
plausible bug. Nothing here asserts wiring or a default value.

| Test | Fails when |
|---|---|
| Compact view is unchanged with the option off | the option leaks into the default rendering |
| Detail line renders for a Session with a title | the gate or the title lookup is wrong |
| Detail line starts at the label column | the alignment breaks, which is the visible defect |
| No detail line for a Session with an empty or whitespace-only title | the empty check is missing, producing a blank line |
| No detail line for a Session with no record | the lookup does not tolerate a missing Session |
| A title containing a newline renders on one line | the flattening is dropped, which would corrupt every row below |
| The title line carries the dim face and no status face | the row property range swallows the title line |
| Exactly one `session-name-start` position per Session in the detail view | Avy gains a duplicate candidate |
| Row count equals Session count in the detail view | a title line is counted as a row |
| The toggle changes the running value and not the saved value | the toggle uses `customize-set-variable` and breaks the restart rule |
| The toggle leaves the serialized state keys unchanged | the view leaks into the manager state file |

Count rows by the `claude-code-ide-manager-session-name-start` property, not by
`claude-code-ide-manager-session-key`. See D10 in
[research.md](research.md#d10-existing-tests-stay-green-and-new-tests-need-a-different-row-count).

## Cleanup

After the gate passes, remove any scratch file used for manual checks. Update
`README.md` with the new option, face, and key. Update `AGENTS.md` only if this
change makes a statement in it incorrect.
