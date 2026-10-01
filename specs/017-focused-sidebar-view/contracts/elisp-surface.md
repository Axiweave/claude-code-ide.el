# Contract: Public Elisp Surface

**Feature**: `017-focused-sidebar-view` | **Date**: 2026-10-01

The package exposes its interface through Elisp: user options, commands, key
bindings, and the `?` menu. This file states what the feature adds and what it
must not change.

## Added: user option

```elisp
(defcustom claude-code-ide-manager-focused-view nil
  "Whether the manager sidebar shows only Sessions that need the user."
  :type 'boolean
  :initialize #'custom-initialize-default
  :set #'claude-code-ide-manager--set-and-refresh
  :group 'claude-code-ide-manager)
```

| Aspect | Contract |
|---|---|
| Default | `nil`. A user who never touches it sees no change (SC-004) |
| `:initialize` | `custom-initialize-default` is required. The default initializer calls `:set` during load, before the redraw path exists |
| On customize | redraws every live manager sidebar with no manual refresh (FR-017) |
| Persistence | customize only. The manager state file keys stay `:version`, `:scopes`, `:layouts` |

## Renamed: setter

`claude-code-ide-manager--set-show-session-titles` becomes
`claude-code-ide-manager--set-and-refresh`. The body stays the same:
`set-default`, then `--refresh-sidebar-state`. Both
`claude-code-ide-manager-show-session-titles` and
`claude-code-ide-manager-focused-view` use it. No alias remains.

## Added: command

```elisp
(defun claude-code-ide-manager-toggle-focused-view ()
  "Toggle the focused view in every manager sidebar."
  (interactive))
```

| Aspect | Contract |
|---|---|
| Effect | flips `claude-code-ide-manager-focused-view` with `setq`, then redraws every manager sidebar |
| Saved value | untouched |
| Manager state | untouched. It does not call `--save-state` |
| Session status | untouched. It never calls `--reset-session-idle-state` (FR-016) |
| Preserves | the active Session, the window layout, and keyboard focus (FR-015) |
| Reports | `Manager focused view: on (N of M Sessions)` or `Manager focused view: off` |

## Added: key binding and menu entry

| Key | Command | Map |
|---|---|---|
| `f` | `claude-code-ide-manager-toggle-focused-view` | `claude-code-ide-manager-mode-map` |

`f` is unbound in the manager map today. The `?` menu gets an entry in the
"Arrange" column, with a dynamic description, next to `v` and `V`:

```elisp
("f" claude-code-ide-manager-toggle-focused-view
 :description (lambda ()
                (format "Focused view (%s)"
                        (if claude-code-ide-manager-focused-view "on" "off"))))
```

## Added: internal helpers

| Symbol | Contract |
|---|---|
| `claude-code-ide-manager--focus-kept-session-key` | variable. The Session that earned its row during its current activation. See [data-model.md](../data-model.md) |
| `claude-code-ide-manager--focus-member-p (key)` | non-nil when the session priority of KEY is < 5, or when KEY equals both the kept Session and `--current-session-key` |
| `claude-code-ide-manager--focus-activation-key` | variable. The Session most recently recorded as becoming current. `--displayed-items` captures current as kept only while this is nil or equals current |
| `claude-code-ide-manager--note-focus-activation (key)` | when KEY differs from `--current-session-key`, sets the activation key to KEY, and the kept Session to KEY if KEY is monitored, else nil. Called after the live-target check and before any acknowledgment |
| `claude-code-ide-manager--displayed-items (scope &optional view)` | sorted items for SCOPE and VIEW. With the focused view on, members only. Also captures a monitored current Session as kept, unless a pending activation names another Session |
| `claude-code-ide-manager--window-change-session-key ()` | the key that `--refresh-on-window-configuration-change` makes current: `--visible-layout-session-key` when a manager window is visible, else nil. That hook and the capture both use it |
| `claude-code-ide-manager--note-focus-on-window-change ()` | calls `--note-focus-activation` with that key, unless `--in-window-config-refresh` is set |

## Added: hook

| Hook | Function | Depth | Contract |
|---|---|---|---|
| `window-configuration-change-hook` | `claude-code-ide-manager--note-focus-on-window-change` | -90 | runs before `claude-code-ide-session-idle--handle-visibility-change` whatever the load order. `--install-window-config-refresh-hook` installs it, and it is not installed twice. `--refresh-on-window-configuration-change` itself never calls `--note-focus-activation` |

## Changed: callers routed through `--displayed-items`

`--render`, `--visible-session-keys`, `--displayed-groups`,
`--neighbor-in-bucket`, `claude-code-ide-manager-switch-by-slot`, and
`claude-code-ide-manager-switch-by-slot-preserve-focus`.

## Changed: render output while the focused view is on

- The first line is a non-selectable line in the `shadow` face:
  `Focused: N of M`, or `Focused: no Session needs attention` when N is 0.
  It carries no `claude-code-ide-manager-session-key`.
- Quick numbers run 1..min(N, 10) over the displayed rows.
- In the grouped arrangement, a host or project heading appears only above a
  displayed row.

## Unchanged

| Surface | Requirement |
|---|---|
| Rendering with the option `nil` | byte-identical to the previous release |
| Every existing key binding | unchanged. The keymap gains one line |
| Pin-order editor and `E` | full Session list (FR-019) |
| `--materialize-order-keys`, `--swap-order`, order storage | full list |
| Switch acknowledgment (ADR 0002) and the idle visibility handler | unchanged. The new code runs before both and only reads status |
| `claude-code-ide-manager-item` and `claude-code-ide-session` structs | no new slot |
| Package dependencies | no new `require` |

## Behavioral invariants

These are the properties the tests prove.

1. **Agreement**: for every arrangement and status mix, the Session keys of
   the rendered rows, in buffer order, equal `--visible-session-keys`, and the
   Nth row shows quick number N for N ≤ 10. Number key N selects that row.
2. **Filter**: with the focused view on, every rendered row is a member, and
   every member appears. With it off, rendering equals the previous release.
3. **Order**: the focused rows are a subsequence of the full-view rows.
4. **Headings**: in the grouped arrangement, each heading line is followed by
   a displayed row of the same host or group before the next heading of the
   same kind.
5. **Lifecycle**: an output-idle, `done`, or `failed` Session stays visible
   after a switch to it, and it leaves after a switch to another Session. A
   `needs-input` Session stays visible after both switches. The same holds
   for an activation by window change, where the idle visibility handler
   acknowledges the Session before the manager refresh hook runs.
6. **No side effects**: the toggle changes no Session status, no saved
   setting, and no state-file content.
