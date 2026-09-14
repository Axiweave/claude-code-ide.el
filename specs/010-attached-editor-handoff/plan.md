# Implementation Plan: Attached-Editor Handoff for Oh My Pi

**Branch**: `main` | **Date**: 2026-09-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/010-attached-editor-handoff/spec.md`

The setup script reported `010-attached-editor-handoff` as its feature identifier. The Git branch is `main` and stays unchanged.

## Summary

When the user presses the editor key or Return in an Oh My Pi Session, the Emacs that received the key sends one write: an origin marker (`editor-open` or `editor-submit`) carrying its own nonce, followed by the raw key byte. A pre-upgrade Agent consumes the marker and still gets the key. A current Agent arms the nonce for that key, so the editor request the key starts (directly, or through a submitted command such as `/todo edit`) carries the nonce. The Agent writes its temp file and emits an OSC request that names the request id, the nonce, and the file path. Only the Emacs whose nonce matches acknowledges, visits the file (locally, or through the approved RPC file name for a remote host), and answers `done` or `cancel` through `with-editor-mode`. No acknowledgment within 500 ms means the Agent uses `$VISUAL`/`$EDITOR` as today.

Two repositories change. The Agent change lands first so the package change can be verified against it. This phase delivers design only.

## Technical Context

**Language/Version**: Emacs Lisp on Emacs 28.1 or later for the package. TypeScript under Bun for the Agent (`~/agents/oh-my-pi/packages/coding-agent` and `packages/tui`).

**Primary Dependencies**: Package: existing `with-editor` (declared), optional Ghostel with native module, optional RPC client through `claude-code-ide-remote-project`. Agent: existing TUI input-listener API, `StdinBuffer`, `Snowflake`. No new dependency on either side.

**Storage**: One temp file per request on the Agent host, owned and removed by the Agent as today. No persistence.

**Testing**: Package: ERT in `claude-code-ide-tests.el`, gate `./scripts/compile-and-test.sh`. Agent: `bun test` in `packages/coding-agent`. Live verification per [quickstart.md](quickstart.md).

**Target Platform**: Supported Emacs desktop hosts with Ghostel. Agent on macOS or Linux hosts, local or reached through zmx over SSH.

**Project Type**: Emacs package plus a change in a separate CLI project.

**Performance Goals**: Handoff decision within 500 ms. Zero added cost when no editor request happens. One OSC frame and at most three APC packets per request.

**Constraints**: Answer packets must arrive while the TUI still owns stdin, so the TUI stays started until the handoff declines. Requests must be inert outside Session buffers. Remote file names go through the public RPC helper. The OSC callback must not block on a remote connection.

**Scale/Scope**: Two key commands (`C-g`, Return), one nonce, one OSC handler, two hook bodies, one routing tweak, and one remote open-file operation in the package. One helper, five listener packet cases (two markers, three answers), one slash-command runtime field, and five caller migrations in the Agent.

## Constitution Check

Both reviews use constitution version 2.0.0.

| Gate | Before research | After design | Evidence and planned compliance |
| --- | --- | --- | --- |
| I. Shared Session core | Pass | Pass | The key command and handler live in `claude-code-ide-session.el` and dispatch on CLI type. The omp-only packet sender already exists there. No Agent-specific fork of terminal or window logic. |
| II. Batch-verifiable quality | Pending tests | Pending tests | ERT and `bun test` cover single-flight, live-owner rejection, admission rejection, post-ack visit failure, nonce match, submit origin, packet emission, hooks, key dispatch, and key fall-through. The gate passes when the tests in Verification Design exist and the full suite runs. |
| III. Optional dependencies | Pass | Pass | One global dispatcher is registered under `with-eval-after-load 'ghostel`. It returns nil silently in any buffer without a live Session owner. Unavailable RPC support signals an actionable `user-error`, which Ghostel's handler catches and shows (`ghostel.el:3265-3275`). No ack is sent, so the Agent falls back. |
| IV. Ghostel-only terminals | Pass | Pass | The channel is Ghostel's own OSC 52;e. No alternate terminal path. |
| V. Simplicity and compatibility | Pending async-apply test | Pending async-apply test | Reuses `with-editor-mode`, the existing packet sender, the existing emulation keymap, the existing RPC helper, and the existing explicit-target attempt. No new dependency, no new setting. Every caller keeps its own apply-before-restart order through an awaited callback. |
| VI. Local/remote parity | Pending file branch | Pending file branch | Same key, same buffer, same finish and cancel keys. Remote file access goes through a new public operation beside `open-target` that reuses the owned worker, its admission checkpoints, health check, and deadline, with one new file branch. The one remote difference is the RPC file-name prefix. Missing approval or support is reported, never silently replaced. |
| Repository workflow | Pass | Pass | Stay on `main`, no commit, design artifacts only. |

No violation needs a Complexity Tracking entry. No clarification remains open.

## Project Structure

### Documentation (this feature)

```text
specs/010-attached-editor-handoff/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── terminal-editor-protocol.md
│   └── emacs-session-editor.md
└── checklists/
    └── requirements.md
```

`tasks.md` belongs to `/speckit.tasks`.

### Source Code

Package (this repository):

```text
claude-code-ide-session.el          # C-g command, nonce, OSC handler, finish/cancel hooks
claude-code-ide-remote-project.el   # public open-file operation: file attempt branch in the owned worker
claude-code-ide.el                  # remote-aware prompt-buffer matching (find-prompt-buffer)
claude-code-ide-tests.el            # ERT coverage
README.org                          # short note under the with-editor paragraph
```

Agent (`~/agents/oh-my-pi`):

```text
packages/coding-agent/src/utils/external-editor.ts                 # handoff helper + single entry for all callers
packages/coding-agent/src/modes/composer.ts                        # editor-open / ack / done / cancel listener cases
packages/coding-agent/src/modes/interactive-mode.ts                # plan + annotation callers migrate
packages/coding-agent/src/modes/components/hook-editor.ts          # caller migrates
packages/coding-agent/src/modes/controllers/input-controller.ts    # caller migrates
packages/coding-agent/src/modes/controllers/todo-command-controller.ts  # caller migrates
packages/coding-agent/src/slash-commands/types.ts                  # editorOrigin on TuiSlashCommandRuntime
packages/coding-agent/src/slash-commands/builtin-session.ts        # forwards editorOrigin to handleTodoCommand
packages/coding-agent/src/modes/types.ts                           # handleTodoCommand(args, origin)
packages/coding-agent/test/external-editor.test.ts                 # handoff tests (existing file)
packages/coding-agent/test/modes/composer-editor-handoff.test.ts   # marker and answer listener tests
```

**Structure Decision**: No new file on either side. One helper in `external-editor.ts` owns the whole editor flow so the five callers shrink to one call each plus their own apply callback.

## Phase 0: Research Results

See [research.md](research.md). Resolved:

- OSC 52;e reaches a Session buffer through zmx (live probe) and runs with the buffer current.
- APC `pi:` packets are already consumed before key parsing, one complete sequence per listener call.
- The TUI must stay started during the handshake: `stop()` drops stdin.
- The origin marker and the raw key travel in one write. `StdinBuffer` delivers them as two events, so a legacy Agent consumes only the marker. One write is contiguous through the multiplexer, which removes the cross-client race a separate nonce write would have.
- The package's emulation keymap outranks Ghostel's and Evil's maps, so `C-g` and Return bindings there must look up and run the shadowed binding unless it is Ghostel's terminal send in an omp buffer.
- Remote file names use `claude-code-ide-remote-project-rpc-directory`. Host comes from the Session record, not `default-directory`.
- `with-editor-mode` gives finish and cancel keys and post-finish/post-cancel hooks that run after the save, with no server or pid.

## Phase 1: Design

### Agent

`openInEditor` becomes the single entry. All handoff state is module-level in `external-editor.ts`. `packages/tui` is untouched.

```ts
openInEditor(ui: TUI, content: string, options: OpenInEditorOptions & {
  origin: string;                        // nonce captured by the entry before its first await, "" when none
  apply?: (text: string) => void | Promise<void>;  // the ONLY place edited text is applied; awaited before the TUI restarts on the fallback path and before the helper resolves
}): Promise<string | null | undefined>   // return value is a status for tests and logging only: text = applied, null = canceled or busy, undefined = no editor
armEditorOrigin(nonce: string): void     // composer listener, on editor-open and editor-submit markers
takeEditorOrigin(): string | undefined   // entries, first synchronous statement; any non-marker input event that is not the expected raw key clears the slot synchronously in the listener, so marker + ordinary character + key yields ""
resolveEditorAnswer(kind: "ack" | "done" | "cancel", id: string): void
```

Flow inside the helper:

1. Reserve the single-flight slot synchronously at entry. If a request is already pending, return `null` at once. No file write, no packet. A double-press test pins this (finding: `custom-editor.ts:1087-1091`, `input-controller.ts:2418-2438`, and `hook-editor.ts:248-264` have no busy guard).
2. `nonce = options.origin`. Every caller passes a string. A plain-terminal keystroke or command carries the empty string. There is no fallback register.
3. Write the temp file as today.
4. `ui.terminal.write` the OSC request per [contracts/terminal-editor-protocol.md](contracts/terminal-editor-protocol.md).
5. Await the pending request with a 500 ms ack timer. Answers arrive only through the composer listener, so listener order cannot swallow them.
6. Ack: keep the TUI running, await done or cancel. Done → read file, apply the existing trailing-newline option, `await apply(text)`, return text. Cancel, or `\x03` in either the offered or the accepted state → `null`, draft preserved.
7. No ack: clear the slot. If `getEditorCommand()` is undefined → return `undefined`. Else `ui.stop()`, spawn as today, on success `await apply(text)`, then `ui.start()` in `finally`, return text or `null`.
8. Remove the file and release the slot in `finally`.

Callers. Each keeps its own lifecycle, which differs per caller (`input-controller.ts:2428-2438` applies before restart; `interactive-mode.ts:4323-4339,4349-4360` commits before restart and forces a render; `hook-editor.ts:257-272` stays silent without an editor and checks `#disposed`; `todo-command-controller.ts:410-445` parses, commits, reports, restarts, renders). Migration per caller:

- Capture `const origin = takeEditorOrigin() ?? ""` as the first synchronous statement of the entry, before any `await`. Key entries: the key handler. The plan caller (`interactive-mode.ts:4302-4324`) awaits a file read before it reaches the helper, so the capture must precede that read. `/todo edit`: the submit pipeline awaits several steps before the command runs (`input-controller.ts:853-959`, `builtin-session.ts:174`), and another client's input in that gap clears the slot. So `onSubmit` captures the origin as its first statement (`input-controller.ts:854`) and passes it as `editorOrigin?: string` on `TuiSlashCommandRuntime` (`slash-commands/types.ts:111-117`, beside `draftDetached`), through `handleTodoCommand(args, origin)` (`types.ts:416`, `interactive-mode.ts:6310`, `builtin-session.ts:174`) to `#editInExternalEditor`. The other `executeBuiltinSlashCommand` caller (`input-controller.ts:1635`) passes nothing, so it gets `""`.
- Pass `origin` and an `apply` callback that does exactly what the caller does today between the editor return and `ui.start()`, including its disposed check, and delete that post-await code from the caller. `apply` is the only application point. A caller that also applied the returned text would commit an edit twice. The plan caller's apply awaits `Bun.write` (`interactive-mode.ts:4328-4332`), so the helper awaits `apply` before any restart or resolution. A test with a deferred async apply observes no `ui.start()` and no render before the callback settles.
- Keep each caller's own warning policy on `undefined` (hook editor stays silent).
- Remove the `getEditorCommand()` guard before the call and the caller's own `ui.stop()`/`tui.stop()` before the call (`input-controller.ts:2428`, `interactive-mode.ts:4323,4349`, `todo-command-controller.ts:421`, `hook-editor.ts:263`). The helper owns stop and restart, and stops only on the fallback path. A stopped TUI removes stdin handling (`tui/src/terminal.ts:1818-1865`), which would break the handshake. Order on fallback: `ui.stop()` → spawn → `apply(text)` → `ui.start()` in `finally`. Order on ack: no stop, `apply(text)` after done, then the caller's existing render request.

`composer.ts` already consumes every `\x1b_pi:` packet, known or not (`composer.ts:288-299`), and it runs before any later-registered listener. It becomes the single owner of the editor kinds. `editor-open;<nonce>` and `editor-submit;<nonce>` → `armEditorOrigin(nonce)`, consumed. No rewrite: the package sends the raw key byte in the same write. `StdinBuffer` splits that write into one event per sequence (`stdin-buffer.ts:234-260`, probe: `"\x1b_pi:editor-open;abc\x1b\\\x07"` → two events, the APC and `"\x07"`), so a pre-upgrade Agent consumes only the marker event and still receives the key, which keeps FR-012 and the restart boundary. Raw `\x07` and `\r` parse as `ctrl+g` and `enter` with and without the kitty protocol (verified with `parseKey` under `setKittyProtocolActive(true)`). The armed nonce is valid for exactly the next input event: the listener keeps it through that event and clears it at the start of the one after. `editor-ack|done|cancel;<id>` → `resolveEditorAnswer(kind, id)`, accepted only for the pending id. A raw `\x03` while a request is pending resolves it as cancel and is consumed: it must not reach `handleCtrlC` (`input-controller.ts:1278-1309`), which would clear the draft on the first press and shut down on the second. With no pending request, `\x03` passes through unchanged.

zmx leader gate (found in the acceptance run): a non-leader client's write is forwarded only when `util.isUserInput` sees a printable, CR/LF/TAB/BS, or a CSI key (zmx 0.7.1 `main.zig:1036-1046`, `util.zig:567-608`, unchanged on `main`). A write of APC plus raw `\x07` is dropped once another client has typed. So the package sends the key as kitty CSI-u ctrl+g (`\x1b[103;5u`) after the `editor-open` marker, and the Agent matches the armed key with `matchesKey(data, "ctrl+g" | "enter")` rather than byte equality. `matchesKey` accepts both encodings with and without the kitty protocol (verified). `\r` already passes the gate and stays raw.

Content size: content never crosses the terminal. The file path has no limit beyond the file system, so the specification's 64 KB minimum holds with no new check. Trailing-newline handling stays the existing `trimTrailingNewline` option, applied identically on both paths, so FR-012 holds and FR-007 holds up to that documented option.

Scope constraint (`ponytail:`): the package sends the raw default bytes `\x07` and `\r`. A user who rebinds `app.editor.external` gets the handoff only on the default key. Upgrade path: send the action's first configured key. One test pins this. Input-mode scope is a user decision recorded in the spec Clarifications (2026-09-13): terminal-input modes only. Line mode's Return sends the edited line as separate character events before `\r`, which would clear the armed nonce, so a `/todo edit` from line mode falls back to `$EDITOR`. Later upgrade: a line-mode wrapper that writes the line text, the marker, and `\r` in one write.

### Package

Per [contracts/emacs-session-editor.md](contracts/emacs-session-editor.md):

- `claude-code-ide-session--editor-nonce`: one value per Emacs process, created on first use. The spec's "client" is one Emacs process, so a per-buffer value adds nothing.
- Global registration once, under `with-eval-after-load 'ghostel`: `(add-to-list 'ghostel-eval-cmds '("claude-code-ide-session-editor-request" claude-code-ide-session-editor-request))`. Buffer-local registration would leave Ghostel's unknown-command message in every other Ghostel buffer (`ghostel.el:3257-3277`). The dispatcher itself returns nil silently when `claude-code-ide--session-for-buffer` is nil, which is the live-registry check the name predicate alone does not give (`claude-code-ide-session.el:108-121`, `claude-code-ide.el:623-643`).
- `claude-code-ide-session-send-control-g-marked`, bound to `C-g` in `claude-code-ide-session--emulation-mode-map-alist`'s map. When the shadowed binding is `ghostel-send-C-g` in an `omp` buffer it calls the public `claude-code-ide-session-send-control-g`, which itself sends the marked keystroke for `omp` and the raw one elsewhere, so user wrappers around that command get the marker too.
- `claude-code-ide-session-send-return-marked`, bound to `RET` in the same map. `<return>` is not bound: Ghostel binds only `RET`, and a `<return>` binding in the package map would stop `function-key-map` from translating it, so the shadow lookup would find nothing. Both bindings are installed with top-level `define-key` on the existing map at load time, outside the `defvar` initializer (`claude-code-ide-session.el:98-105`), because `defvar` never re-evaluates an already bound variable and a `load-file` into a running Emacs would otherwise leave both keys absent. The manager uses that pattern (`claude-code-ide-manager.el:1368-1387`). Both commands share one helper that looks up the shadowed binding with `emulation-mode-map-alists` bound to the current list minus the package alist.
- `claude-code-ide-session-editor-request`: live-owner check, nonce check, remote preflight (`(or (fboundp 'claude-code-ide-remote-project-open-file) (and (require 'claude-code-ide-remote-project nil t) (fboundp 'claude-code-ide-remote-project-open-file)))`, the manager's optional-require pattern at `claude-code-ide-manager.el:201-203` plus a second `fboundp` because `require` never reloads an already provided feature; host in `claude-code-ide-remote-hosts`; RPC availability; each failure a `user-error`), then ack at once. The ack must precede the visit because the Agent's ack timer is 500 ms and the remote worker may take up to 30 s. Local: deferred `find-file-noselect`. Remote: the open-file operation below. Either visit failure after the ack sends cancel and one message.
- New public `claude-code-ide-remote-project-open-file (host path callback)` in `claude-code-ide-remote-project.el`, beside `claude-code-ide-remote-project-open-target` (`:1459-1504`) and with its guards: `claude-code-ide-zmx--validate-host` (membership in `claude-code-ide-remote-hosts`, the module's policy for explicit callback attempts, `:255-263`), `claude-code-ide-remote-project-target-available-p`, absolute `path`. A file open is not a Project view, so the two-list view policy of the manager does not apply. The attempt gets one new field `file`. The worker (`:1296-1345`) gains one branch: when `file` is set, after the health check it calls `find-file-noselect` on `(concat (claude-code-ide-remote-project-rpc-directory host (file-name-directory path)) (file-name-nondirectory path))` under `inhibit-interaction`, then `run-at-time 0` a new `--finish-file-success` that rechecks `--attempt-current-p` (admission at the checkpoint) and calls `callback` once with `:status completed :buffer` or, via the existing `--finish-failure`, `:status failed :error`. No view registry, no publication, no `--finish-view-success`. The existing 30-second deadline and cancel apply. No main-thread timer.
- `claude-code-ide--find-prompt-buffer`: match on `(or (file-remote-p name 'localname) name)`. The `with-editor-server-window-alist` change is dropped: that API matches regexps against the full name (`with-editor.el:257-266,545-550`), and the handler displays the buffer itself.

The `with-editor` macro around Session start stays. It is the fallback for Claude, Codex, and any omp request that no Emacs accepts.

### Verification Design

Package ERT (mock `ghostel--send-string`, `find-file-noselect`, `claude-code-ide-remote-project-target-available-p`, and the worker spawn):

- Matching nonce, local Session: ack packet sent, file visited with `with-editor-mode`, post-finish hook sends done, post-cancel hook sends cancel, neither pre hook sends anything.
- Mismatched or empty nonce: nothing sent, nothing visited.
- Name-matching Ghostel buffer absent from the Session registry: dispatcher returns nil, nothing sent, no message.
- Remote host admitted with RPC available: ack sent first, the open-file operation runs through the real worker dispatch with the connection and `find-file-noselect` seams mocked, the composed RPC file name reaches the mock, and the buffer callback enables `with-editor-mode` and displays.
- Remote host not in `claude-code-ide-remote-hosts`, or RPC unavailable: `user-error` signaled, no ack.
- Admission removed while the worker runs: callback receives `:failed`, cancel sent.
- Post-ack visit failure: cancel sent, one message, no buffer left.
- Remote feature provided but `claude-code-ide-remote-project-open-file` unbound: `user-error`, no ack.
- Key command: omp buffer in char mode sends marker plus raw byte in one string for `C-g` and Return. Line mode, copy mode, Evil normal state, and a non-omp buffer run the shadowed binding unchanged and send no marker.
- Key command, scrolled omp buffer with `ghostel-scroll-on-input`: Return anchors the buffer to the live terminal before the send, exactly as the shadowed `ghostel--send-event` path does. `C-g` does not.

Agent `bun test` with a fake terminal: outcomes listed in [quickstart.md](quickstart.md) section 1, which is the full Agent contract list.

Live: quickstart sections 3 to 8 after both gates pass, reloaded with `emacsclient`.

## Complexity Tracking

No constitution violation. Two `ponytail:` ceilings are recorded: the raw default `ctrl+g`/Return bytes, and no Agent → Emacs abort for an interrupt during a slow remote open (stale buffer, ignored answers, upgrade path is one abort OSC). The terminal-input-mode scope is a spec clarification, not a ceiling.
