# Research: Focused Sidebar View

All facts below come from `claude-code-ide-manager.el` and
`claude-code-ide-session-idle.el` at the time of planning. Line numbers are
approximate.

## R1. Where does the sidebar get its rows?

**Finding**: Every command that acts on "the rows the user sees" calls
`claude-code-ide-manager--sorted-items` on
`claude-code-ide-manager--scope-items`:

| Caller | Line | Purpose | Focused view must filter? |
|---|---|---|---|
| `--render` | 3107 | rows, headings, quick numbers | yes |
| `--visible-session-keys` | 2541 | `n`/`p`/`j`/`k` cycle, `]`/`[` priority passes (through `--live-visible-session-keys`) | yes |
| `--displayed-groups` | 3501 | `C-j`/`C-k`, `M-P`/`M-N` group moves | yes |
| `switch-by-slot`, `switch-by-slot-preserve-focus` | 5481, 5494 | number keys | yes |
| `--neighbor-in-bucket` | 3481 | `M-p`/`M-n` row moves | yes |
| `--materialize-order-keys`, `--swap-order` | 3528, 3541 | store a full order | no |
| `edit-pin-order`, pin-order editor | 2648, 2691, 2958 | full-list editor | no (FR-019) |

**Decision**: Add one function, `claude-code-ide-manager--displayed-items`,
that returns the sorted items and drops non-members when the focused view is
on. Route the five "yes" callers through it. The "no" callers keep the full
list.

**Rationale**: One choke point. Render, numbers, and navigation then agree by
construction, which is what FR-005, FR-006, and FR-014 require.

**Alternatives considered**:
- Filter only in `--render`. Rejected. Number keys and `n`/`p` would still
  index the full list, so key `3` would not reach row `3` (FR-006).
- Filter `--scope-items`. Rejected. That list feeds order storage, the
  pin-order editor, and persistence, which must see every Session.

`M-p`/`M-n` is not named in the spec. With the full list, a move in the focused
view swaps with a hidden neighbor and shows no change. `--swap-order` already
handles non-adjacent pairs in both arrangements, so routing
`--neighbor-in-bucket` through the new function makes a move swap with the
visible neighbor. This is one changed call, not a new feature.

## R2. Which statuses count as "monitored"?

**Finding**: `claude-code-ide-manager--session-priority` already ranks every
status the sidebar marks: `needs-input` 0, `failed` 1, `done` 2, output-idle 3,
`working` (reported or output-based) 4, and everything else 5. "Everything
else" includes the acknowledged `idle` agent state and Sessions with no live
buffer.

**Decision**: monitored = `(< (claude-code-ide-manager--session-priority key) 5)`.

**Rationale**: It is the exact set in FR-002, and it already exists. The row
glyph and row face use the same conditions, so "shows a status" and "is in the
focused view" cannot drift apart.

**Alternatives considered**: A new predicate that lists the states. Rejected
as a second copy of the same table.

**Consequence**: A disconnected Session has no live buffer, so it has no
status and stays hidden. The spec edge case now says this.

## R3. How does a switch acknowledge a Session, and in what order?

**Finding**: `claude-code-ide-manager-switch-to-session` sets
`claude-code-ide-manager--current-session-key` (through `--restore-layout`,
`--build-default-layout`, or its fallback branch). It then calls
`--reset-session-idle-state`, which calls
`claude-code-ide-session-idle-clear-state` with ACKNOWLEDGED. That clears the
output-idle timer and turns `done`/`failed` into `idle`. It leaves `working`
and `needs-input` alone (ADR 0002). Only after that does
`--refresh-sidebar-state` render. `claude-code-ide-manager-reset-layout` (`R`)
follows the same order.

**Consequence**: By the time the sidebar renders, an output-idle, `done`, or
`failed` target already has priority 5. A rule that checks status at render
time would hide the Session the user just opened. That breaks US3 scenario 1.

**Decision**: Record whether the target "earned" its row before the switch
acknowledges it. One variable,
`claude-code-ide-manager--focus-kept-session-key`, holds the Session that
earned a row during its current activation. Membership is:

```
monitored(key) OR (key = kept AND key = current-session-key)
```

`claude-code-ide-manager--note-focus-activation` updates it. It runs at the
start of `switch-to-session` and `reset-layout`, before anything changes. When
the target differs from the current Session, it sets `kept` to the target if
the target is monitored, and to nil otherwise. When the target is already
current, it leaves `kept` alone.

`--displayed-items` also sets `kept` to the current Session whenever that
Session is monitored. This covers a Session that starts working while the user
watches it. A status change always triggers a render
(`--refresh-after-session-status-change`), so this capture runs before any
later acknowledgment.

**Rationale**: One variable with no timer and no per-Session table. The
`key = current` guard makes a stale `kept` harmless, so nothing needs to clear
it when the user leaves. The next activation overwrites it.

**Alternatives considered**:
- A per-Session "earned" flag. Rejected. Only one Session can be active, so
  one variable is enough.
- Delay acknowledgment until the user leaves. Rejected. It changes ADR 0002
  behavior and every switch path, which FR-016 and the spec assumptions forbid.
- Capture inside `--reset-session-idle-state`. Rejected. The clear-all command
  (`!`) calls it for every Session, and the capture must apply to the active
  Session only. The render-time capture already covers `!`: the active
  Session was rendered while it was monitored, so `kept` already holds it.

## R4. Activation outside manager commands

**Finding**: `--refresh-on-window-configuration-change` sets
`--current-session-key` when a Session becomes the visible layout without a
manager command, for example after `C-x b` or a window change (around line
2294). Before that hook runs, the idle module has already acknowledged the
Session:

- `claude-code-ide.el` requires the manager (line 69) before
  `claude-code-ide-session-idle` (line 73). The manager installs its hook at
  load (line 2461). The idle module then calls `add-hook` with the default
  depth (session-idle.el:694-697), which prepends its hook.
- The live Emacs shows this order in `window-configuration-change-hook`:
  `claude-code-ide-session-idle--handle-visibility-change`, then
  `claude-code-ide-manager--refresh-on-window-configuration-change`.
- The visibility handler clears output-idle. It also changes `done` and
  `failed` to the acknowledged `idle` (session-idle.el:521-523).

So a call inside the manager hook sees rank 5 for a Session that qualified a
moment earlier. The Session would leave the focused view while active, which
breaks FR-003 and US3. Moving the call earlier inside the same hook does not
help.

The Emacs 31 documentation of `window-state-change-hook` says that it runs
after all other window change functions. In one redisplay, the order is
therefore:

1. `window-configuration-change-hook`, run per frame.
2. `window-state-change-hook`, which runs the idle handler again.

`after-focus-change-function` also runs the idle handler. It never changes
`--current-session-key`, so it starts no activation.

**Decision**: Capture in `window-configuration-change-hook`, ahead of the idle
handler, with a hook depth.

- Factor the existing expression
  `(and manager-visible-p (claude-code-ide-manager--visible-layout-session-key))`
  out of `--refresh-on-window-configuration-change` into
  `claude-code-ide-manager--window-change-session-key`. The refresh hook keeps
  its behavior and uses the helper.
- Add `claude-code-ide-manager--note-focus-on-window-change`. Unless
  `--in-window-config-refresh` is set, it calls `--note-focus-activation` with
  the helper's key.
- Install it in `--install-window-config-refresh-hook` with
  `(add-hook 'window-configuration-change-hook #'... -90)`. Emacs 27 added hook
  depth, and the package needs 28.1. A depth below 0 runs before every
  default-depth function, whatever the load order.
- Do not call `--note-focus-activation` inside
  `--refresh-on-window-configuration-change`. At that point the target already
  has rank 5 and still differs from current, so a second call would reset
  `kept` to nil.

**Why no other state is needed**: The capture and the refresh hook use the
same helper in the same pass, for the same frame. When the capture sees a key
that differs from current, the refresh hook sets that key as current in the
same pass. `kept` therefore never names a Session that the pass does not
activate. In a later pass, the key equals current, so the capture does
nothing.

**Alternatives considered**:
- `:before` advice on `--handle-visibility-change`. Rejected. That function
  also runs on focus changes and on `window-state-change-hook`, where current
  does not change. A capture there could overwrite `kept` for the active
  Session.
- Install the whole refresh hook at a negative depth. Rejected. That hook
  reasserts sidebar windows, and running it before the idle handler changes
  more than this feature needs.
- Record a snapshot of members at each render. Rejected. The visibility
  clear calls `set-agent-state`, and the manager advice on that function
  renders. So the snapshot can already hold the acknowledged status.

**Regression proof**: A batch test reproduces the real install order: it runs
the manager installer, then `add-hook` for the idle handler at the default
depth. Then it activates an output-idle Session by window change and runs
`run-window-configuration-change-hook`. The Session must be current, must have
`idle-p` nil (proof that the clear ran), and must be a visible row. The same
test, with the capture hook removed, must show the row missing. This proves
that the test detects the race.

**Implementation finding**: The idle handler clears the Session through
`claude-code-ide-session-idle-clear-state` or `set-agent-state`. The manager
advises both functions, and the advice renders while current is still the old
Session. When the old Session was still monitored, for example `working`,
`--displayed-items` promoted it to kept and overwrote the new capture. The
regression test failed in this way. The fix adds
`claude-code-ide-manager--focus-activation-key`. The note sets it, and the
promotion in `--displayed-items` runs only while it is nil or equals current.
The switch commands now note after `--ensure-live-target`, so a failed switch
leaves no pending activation.

## R5. Startup setting and toggle

**Finding**: `claude-code-ide-manager-show-session-titles` (spec 006) is the
same pattern: a `defcustom` with `custom-initialize-default` and a `:set`
function that calls `set-default` and `--refresh-sidebar-state`. The `V`
command flips the variable with `setq`, so the customize value is never
written.

**Decision**: Add `claude-code-ide-manager-focused-view` (boolean, default
nil) and `claude-code-ide-manager-toggle-focused-view`, bound to `f`. Rename
`--set-show-session-titles` to `--set-and-refresh` and use it for both
settings. The old function body does nothing specific to titles.

**Alternatives considered**: Store the view in the manager state file.
Rejected by the clarification and by FR-017.

## R6. Focused-view indicator and empty state

**Finding**: The manager mode sets no header line. Group headings are
non-selectable lines that `--insert-group-heading` writes.
`--move-point-to-session-key` and every navigation command skip lines with no
Session key.

**Decision**: While the focused view is on, `--render` writes one dim,
non-selectable first line. It reads `Focused: N of M` when rows exist, and
`Focused: no Session needs attention` when none exist. The line covers FR-012
and FR-013. It carries no Session key, so navigation skips it, as it skips
headings.

**Alternatives considered**: `header-line-format`. Rejected. It changes the
window height that the sidebar already sizes, and batch tests cannot see it in
the buffer text.

## R7. Remote host and project context

**Finding**: In the grouped arrangement, `--render` writes a `[host]` heading
whenever the host changes, and a project heading whenever the group key
changes, between consecutive items. The flat labels come from
`--item-visible-name`, which does not depend on the list.

**Decision**: No new code. A filtered list gives headings only for groups
that have a visible item (FR-008). Flat labels stay the same (FR-009).

## R8. Discoverability surfaces

**Finding**: The `?` manager menu (`claude-code-ide-transient.el`, "Arrange"
column) lists `v` and `V` with their state. README.org lists the sidebar keys
(around line 707). CONTEXT.md defines Compact view and Detail view.

**Decision**: Add `f` with its state to the menu, add `f` to the README key
list, and add a "Focused view" glossary term. AGENTS.md needs no change.
