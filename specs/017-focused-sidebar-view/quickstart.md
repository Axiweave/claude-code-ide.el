# Quickstart: Focused Sidebar View

**Feature**: `017-focused-sidebar-view` | **Date**: 2026-10-01

This guide shows how to validate the feature. See [plan.md](plan.md) for the
approach, [contracts/elisp-surface.md](contracts/elisp-surface.md) for the
surface, and [data-model.md](data-model.md) for the membership rule.

## Prerequisites

- Emacs 28.1 or later, with an `emacsclient` server.
- This repository loaded in that Emacs.
- Several live Sessions in mixed states. The best case matches the reference
  screenshot: two working remote Sessions on one host, one working local
  Session past row 10, and several quiet Sessions.

## 1. Batch quality gate

```bash
./scripts/compile-and-test.sh
```

Expected: no unexpected byte-compilation warning, and 0 unexpected results.

## 2. This feature's tests only

```bash
emacs -batch -L . -l ert -l claude-code-ide-tests.el \
  --eval '(ert-run-tests-batch-and-exit "focused-view")'
```

Expected: every selected test passes and none is skipped.

## 3. Load the change into the running Emacs

```bash
emacsclient --eval '(load-file "claude-code-ide-manager.el")'
emacsclient --eval '(load-file "claude-code-ide-transient.el")'
```

Expected: each call returns `t`.

## 4. Default is unchanged (SC-004)

```bash
emacsclient --eval 'claude-code-ide-manager-focused-view'
```

Expected: `nil`. The sidebar looks the same as before the change.

## 5. Filter and numbers (US1, US2, SC-001)

1. Put point in the global sidebar.
2. Press `f`.

Expected:

- The first line reads `Focused: N of M` in a dim face.
- Only working, waiting, failed, done, and unseen-idle Sessions remain.
- The rows show numbers `1` to `N` with no gap. The former `-` row has a number.
- In the grouped arrangement, `[v12mac]` and `v12x` still head their rows, and
  headings with no rows are gone.
- The echo area reads `Manager focused view: on (N of M Sessions)`.
- The active Session, the layout, and focus do not change.

Check that the rendered rows and the number keys agree:

```bash
emacsclient --eval '(with-current-buffer (car (claude-code-ide-manager--manager-buffers))
  (claude-code-ide-manager--visible-session-keys (quote (:type global))))'
```

Expected: the keys in the same order as the rows. Press `3` and confirm the
switch goes to row `3`.

## 6. Lifecycle (US3)

1. Make one Session output-idle or `done`.
2. Press its number.
   - Expected: it is the active row, it stays visible, and its number stays.
3. Press another row's number.
   - Expected: the first Session is gone, and the rows renumber from 1.
4. Repeat with a `needs-input` Session.
   - Expected: it stays after you leave, because a switch does not acknowledge
     `needs-input`.
5. Press `!`, which clears all idle state.
   - Expected: every acknowledged Session leaves, except the active Session if
     it was visible.
6. Make another Session output-idle or `done`. Show it with `C-x b` in the
   content window, not with a manager key.
   - Expected: it becomes the active row and stays visible, although the idle
     visibility handler has already cleared it. A switch away removes it.
   - Check the hook order:

     ```bash
     ~/bin/emacsclient --eval '(seq-filter (lambda (f) (and (symbolp f) (string-match-p "claude-code-ide" (symbol-name f)))) (default-value (quote window-configuration-change-hook)))'
     ```

     Expected: `claude-code-ide-manager--note-focus-on-window-change` comes
     before `claude-code-ide-session-idle--handle-visibility-change`.

## 7. Empty state

1. Clear or finish every Session.
2. Switch to a quiet Session.

Expected: the sidebar shows only `Focused: no Session needs attention`.

## 8. Startup setting

1. Run `M-x customize-option RET claude-code-ide-manager-focused-view` and set
   it to on.
   - Expected: an open sidebar becomes focused with no refresh.
2. Press `f` to turn it off.
3. Restart Emacs.
   - Expected: the sidebar starts focused, because the `f` press was never
     saved.

## 9. Things that must keep the full list

- Press `E`. Expected: the pin-order editor lists every Session.
- Press `f` to turn the focused view off. Expected: the full list returns
  exactly as before, with the original numbers.

## Test coverage expected in `claude-code-ide-tests.el`

Use `claude-code-ide-tests--with-priority-sessions`, which performs real
switches. Each test proves a property, not a copy of the code.

| Test | Property | Fails when |
|---|---|---|
| Rows, numbers, and keys agree | For every status mix from a fixed-seed generator over the six statuses, in flat and grouped arrangements, the rendered row keys equal `--visible-session-keys`. Row N shows number N. `switch-by-slot N` reaches row N | numbers or keys still index the full list |
| Filter equals membership | Rendered rows are exactly the Sessions with rank < 5, plus a kept active Session. They form a subsequence of the full-view rows | a status is missing from the monitored set, or the order changes |
| Off shows everything | With the option nil, the rendered row keys equal the full sorted list for every generated status mix, and no `Focused:` line appears. The existing render tests cover byte-identical output | the filter leaks into the default render |
| Handled Session leaves after the user leaves | output-idle, `done`, and `failed`: visible after a switch to it, absent after a switch away. `needs-input`: visible after both switches | the capture runs after acknowledgment, or `kept` survives a switch |
| Active alone earns nothing | A switch to a quiet Session leaves it hidden | the active Session is always shown |
| Window change survives the visibility clear | With the real install order (manager first, idle handler prepended), an output-idle or `done` Session that becomes current by `set-window-buffer` and `run-window-configuration-change-hook` is a row. The same case without the depth -90 capture shows no row | the capture runs after the idle handler (research R4) |
| Grouped headings follow rows | Every host and project heading is followed by a row of its own before the next heading | headings for hidden groups remain |
| Toggle has no side effects | The toggle changes no Session status, no saved value, and no serialized state keys | the toggle acknowledges a Session or persists the view |

## Cleanup

After the gate passes, remove scratch files. Update README.org (the sidebar key
list and the `?` menu notes), CONTEXT.md (the "Focused view" term), and the
transient menu.
