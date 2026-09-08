# Contract: Public Elisp Surface

**Feature**: `006-sidebar-detail-view` | **Date**: 2026-09-08

This package's external interface is its Elisp surface: user options, faces,
interactive commands, and key bindings. This file is the contract for what the
feature adds and what it must not change.

Naming follows the Elisp Standards in the constitution: a public symbol uses
the `claude-code-ide-` prefix, and an internal symbol uses a `--` separator.

## Added: user option

```elisp
(defcustom claude-code-ide-manager-show-session-titles nil
  "Whether the manager sidebar shows a Session title line under each row."
  :type 'boolean
  :initialize #'custom-initialize-default
  :set #'claude-code-ide-manager--set-show-session-titles
  :group 'claude-code-ide-manager)
```

| Aspect | Contract |
|---|---|
| Default | `nil`. A user who never touches it sees no change, per SC-001 |
| Group | `claude-code-ide-manager`, the existing group |
| `:initialize` | `custom-initialize-default` is required, not decoration. The default `custom-initialize-reset` calls the `:set` function while the file loads, before the redraw path is defined, and loading fails |
| On customize | the setter sets the default, then redraws every live manager sidebar with no manual refresh |
| Persistence | the customize interface saves it. Nothing else writes it |
| Read | at render time. Changing it with `setq` takes effect on the next redraw |

## Added: setter

```elisp
(defun claude-code-ide-manager--set-show-session-titles (symbol value)
  "Set SYMBOL to VALUE and redraw every manager sidebar.")
```

Internal. Named in the contract only because `:set` makes it observable
through the customize interface.

## Added: face

```elisp
(defface claude-code-ide-manager-session-title-face
  '((t :inherit shadow))
  "Face for the Session title line under a manager sidebar row."
  :group 'claude-code-ide-manager)
```

| Aspect | Contract |
|---|---|
| Inherits | `shadow`, so it dims with the user's theme |
| `:extend` | absent, and MUST stay absent. The status faces extend to paint a full-width row, and the title line must not read as a row |
| Applied to | the detail line range only. Never to a Session row |

## Added: command

```elisp
(defun claude-code-ide-manager-toggle-session-titles ()
  "Toggle the Session title line in the manager sidebar."
  (interactive))
```

| Aspect | Contract |
|---|---|
| Effect | flips `claude-code-ide-manager-show-session-titles` for the running Emacs, then redraws every manager sidebar |
| Saved value | untouched. A restart returns to the saved value, per clarification 1 |
| Manager state | untouched. It does not call `claude-code-ide-manager--save-state` |
| Preserves | the active Session, the Emacs window layout, the selected row, and keyboard focus, per FR-015 |
| Reports | the resulting view and how many Sessions have a title, for example `Manager session titles: on (3 of 5 Sessions have a title)` |
| Callable | from any buffer. It is not restricted to the sidebar |

The message format is part of the contract because it is the mitigation for
constitution principle IV. Turning the view on where no Session has a title
must say so, rather than appear to do nothing.

## Added: key binding

| Key | Command | Map |
|---|---|---|
| `V` | `claude-code-ide-manager-toggle-session-titles` | `claude-code-ide-manager-mode-map` |

`V` is unbound in every `.el` file in the repository. Lowercase `v` keeps
`claude-code-ide-manager-toggle-grouped-view`.

## Added: dispatch entry

One entry in the "Arrange" group of `claude-code-ide-manager-dispatch`
(`claude-code-ide-transient.el:697-741`), using the dynamic-description form
that the `v` entry already uses, so `?` shows the current state:

```elisp
("V" claude-code-ide-manager-toggle-session-titles
 :description (lambda ()
                (format "Session titles (%s)"
                        (if claude-code-ide-manager-show-session-titles "on" "off"))))
```

## Added: internal helper

```elisp
(defun claude-code-ide-manager--item-title (item)
  "Return ITEM's Session title as one line, or nil when it has none.")
```

| Aspect | Contract |
|---|---|
| Returns | a non-empty single-line string, or `nil` |
| `nil` for | no Session record, `nil` title, empty title, whitespace-only title, glyph-only title. Whitespace includes the non-ASCII spaces `string-trim` ignores, such as U+00A0 and U+3000, per `claude-code-ide-manager--title-space-regexp` |
| Flattens | every whitespace run to one space, so no `\r` or `\n` reaches a row |
| Strips | leading status glyphs from a known set only: `>`, `*`, `π`, `✳`, `✻`, and the braille block, per `claude-code-ide-manager--title-prefix-regexp`. Any other first character is text, so `日 work` and `• Fix parser` keep their first word |
| Callers | the row renderer, the toggle's count, and `claude-code-ide-manager--pin-order-item-names` |

## Unchanged: contract this feature must not break

A reviewer can check the diff against this list.

| Surface | Requirement |
|---|---|
| Compact view rendering | byte-identical with the option off, per FR-002. Same marker, gutter, slot, label column, faces, and text properties |
| Every existing key binding | unchanged. The keymap block gains one line and edits none |
| `claude-code-ide-manager-pin-order-show-titles` | kept, with one stated deviation. The editor keeps one line per Session, one setting, and one title control. Its title text now drops the same status glyphs the sidebar drops, because both call `claude-code-ide-manager--item-title`. A second normalization path would duplicate the rule FR-003 defines |
| `claude-code-ide-manager--serialize-state` keys | still `:version`, `:scopes`, `:layouts` |
| Navigation commands | unchanged. `n`, `p`, `j`, `k`, `C-j`, `C-k`, `g`, `RET`, `SPC` keep their behavior and their code |
| `claude-code-ide-manager--move-point-to-session-key` | unchanged. See D2 in [research.md](../research.md#d2-the-detail-line-does-carry-the-session-key-and-navigation-needs-no-change) |
| `claude-code-ide-session` struct | unchanged. No new slot |
| `claude-code-ide-manager-item` struct | unchanged. No new slot |
| Package dependencies | unchanged. No new `require` and no new `Package-Requires` entry |

## Behavioral invariants

Testable statements a consumer can rely on.

1. With the option `nil`, the sidebar buffer text and text properties are
   exactly what the previous release produced.
2. The number of Session rows equals the number of visible Sessions in both
   views. A detail line is never a row.
3. Every buffer line carrying `claude-code-ide-manager-session-key` resolves to
   a Session. Detail lines included, which is why a click on one works.
4. Exactly one position per Session carries
   `claude-code-ide-manager-session-name-start`, in both views.
5. A detail line never contains `\r` or `\n` inside its text.
6. A Session with no title produces exactly one line in both views.
7. No row status face is ever applied to a detail line range.
8. Switching the view performs no process start and no network request.
