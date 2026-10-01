# Data Model: Focused Sidebar View

This feature adds no stored data. It adds one setting and one runtime
variable. All other inputs already exist.

## Inputs that already exist

| Name | Source | Use |
|---|---|---|
| Session status rank | `claude-code-ide-manager--session-priority` | rank < 5 means a monitored status (research R2) |
| Current Session | `claude-code-ide-manager--current-session-key` | the active Session for FR-003 |
| Sorted Session items | `claude-code-ide-manager--sorted-items` | order of the current arrangement and sort (FR-007) |

## New state

### Focused view setting

- **Name**: `claude-code-ide-manager-focused-view`
- **Type**: boolean `defcustom`. Default `nil`.
- **Scope**: global, one value for every sidebar (FR-017).
- **Persistence**: customize only. The manager state file never stores it. The
  `f` command changes the live value with `setq` and never saves it.
- **On change through customize**: redraw every live sidebar.

### Kept Session

- **Name**: `claude-code-ide-manager--focus-kept-session-key`
- **Type**: Session key or `nil`. Runtime only. A restart resets it.
- **Meaning**: the Session that earned a row during its current activation.
  It matters only while it equals the current Session.

### Activation key

- **Name**: `claude-code-ide-manager--focus-activation-key`
- **Type**: Session key or `nil`. Runtime only.
- **Meaning**: the Session most recently recorded as becoming current. Between
  the window-change capture and the refresh hook, the idle handler renders
  through the manager status advice. At that moment current is still the old
  Session. The old Session may not take the kept slot while `activation`
  differs from current, or it would overwrite the new capture.

## Derived rule: focused-set membership

```
member(key) = rank(key) < 5
              OR (key = kept AND key = current)
```

`claude-code-ide-manager--displayed-items` returns the sorted items. When the
focused view is on, it keeps only members.

## State transitions of `kept`

| Event | Where | Effect |
|---|---|---|
| Switch to target T, with T ≠ current | `switch-to-session`, `reset-layout`, after the live-target check and before acknowledgment | `activation := T`. `kept := T` if `rank(T) < 5`, else `nil` |
| Switch to T, with T = current | same | unchanged |
| A Session becomes the visible layout without a manager command | `--note-focus-on-window-change`, at depth -90 in `window-configuration-change-hook`, before the idle visibility handler clears output-idle or folds `done`/`failed` | same rule as a switch. The refresh hook sets current to that key later in the same pass |
| Any computation of displayed items while `rank(current) < 5` and `activation` is nil or current | `--displayed-items` | `activation := current`, `kept := current` |
| Current Session changes to another key | any | no write needed: `key = current` fails for the old key |

## Lifecycle walkthroughs (from the spec)

The reference set is `A` (output-idle), `W` (working), and `Q` (quiet). The
user starts on `Q`, and the focused view shows `1. A`, `2. W`.

| Step | current | kept | Visible rows |
|---|---|---|---|
| Start | Q | nil | 1. A, 2. W |
| Press `1`: the note runs (A has rank 3, so kept := A), then the switch acknowledges A (rank 5) | A | A | 1. A (active), 2. W |
| Press `2`: the note runs (W has rank 4, so kept := W) | W | W | 1. W (active) |
| W finishes while visible: `done` changes to `idle` at once, rank 5 | W | W | 1. W (active) |
| Switch to Q from outside the rows: the note runs (Q has rank 5, so kept := nil) | Q | nil | none, so the sidebar shows `Focused: no Session needs attention` |

`needs-input` case (US3 scenario 6): a switch does not acknowledge
`needs-input`, so the rank stays 0. The Session stays visible after the user
leaves.

## Validation rules

- Quick numbers count the displayed items from 1, up to 10 (FR-005).
- Number key N selects the Nth displayed item. If there is no Nth item, the
  key does nothing (FR-006).
- The toggle, the setting, and rendering never call
  `--reset-session-idle-state` (FR-016).
