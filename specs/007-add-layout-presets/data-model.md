# Data Model: Predefined Manager Layouts

**Feature**: `007-add-layout-presets` | **Date**: 2026-09-12

This design extends existing manager and remote-project state.
It does not add a database, a persisted shell process, or a user-defined layout format.
See [research.md](research.md) for the source evidence and rejected alternatives.

## 1. Layout preset descriptor

A private constant alist maps the public preference value to a companion kind and companion side.
The manager resolves this descriptor once for each new-layout or explicit-reset action.

| Preference value | Label | Companion kind | Companion side | Agent side |
| --- | --- | --- | --- | --- |
| `magit-left` | Magit left | `git` | `left` | `right` |
| `magit-right` | Magit right | `git` | `right` | `left` |
| `shell-left` | Shell left | `shell` | `left` | `right` |
| `shell-right` | Shell right | `shell` | `right` | `left` |
| `dired-left` | Dired left | `dired` | `left` | `right` |
| `dired-right` | Dired right | `dired` | `right` | `left` |

Validation rules:

- The preference is exactly one of the six symbols.
- The companion side describes the content windows, never the sidebar.
- Only `git` reads the configured custom-content function.
- Only `shell` can create a Ghostel shell.
- `dired` uses `dired-noselect` for the requested Session directory.
- No descriptor contains an Agent CLI or Agent terminal choice.
- The old side setting has no precedence and no compatibility alias.

The descriptor table is fixed for this feature.
It is not a registration protocol for future custom layouts.

## 2. Session identity

Use the existing `claude-code-ide-session-id` as the ownership key for local and remote Sessions.
Resolve a legacy directory argument to an actual Session record before allocating a shell.
Never use that directory argument as a shell ownership key.

| Existing field | Meaning for layouts |
| --- | --- |
| Session ID | Unique owner of a companion shell and saved layout |
| Directory | Bare path on the Session's host |
| Host | Nil for local Sessions, exact configured host for remote Sessions |
| Agent buffer/process | Existing Agent terminal, never replaced by a companion |
| Remembered remote row | Retains the Session identity while its attachment is disconnected |

Two Sessions can have identical host and directory values while retaining different IDs and shell processes.
A released shell cannot become another Session's companion through a directory or buffer-name lookup.

## 3. Runtime companion shell table

Add one manager-owned runtime hash table, `claude-code-ide-manager--companion-shells`.
Its key is the canonical Session ID. Its value is the exact Ghostel buffer object.
The table is not part of `claude-code-ide-manager--persisted-state`.

A dead buffer reference can remain until an explicit reset or Session removal replaces or releases the entry.
This keeps ownership separate from buffer naming without a second liveness registry.
Do not remove a live entry when resetting a layout, hiding a window, or selecting a Git/Dired preset.

Derived states are observations, not additional stored fields:

| State | Evidence | Normal return | Explicit shell-preset reset |
| --- | --- | --- | --- |
| Never created | No table entry and no saved shell metadata | Restore saved non-shell layout, or apply preset for a genuinely new layout | Create a shell |
| Preparing | Current admitted remote attempt owns creation | Keep Agent usable, never start a second request merely to restore | Supersede the request through existing cancellation rules |
| Live | Owned buffer exists and its Ghostel process is live | Restore it only where the saved layout displays it | Reuse it and preserve command, output, and directory |
| Exited | Owned buffer exists but its process is not live | Show retained output when the saved layout includes it, plus reset guidance | Create a new buffer/process, retain old output according to Ghostel behavior |
| Missing | Owned buffer was killed, or saved shell metadata has no runtime owner | Restore remaining layout, show guidance, do not create a shell | Create a shell in the Session directory |
| Disconnected Session | Remembered remote Session ID survives attachment loss | Do not attach the Agent automatically | After explicit Agent reattachment, reuse a live owned shell |
| Released | Session ended or was removed, table entry deleted | No manager ownership remains | A different or new Session creates its own shell |

The Session layer checks the buffer-local `ghostel--process` with `process-live-p`.
It does not infer liveness from a window, buffer name, terminal handle, prompt, or output-idle state.

### Ownership transitions

1. A successful local creation stores the exact buffer under the Session ID.
2. A successful remote completion stores it only while its request still owns that Session and layout action.
3. Mirroring or resetting a live shell changes windows, not shell ownership.
4. Selecting Git or Dired leaves an existing shell available but does not display it in the new preset layout.
5. Temporary remote disconnection retains the association for the remembered Session ID.
6. Confirmed Session end or explicit removal deletes the association without killing the shell.
7. A stale request that already started a shell leaves it as an ordinary terminal, without adopting it into another request.

Shells that become ordinary terminals keep Ghostel's ordinary identity and exit preferences.
Emacs shutdown is not a shell-persistence feature.

## 4. Saved layout record

Extend each plist in `claude-code-ide-manager--layouts`.
Keep the existing window-state format and remote Project-view identity fields.

| Field | Type | Persistence | Meaning |
| --- | --- | --- | --- |
| `:session-key` | Session ID string | Existing behavior | Layout owner |
| `:window-state` | Writable native window state | Existing behavior | Window arrangement and displayed buffer names |
| `:selected-buffer-name` | String or nil | Existing behavior | Last selected buffer |
| `:terminal-buffer-name` | String or nil | Existing behavior | Old remote Agent name for exact attachment substitution |
| `:project-view-buffer` | Buffer or nil | Never | Existing remote Git/Dired view identity |
| `:project-view-name` | String or nil | Never, as today | Existing remote view rename substitution |
| `:preset` | One of six symbols or nil | Yes | Preset last applied to this layout, not the current default |
| `:companion-kind` | `git`, `dired`, `shell`, or nil | Yes | Last applied companion kind |
| `:shell-buffer` | Buffer or nil | Never | Exact companion object captured with the layout |
| `:shell-buffer-name` | String or nil | Yes | Advisory name of the saved shell window, not proof of ownership |

A buffer name may remain in saved window metadata across Emacs restarts.
That does not preserve a process or authorize recreation.
Only the runtime shell table can identify a live companion owner.

### Capture rules

- Record `:preset` and `:companion-kind` when the layout action applies them.
- Copy those recorded values during later layout capture.
- Do not read the current default preference while capturing a previously applied layout.
- Capture shell object/name metadata only from the Session's owned shell or existing saved shell record.
- Keep shell metadata after a killed shell when it is needed to explain a missing saved companion.
- Do not insert a shell window into the saved state merely because a shell table entry exists.

The current builder/reset flow must write the applied descriptor into the layout record before a later switch can capture it.
Remote completion updates the corresponding record only if the request still owns it.

### Restore rules

Use native `window-state-put` and the existing name-substitution pattern.
A renamed owned shell can replace its old recorded name in the saved state.
A missing runtime shell must not resolve to an unrelated buffer that reused the same name.
Remove or substitute that stale shell reference before native restoration, without creating a terminal buffer.

An exited shell buffer is valid output, not a live shell.
A missing or exited shell alone is a recoverable companion condition, not a request to rebuild the default layout.
If recovery cannot restore the old selected window, select the Agent window and show reset guidance.
The public switch path must not fall through to shell creation after this handled recovery.

Existing remote restoration currently prefers the Agent window.
Change that path to preserve the saved selected window when it still exists, as the specification requires.
A delayed companion display must preserve the user's current focus rather than repeat an old focus request.

### Old persisted records

Old records lack the new fields and remain valid native window layouts.
Do not infer a shell from the current default or migrate old side preference values.
Restore the old record normally. The next explicit reset applies the selected preset and records the new metadata.
No persistence version bump or read-time migration is required for additive optional plist fields.

## 5. Captured layout request

Use a small immutable plist to carry one layout action's resolved intent.
Local construction consumes it synchronously. Remote construction stores it on the existing attempt and frame intent.

| Field | Meaning |
| --- | --- |
| `:preset` | Resolved preset symbol |
| `:companion-kind` | `git`, `dired`, or `shell` |
| `:companion-side` | `left` or `right` |
| `:provider` | Captured custom-content function for Git, `dired-noselect` for Dired, nil for shell |
| `:directory` | Exact requested local or RPC-qualified Session directory |
| `:allow-create` | True only for a new default layout or explicit shell reset, never an ordinary saved-shell return |
| `:epoch` | Existing frame layout epoch captured for publication checks |

This plist contains no functions for arbitrary whole-layout customization.
It does not introduce another queue or persistent request store.

The existing attempt retains Session ID, host, admitted host, Agent attachment, frame, reason, worker, and cancellation state.
Add one `layout-request` field to that attempt.
Explicit non-Session attempts capture only Git provider and directory data.
They do not inherit the manager preset, frame epoch, or shell creation permission.
Their public callback contract remains unchanged.

## 6. Shared remote Project-view key

Preserve the existing location identity and add provider identity:

```text
(HOST LOCATION-KIND CANONICAL-LOCATION PROVIDER-DESCRIPTOR)

PROVIDER-DESCRIPTOR = (COMPANION-KIND PROVIDER REQUESTED-RPC-DIRECTORY)
```

`LOCATION-KIND` still means `git` or `directory` as a location classification.
It never means `shell`, and it is not the orientation.
`COMPANION-KIND` is `git` or `dired` for shared views.
A shell never has a shared Project-view key.

The requested RPC directory controls the provider call and Dired's displayed directory.
The canonical location remains available for existing Worktree reconciliation.
Do not replace the requested directory with its Worktree root when invoking a custom provider or opening Dired.

Key constructors and consumers migrate together during implementation.
Update native lookup, writer claims, publication, surviving-view lookup, explicit target requests, cleanup, reconciliation, and their existing tests.
Do not retain a second three-field cache-key format in runtime lookups.
These keys are runtime-only, so no persisted key migration is needed.

A provider descriptor holds its captured function object.
It is never serialized or reconstructed from printed Lisp.
Native buffer reuse must match the requested provider kind.
In particular, Dired lookup cannot select Magit just because the location is a Git Worktree.

### Shared native buffers

Different keys may still resolve to the same native Magit or Dired buffer.
The existing view registry must treat that as shared ownership when deciding whether cleanup can kill the buffer.
Check all registered owners of the exact buffer and retain modified, preexisting, or uncertain custom buffers.
Removing one provider key or Session must not invalidate another owner's saved layout.

## 7. Remote result variants

Extend the existing worker result plist with `:companion-kind`.
Keep the current result fields for Git/Dired view publication.
Use a separate shell branch in completion, before shared-view registration.

| Result | Required values | Publication |
| --- | --- | --- |
| Git/Dired view | Kind, provider-aware key, buffer, existing origin/creator metadata | Existing shared Project-view registry with provider-aware lookup |
| Shell | Kind `shell`, exact buffer, captured layout request | Session shell table only |
| Failure | Existing error data and current attempt ownership | Explanation, usable Agent, no substitute companion |

A stale result cannot select a window, replace a shell association, or publish under a newer preset.
A live shell from a stale result becomes an ordinary terminal rather than an automatically terminated process.
The existing attempt cancellation never closes a shared RPC connection.

## 8. Validation invariants

1. One Session owns at most one current companion shell association.
2. Two Session IDs never share that association, even with identical host and directory values.
3. A live shell survives reset, mirroring, and Session removal without a process restart.
4. An ordinary saved-layout return never grants shell creation permission.
5. A preference change alone performs no remote work and changes no saved layout.
6. Magit/Dired presets do not require Ghostel and never enter shell creation.
7. A Dired request cannot reuse a cached Magit view.
8. A remote result must match its captured admission and layout request before display.
9. Buffer names never establish Session or process ownership.
10. Persisted layout data contains no buffer objects, processes, threads, or provider functions.

The implementation validation scenarios appear in [quickstart.md](quickstart.md).
