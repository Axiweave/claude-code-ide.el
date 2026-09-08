# Research: How refs/ projects get a Session description alongside the title

**Feature**: `006-sidebar-detail-view`

**Created**: 2026-09-08

**Question asked**: How does each project in `refs/` obtain a description of a
Session, alongside the title?

**Method**: Read-only survey of the seven `refs/` checkouts, plus this package.
Every claim below carries a file and line reference.

## Short answer

No surveyed project keeps a separate "description" field. Where a project
labels a Session at all, it keeps **one title string**. Only orca puts a second
line under that title in a list, and that line is a transcript preview, not a
description. Two of the seven projects label nothing: ai-code-interface.el and
emacs-term-sessions render one-line metadata rows and send extra detail to
eldoc instead. Among the five that do label a Session, the title comes from
one of four sources:

1. The agent terminal title, reported by the terminal or pushed by the agent.
   Used by herdr, and by this package already.
2. The first user message in the transcript, truncated. Used by cmux, and by
   orca as a fallback.
3. A model-generated summary of the first turn. Used by t3code, and by orca for
   Claude Sessions.
4. A static label assembled from CLI arguments at startup. Used by plannotator,
   which describes a review server rather than an agent Session.

This package already has source 1. That makes the terminal title the cheapest
description available, with no new reader and no new dependency.

## Per-project findings

### cmux — first 80 characters of the first user prompt

- Data model: `ChatSessionDescriptor` with `id`, `agentKind`, `title`,
  `workspaceID`, `terminalID`, `workingDirectory`, `state`, `lastActivityAt`,
  `version` (`refs/cmux/Packages/Shared/CmuxAgentChat/Sources/CmuxAgentChat/Model/ChatSessionDescriptor.swift:8`).
  There is no description field.
- Storage: `AgentChatSessionRecord.title`, documented as "Conversation title
  (first user prompt), filled by the tailer"
  (`refs/cmux/Sources/Mobile/AgentChat/AgentChatSessionRecord.swift:46`).
- Derivation: the transcript tailer scans its message cache for the first user
  message and truncates it
  (`refs/cmux/Sources/Mobile/AgentChat/AgentChatTranscriptTailer.swift:133-137`):

  ```swift
  var title: String? {
      for message in cache {
          if message.role == .user, case .prose(let prose) = message.kind {
              return String(prose.text.prefix(80))
          }
      }
      return nil
  }
  ```

- Refresh: a file watcher on the transcript with a 200 ms throttle
  (`AgentChatTranscriptTailer.swift:59`). Initial backfill reads up to 2000
  lines (`:189`). File rotation is detected by inode comparison (`:102`).
- Dim styling, which the user cited as the reference
  (`refs/cmux/agent-chat/public/app.css:40-41`):

  ```css
  --text-dim: color-mix(in srgb, var(--fg) 60%, var(--bg));
  --text-faint: color-mix(in srgb, var(--fg) 40%, var(--bg));
  ```

  So "dimmer like cmux" is a foreground blended 60% toward the background, not
  a different hue. The Emacs equivalent is a face inheriting from `shadow`.
- Externally readable: `sessionDescriptors(workspaceID:)` returns the Codable
  descriptors (`AgentChatTranscriptService.swift:347`). No public RPC endpoint
  exposes them yet.

### orca — title from the transcript, second line is a message preview

- `AiVaultSession.title` (`refs/orca/src/shared/ai-vault-types.ts:91`) and
  `previewMessages` (`:100`). The second line is the latest conversation turn,
  not a description field.
- Title source depends on the agent: Codex sessions read a `set_title` action
  (`refs/orca/src/main/ai-vault/session-scanner-codex-message-records.ts:43-44`);
  Claude sessions use a generated title, falling back to the first user prompt
  (`refs/orca/src/main/ai-vault/session-scanner-claude-title.test.ts`).
- Preview turns are capped at about five during scan accumulation
  (`refs/orca/src/main/ai-vault/session-scanner-accumulator.ts:177-186`).
- Rendering: title is plain foreground, `font-medium`, clamped to one line;
  the preview below it uses `text-muted-foreground` at 12 px, clamped to two
  lines
  (`refs/orca/src/renderer/src/components/right-sidebar/AiVaultSessionRow.tsx:108-137`).
  This is the closest match to the layout the user drew.
- Refresh: on demand through an IPC call, cancellable, with generation
  tracking so a stale scan cannot overwrite a fresh one
  (`refs/orca/src/renderer/src/components/status-bar/use-resource-session-inventory.ts:59,62,96-97`).
  Cost is a filesystem scan plus a transcript parse per Session.

### herdr — agent pushes its own title through an API

- `PaneInfo` carries `title`, `terminal_title`, `terminal_title_stripped`, and
  `display_agent`, all optional
  (`refs/herdr/src/api/schema/panes.rs:542-548`). No description field.
- The agent sets them by calling `pane.report_metadata`, which also accepts
  `state_labels` and a clear flag (`refs/herdr/src/api/schema/panes.rs:507-525`).
  Metadata may carry a TTL, after which fields clear
  (`refs/herdr/src/api/subscriptions.rs:751-758`), and an optional sequence
  number for causality (`refs/herdr/src/app/api/panes.rs:1667-1672`).
- The sidebar renders `terminal_title_stripped` for plain text
  (`refs/herdr/src/ui/sidebar/tokens.rs:78-83`).
- Refresh is event driven, so polling cost is zero
  (`refs/herdr/src/api/subscriptions.rs:351-389`).
- This is the same shape as this package's Ghostel title observer: the terminal
  or agent pushes a title, and the UI stores and renders it.

### t3code — model-generated title, still only one field

- Stored in `projection_threads` as `title`, plus
  `title_regeneration_request_id` and `title_regeneration_started_at`
  (`refs/t3code/apps/server/src/persistence/Layers/ProjectionThreads.ts:54-86`).
- Auto-generated after the first exchange, but only when the title is still the
  default placeholder, guarded by `canReplaceThreadTitle`
  (`refs/t3code/apps/server/src/orchestration/Layers/ProviderCommandReactor.ts:936-1008`).
  A user rename during a pending regeneration wins, and the generated result is
  discarded (`:966-1008`).
- The user can rename by double-clicking the chat header
  (`refs/t3code/apps/web/src/components/chat/ChatHeader.tsx:180-190`) or
  request regeneration from a context menu
  (`refs/t3code/apps/web/src/hooks/useThreadActionMenu.ts:137-246`).
- Sidebar rendering is a single truncated span with a hover tooltip for the
  full text (`refs/t3code/apps/web/src/Sidebar.tsx:1206-1208`). There is no dim
  second line.
- Not readable without the running server: values come over HTTP or WebSocket,
  with no local cache file.

### plannotator — a static label built from CLI context

- `SessionInfo` holds `pid`, `port`, `url`, `mode`, `project`, `startedAt`, and
  `label` (`refs/plannotator/packages/server/sessions.ts:1-30`), written as
  `~/.plannotator/sessions/{pid}.json` (`:56-59`).
- `label` is assembled at registration from CLI arguments and detected context.
  No model is involved, and the value never changes for the life of the
  Session.
- `listSessions()` removes files whose PID is dead
  (`refs/plannotator/packages/server/sessions.ts:67-109`).
- This is the most readable source for Emacs, because it is plain JSON on disk,
  but it describes a review server, not an agent Session.

### ai-code-interface.el and emacs-term-sessions — no second line today

- Both render Sessions with `tabulated-list-mode` and a vector of column
  strings, so every entry is one line
  (`refs/ai-code-interface.el/ai-code-session.el:226-260`,
  `refs/emacs-term-sessions/term-sessions-list.el:99-148`).
- `emacs-term-sessions` shows extra metadata through eldoc in the minibuffer
  rather than in the list
  (`refs/emacs-term-sessions/term-sessions-list.el:216-253`).
- Available fields: `ai-code-interface` has `task-file` and a metadata plist
  (`ai-code-session.el:1-30`); `emacs-term-sessions` has `name`, `cwd`,
  `command`, `project`, `tags`, `created-at`
  (`refs/emacs-term-sessions/term-sessions-core.el:70-90`).
- Neither offers a dim-second-line pattern to copy, so the styling reference
  stays cmux and orca.

## What this package already has

- The Session struct carries a `title` field
  (`claude-code-ide.el:409-411`).
- It is filled by an `:after` advice on the Ghostel title setter, which reads
  the OSC 2 terminal title (`claude-code-ide.el:911-923`). For a local
  zmx-backed Session the title is mirrored to a zmx label; a remote Session's
  title stays local and contacts no zmx.
- The manager already renders this title in one place: the pin-order editor
  appends it to disambiguate rows with the same base name, gated by
  `claude-code-ide-manager-pin-order-show-titles`
  (`claude-code-ide-manager.el:2194-2207`). It normalizes newlines with
  `(replace-regexp-in-string "[\r\n]+" " " title)`, which the detail line
  should reuse.
- No file in this package reads an agent transcript, and none reads
  `~/.claude`, `~/.codex`, or `~/.omp` for titles.
- The sidebar refreshes on events, not on a timer: the idle and working hooks
  and `window-configuration-change-hook`
  (`claude-code-ide-manager.el:2031-2084`).

## Conclusions that shaped the spec

1. **Use the terminal title. Add no new source.** It is already recorded, it is
   already refreshed, and it needs no transcript reader, no timer, and no
   network call. This matches herdr's model exactly and is what cmux and orca
   approximate at higher cost.
2. **Expect the title to be missing.** Only Ghostel fills it today, so vterm
   and eat Sessions have none. The spec therefore requires a Session with no
   title to keep a single row, rather than showing a blank line or an error.
3. **Copy the orca layout and the cmux dim level.** Title on the row, dim
   secondary line under it, truncated to one line, with the full text in the
   tooltip. The dim level is a blended foreground, so a face inheriting from
   `shadow` is the right Emacs mapping.
4. **One title, not a title plus a description.** No surveyed project keeps
   both. A separate user-editable description would duplicate the existing
   custom Session name, so the spec puts it out of scope.
5. **Reuse the existing newline normalization.** The pin-order editor already
   proves the title can contain newlines and must be flattened before display.

## Phase 0: technical decisions

Added by `/speckit.plan`. The survey above answered where the text comes from.
These decisions answer how to render it. Every line reference was read
directly.

### D1: A real buffer line, inserted after the row closes

**Decision**: Insert the detail line as a normal buffer line at the end of
`claude-code-ide-manager--insert-item`, after the two `add-text-properties`
calls at `claude-code-ide-manager.el:2582-2609`.

**Rationale**: Those calls apply the row status face over `start` through
`(point)`, which includes the row's trailing newline. A detail line inserted
before them would fall inside the range and would be painted as a status row,
which FR-006 forbids. Inserted after, it is a separate range with its own face.
A text property cannot cross into a line that did not exist when the property
was applied.

**Alternatives considered**:

- An overlay with an `after-string`. Rejected. The existing render tests read
  the buffer with `buffer-substring-no-properties`, so an `after-string` would
  be invisible to them. Overlays also need explicit cleanup on every
  `erase-buffer`, which `--render` performs at `claude-code-ide-manager.el:2674`.
- A second display line inside the row string with an embedded newline.
  Rejected. The row's property ranges are computed from `(point)` arithmetic,
  so an embedded newline would shift every range and would put the detail text
  inside the `mouse-face` and status-face spans.

### D2: The detail line does carry the Session key, and navigation needs no change

**Decision**: Apply `claude-code-ide-manager-session-key` to the detail line.
Change no navigation function.

**Rationale**: FR-009 requires a click or command on the detail line to resolve
to the same Session, and `claude-code-ide-manager--item-at-point`
(`claude-code-ide-manager.el:2118-2122`) resolves a Session by reading that
property at point. Without the property, a click on the detail line would be a
no-op.

The apparent risk is `claude-code-ide-manager--move-point-to-session-key`
(`claude-code-ide-manager.el:3235-3242`), which scans with `forward-line` and
stops at the first line whose `session-key` property equals the target:

```elisp
(goto-char (point-min))
(while (and (not (eobp))
            (not (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                        session-key)))
  (forward-line 1))
(beginning-of-line)
```

That scan is safe here. It always starts at `point-min` and moves forward, a
Session appears exactly once in the render loop
(`claude-code-ide-manager.el:2675-2690`), and a Session's detail line is
emitted immediately after its own row. So for any target key the row is the
first line carrying that key, and the scan stops on the row, never on the
detail line. This holds for the flat and the grouped path, because both run
through the same single call site.

A first-pass reading of this function suggested the opposite, that the scan
would halt on a detail line. That reading missed the ordering guarantee. The
ordering is what makes the property safe, so it is recorded here rather than
left implicit.

Two further readers benefit rather than break:

- `claude-code-ide-manager--cycle-session-key`
  (`claude-code-ide-manager.el:3330-3345`) reads the key at point to find its
  index in a list of visible keys. From a detail line it reads the correct key,
  so `n` and `p` continue from the right Session.
- `claude-code-ide-manager--render` recovers the selected key from the window
  point at `claude-code-ide-manager.el:2664-2670`. A point resting on a detail
  line still yields the right key.

**Alternatives considered**:

- Omit the property and add a guard so navigation skips detail lines. Rejected.
  It is a larger diff, it breaks FR-009, and the guard is unnecessary given the
  ordering.
- Add a `claude-code-ide-manager-detail-line` marker property for future logic.
  Rejected as speculative. Nothing needs to distinguish the lines today.

### D3: No name-start property, so Avy gains no candidate

**Decision**: Do not apply `claude-code-ide-manager-session-name-start` to the
detail line.

**Rationale**: `claude-code-ide-manager-avy-switch`
(`claude-code-ide-manager.el:4260-4279`) builds candidates with
`:pred` on exactly that property. Omitting it means the detail line produces no
candidate, which is what FR-008 requires. This is the same discrimination that
already keeps group headings out of navigation: a heading
(`claude-code-ide-manager.el:2611-2621`) carries neither the session key nor
the name-start property.

### D4: Column 7, using the existing align-to idiom

**Decision**: Start the detail text at display column 7 with
`(insert (propertize " " 'display '(space :align-to 7)))`.

**Rationale**: The compact row reaches the label at column 7. The arithmetic,
from `claude-code-ide-manager.el:2560-2570`:

| Part | Line | Columns | Running total |
|---|---|---|---|
| Active marker `▌` or space | 2560-2565 | 1 | 1 |
| Marker gutter, fixed width | 2566 | 2 | 3 |
| `(space :align-to 3)` normalizer | 2567 | 0 | 3 |
| Slot `%2d.` or ` - ` | 2568 | 3 | 6 |
| Separator space | 2569 | 1 | 7 |

The gutter is fixed at 2 columns by
`claude-code-ide-manager--marker-gutter-width`
(`claude-code-ide-manager.el:304`) and padded to that width by
`claude-code-ide-manager--marker-gutter`
(`claude-code-ide-manager.el:1896-1898`). The `(space :align-to 3)` at line
2567 exists to absorb a glyph that measures wider than `string-width` reports,
which the comment at `claude-code-ide-manager.el:281-285` describes for the
bell emoji. Aligning the detail line to an absolute column, rather than padding
with 7 literal spaces, inherits that same protection.

`(space :align-to N)` at line 2567 is the file's only existing use of the
idiom, so reusing it keeps one way of doing this.

### D5: A face inheriting `shadow`, without `:extend`

**Decision**: `claude-code-ide-manager-session-title-face`, inheriting
`shadow`, with no `:extend t`.

**Rationale**: The cmux reference is `color-mix(in srgb, var(--fg) 60%, var(--bg))`,
a foreground blended toward the background. `shadow` is the standard Emacs face
with that meaning, and it follows the user's theme, which a hard-coded hex value
would not. The seven existing manager faces
(`claude-code-ide-manager.el:242-279`) all set `:extend t` except the marker and
host faces, because they paint a full-width row highlight. The detail line must
not read as a row, so it must not extend.

**Alternatives considered**: `font-lock-comment-face`. Rejected, because it
carries the meaning "comment" and is often colored rather than dimmed. A fixed
gray such as `#8a8a8a`. Rejected, because it breaks on light themes.

### D6: A setting with a redraw setter, and a toggle that bypasses it

**Decision**: `defcustom claude-code-ide-manager-show-session-titles`, default
`nil`, with a `:set` function that calls `set-default` and then redraws every
manager sidebar. The `V` command flips the value with plain `setq`.

**Rationale**: Two behaviors that look contradictory are both required. Story 3
scenario 3 says a customize change updates an open sidebar with no manual
refresh, which needs a `:set`. Clarification 1 says the toggle must not write
the saved value, which needs to bypass `:set`. A plain `setq` does exactly that:
it changes the running value, leaves the saved custom value untouched, and does
not invoke `:set`. So the command performs its own redraw.

The two candidate precedents in the file bracket this design.
`claude-code-ide-manager-show-session-order`
(`claude-code-ide-manager.el:194-197`) is a pure display flag with no setter,
read at one point during rendering
(`claude-code-ide-manager.el:2172`). `claude-code-ide-manager-persist-state`
(`claude-code-ide-manager.el:136-147`) shows the `:set` shape. This feature
needs the display-flag role with the persist-state mechanism.

Redraw all sidebars the way `claude-code-ide-manager-refresh-all`
(`claude-code-ide-manager.el:3115`) does: iterate
`claude-code-ide-manager--manager-buffers`
(`claude-code-ide-manager.el:1181-1184`) and call
`claude-code-ide-manager--render` (`claude-code-ide-manager.el:2648`) per
scope. `--render` only redraws. `claude-code-ide-manager-refresh-items`
(`claude-code-ide-manager.el:2086-2105`) rebuilds items from the session
registry and is not needed, because the item list does not change.

### D7: The tooltip gains the title only in the detail view

**Decision**: Append the title to the row `help-echo`
(`claude-code-ide-manager.el:2589-2606`) only when the option is on and a title
exists.

**Rationale**: FR-017 requires a truncated title to remain fully readable
through the row tooltip, and the current tooltip holds the path, branch, zmx
name, and reattach hint, but not the title. Gating on the option keeps the
compact view's text properties unchanged, which FR-002 requires.

### D8: Width is tight at the default, and that is accepted

**Finding**: `claude-code-ide-manager-window-width` defaults to 22
(`claude-code-ide-manager.el:143`). With the label column at 7, about 15
columns remain for the title.

**Decision**: Accept it. No new width logic and no automatic widening.

**Rationale**: The indent decision was made knowingly, and the cost was stated
in the clarification. `truncate-lines` is already `t`
(`claude-code-ide-manager.el:1304`), so truncation needs no code, and the full
title stays reachable through the tooltip per D7. A user who wants more title
raises `claude-code-ide-manager-window-width`, which already exists. Widening
the window as a side effect of a display toggle would be a surprising change to
the user's frame.

### D9: One place normalizes the title

**Decision**: Add `claude-code-ide-manager--item-title`, and change
`claude-code-ide-manager--pin-order-item-names`
(`claude-code-ide-manager.el:2194-2207`) to call it.

**Rationale**: That function already resolves the Session record with
`claude-code-ide-manager--session-record`, reads
`claude-code-ide-session-title`, and flattens newlines with
`(replace-regexp-in-string "[\r\n]+" " " title)`. The detail line needs the
identical three steps. Extracting the helper leaves less total code than
copying the expression, and it keeps one definition of "the Session's
displayable title". The change is behavior-preserving, so the pin-order editor
and its own `pin-order-show-titles` setting stay as they are, per the spec
non-goal.

### D10: Existing tests stay green, and new tests need a different row count

**Finding**: An existing render test counts Session rows by walking lines and
counting those that carry the `session-key` property, asserting 12
(`claude-code-ide-tests.el`, `claude-code-ide-test-manager-grouped-render-toggle-and-slots`).

**Decision**: Leave that test alone. Count rows in new tests by the
`claude-code-ide-manager-session-name-start` property instead.

**Rationale**: The option defaults to `nil`, so no detail line renders unless a
test opts in, and the existing test does not. It stays green untouched. Inside
the detail view, however, "lines carrying a session key" is no longer the row
count, because D2 puts that property on the detail line too. The name-start
property marks exactly one position per row, so it is the correct discriminator
for a detail-view test. This is the same property Avy relies on in D3.

### Sources for Phase 0

Agent reports, retained for audit: `agent://RenderScout`, `agent://NavScout`,
`agent://StateScout`, `agent://TestScout`. Every line reference above was
confirmed by direct read.

## Sources

Agent research reports, retained for audit:
`agent://ScoutCmux`, `agent://ScoutOrcaHerdr`, `agent://ScoutT3Plan`,
`agent://ScoutEmacsRefs`, `agent://ScoutOurManager`.
