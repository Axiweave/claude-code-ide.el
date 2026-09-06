# Contract: Global Manager Views

**Status**: Implemented and verified. See [acceptance results](../quickstart.md#8-implementation-validation-record).
**Specification**: [spec.md](../spec.md)
**State and identity**: [data-model.md](../data-model.md)

## Commands

| Interface | Behavior |
|---|---|
| `claude-code-ide-manager-toggle-grouped-view` | Toggle the existing global scope between flat and grouped view |
| Sidebar `v`, manager menu `v` | Invoke the view toggle and show the current view in the menu description |
| `claude-code-ide-manager-next-project-group` | Select the first Session in the next group |
| `claude-code-ide-manager-previous-project-group` | Select the first Session in the previous group |
| Sidebar and manager menu `C-j` / `C-k` | Invoke next/previous Project group commands |
| `claude-code-ide-manager-refresh-remote-metadata (&optional host)` | Prompt for one configured host interactively, then refresh all its known manager Sessions |
| Manager menu `m` | Invoke remote metadata refresh. Do not replace `G` or any existing binding |
| Existing `E` | Open the order editor using the current view's presentation |

The view toggle always targets the global scope, even when invoked from a repo-local sidebar.
It does not convert a repo-local sidebar or change its scope.
Do not open a hidden sidebar merely to change the global view setting.
Group navigation requires a grouped global sidebar. Otherwise report that grouped global view is required without changing state.

`v` and `m` are new bindings only in the manager interfaces shown above.
Do not replace bindings in the main package transient or user maps without checking that interface separately.

## Display

Local groups appear first, without a local-host heading.
Remote groups appear under `[HOST]` headings, using the exact configured host label.
Within each host, use natural ascending group-name order, with group identity as the tie-breaker.
Use enough parent-path text to distinguish identical project headings within a host.
The full project path appears in heading `help-echo`.

Headings have no Session ID property, numeric slot, Avy target, or Session action.
They are always expanded. Session-level actions on a heading follow existing no-Session-at-point behavior.
Do not start, stop, detach, pin, or rename an entire group.

Each Session appears once. Only Session rows receive existing active and Agent-state indicators.
Show branch names in grouped rows, with Worktree directory fallback for detached HEAD or non-Git Sessions.
Append custom names without hiding the branch. Disambiguate duplicate final labels within a group.
Keep the existing `[disconnected]` indication and hide current Agent-state markers for disconnected Sessions.
Remote grouped rows need not repeat the host prefix because their Host section already identifies the host.
Flat rows retain their current host-qualified labels.

Preserve the existing numeric-slot contract: 1–9 and 0 for slot 10.
Rows after slot 10 remain visible without numeric shortcuts.
Compute slots from the same ordered Session sequence used for display and navigation.

## Toggle and persistence

Capture selected and active Session IDs before changing view.
Save the global view field before refreshing when persistence is enabled.
Restore point by selected Session ID without invoking a Session switch or acknowledging Agent results.
Update visible global sidebars across frames. Leave layouts and repo-local sidebars unchanged.
The first installation and old persisted states default to flat view.

## Group navigation

Resolve the origin from the Session at point, then the scope's selected Session, then the active Session.
When point is on a heading, use the remembered selected Session rather than treating the heading as a Session.
With no valid origin, next selects the first group and previous selects the last group.
With no groups, report that there are no Sessions. With one group, do nothing.

From any Session in a group, next/previous selects the first Session of the adjacent group.
Wrap across the first/last group and across Host sections.
For a connected target, use the existing Session-switch path and retain sidebar focus.
For a disconnected target, persist row selection, retain the displayed terminal, and show explicit reattach guidance.
A subsequent jump starts from that selected group. Never reconnect during navigation.
Ordinary `n`/`p`, numeric shortcuts, and priority navigation use the same displayed Session order while skipping headings.

## Grouped order editor

Fixed host/group headings have read-only text, no Session identity, and no row number.
Session rows retain stable hidden Session IDs and existing number, kill/yank, and rename-validation conventions.
Movement and renumbering operate on Session rows, never raw heading lines.
Allow empty lines as the current editor does.

Capture the editor view and the snapshot defined in the data model.
A sidebar toggle does not change an existing editor's mode or discard edits.
The existing explicit sort action can resync its contents using the captured view.

Apply validates the entire buffer before changing manager items:

1. Validate fixed heading text, order, and identity.
2. Validate complete, unique, known Session row identities and opening labels.
3. Validate each Session remains inside its opening group in the buffer.
4. Validate each snapshot Session still belongs to the same group in current scope items.
5. Compute the complete merged flat-order result.
6. Apply order keys and existing scope-wide pin clearing only after all checks pass.

A remembered disconnected Session is eligible in grouped view.
A vanished Session or changed group causes an actionable error without order or pin changes.
The editor stays open after rejection. Cancel never modifies manager order or pins.
Sessions added after opening retain existing fallback-order behavior.
The flat editor retains its existing validation behavior, including its pre-existing disconnected-row limitation.

## Compatibility and documentation

Use existing manager mode and Evil integration patterns for all bindings.
Do not add backend-specific branches to these commands.
Update `README.org` manager bindings, view behavior, and remote metadata trigger descriptions during implementation.
Document that a separate Git directory supplies the heading name when its canonical common-directory basename is not `.git`.
Link the feature from the matching `TODOs.org` entry and mark it complete only after acceptance validation.
Update feature 003's display and remote-command contracts to describe grouped host headings and optional metadata requests.
