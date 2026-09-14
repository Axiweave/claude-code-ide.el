# Research: Attached-Editor Handoff for Oh My Pi

All findings come from the checked-out sources named below. Line numbers are from the inspected revisions.

## R1. Why the editor opens in the wrong Emacs

**Decision**: Move the editor decision from the frozen process environment to a per-request handshake over the attached PTY.

**Evidence**:
- zmx freezes the environment at Session creation (`docs/zmx.org:47-50`). The creating Emacs sets `EDITOR` to its own `emacsclient` through the `with-editor` macro (`claude-code-ide.el:1909-1916`).
- omp resolves `$VISUAL` then `$EDITOR` and spawns it with inherited stdio (`oh-my-pi/packages/coding-agent/src/utils/external-editor.ts:20-25,61-97`). The child runs on the Agent host and talks to the creating Emacs.

**Alternatives considered**:
- Sleeping-editor fallback of `with-editor`: needs the stdout line to reach Emacs. Ghostel native PTY delivers only event forms to Elisp, and omp is in the alternate screen. Rejected.
- Per-Session `EDITOR` shim: still frozen at creation, and a shim has no way to know which client is attached now. Rejected.

## R2. Output channel from omp to the attached Emacs

**Decision**: OSC 52 with the Ghostel-private `e` kind: `ESC ] 52;e;<payload> ESC \`. The payload is a quoted argument list that `ghostel--osc52-eval` parses with `split-string-and-unquote` and dispatches to a function listed in `ghostel-eval-cmds`.

**Evidence**:
- Handler and dispatch: `ghostel/lisp/ghostel.el:3257-3275`, native route `ghostel/src/handler.zig:238-256`.
- Callbacks run with the receiving Ghostel buffer current (`ghostel.el:3836-3841`).
- Live probe in the user's Emacs: a `message` payload sent from a `sh -c` child inside `zmx attach` reached `*Messages*` (`CCI-OSC-PROBE-ZMX 2256`). Direct (no zmx) also passed. An earlier probe without a delay after attach returned `NOT FOUND`, so the request must be emitted after attach settles. omp emits it only on user action, long after attach. The probe buffer and zmx target were removed.
- zmx fans output to every attached client (`zmx ls` showed `clients=2` for a shared target). Every attached Emacs receives the request. This is why R4 exists.

**Constraints**:
- Arguments are shell-quoted strings. The payload carries only short tokens and one absolute path. Content never travels in the OSC, so no size ceiling applies.
- `ghostel-eval-cmds` is a `defcustom`. The package registers one global entry (see "Dispatcher registration" below). The handler returns nil in a buffer with no live Session owner, so a request arriving in a non-Session Ghostel buffer is inert (FR-010).

## R3. Input channel from Emacs to omp

**Decision**: APC `ESC _ pi:<kind>;<value> ESC \`, the packet family omp already consumes.

**Evidence**:
- omp consumes `pi:prompt` and `pi:keyword` through `ui.addInputListener` (`packages/coding-agent/src/modes/composer.ts:288-299`). Listeners run before key parsing (`packages/tui/src/tui.ts:2159-2213`).
- `StdinBuffer` reassembles a split APC across reads and delivers each complete sequence to listeners as one string (`packages/tui/src/stdin-buffer.ts:212-223`).
- The package already sends this family (`claude-code-ide-session-send-omp-packet`, `claude-code-ide-session.el:265-271`).

**Constraint found**: every editor caller calls `ui.stop()` before it awaits the editor. `ProcessTerminal.stop()` removes stdin listeners, destroys the stdin buffer, and pauses stdin (`packages/tui/src/terminal.ts:1726-1880`). There is no lighter pause API. Therefore the handshake and the wait for `done`/`cancel` MUST run while the TUI is still started. `ui.stop()` moves after the handshake declines.

## R4. Choosing exactly one Emacs: the client nonce

**Decision**: The Emacs where the user pressed the editor key sends the marker `pi:editor-open;<nonce>` followed by the raw `\x07` in one write. The Emacs where the user pressed Return sends `pi:editor-submit;<nonce>` followed by `\r` in one write. omp consumes the marker and arms the nonce for exactly the next input event, so the request that key starts carries it. Only the Emacs whose nonce matches opens the file. The nonce is one value per Emacs process: a request arrives only on its own Agent's pty, so two Sessions in one Emacs never see each other's requests, and the nonce only needs to tell two Emacs clients on one shared terminal apart.

**Why marker plus raw key in one write, not a rewrite**: the composer already consumes every unknown `pi:` packet (`composer.ts:288-299`). A rewrite design would make a pre-upgrade Agent swallow Return and `C-g` until restart, which breaks FR-012 and the restart boundary. With the raw key in the same write, `StdinBuffer` still delivers the APC and the key as two events (`stdin-buffer.ts:234-260`; probe: `"\x1b_pi:editor-open;abc\x1b\\\x07"` → `["\x1b_pi:editor-open;abc\x1b\\", "\x07"]`), so the old Agent consumes only the marker event and keeps working. One write from one client is contiguous through the multiplexer, so no other client's byte lands between marker and key. Ghostel line mode writes the edited line as separate character events before `\r`, which would clear the armed nonce, so line mode is excluded.

**How omp uses the marker**: the composer listener arms the nonce in module state of `external-editor.ts`. Raw `\x07` and `\r` parse as `ctrl+g` and `enter` with and without the kitty protocol (probe: `parseKey` under `setKittyProtocolActive(true)`), so the existing key path fires whatever handler owns the action in the focused component. The first synchronous statement of that handler takes the nonce: the four key entries in their key handler, a Return in `onSubmit`, which carries the string through `TuiSlashCommandRuntime.editorOrigin` and `handleTodoCommand(args, origin)` to `/todo edit`. The event after the key clears any leftover, so a plain-terminal keystroke never inherits a nonce. The Emacs Return and `C-g` bindings send the marker only when the shadowed binding is Ghostel's terminal send in an omp buffer, so Ghostel's key encoder, line mode, copy mode, and Evil stay in charge everywhere else.

**Ceiling** (`ponytail:`): the package sends the raw default `\x07` and `\r`. A user who rebinds the external-editor action to another key gets the handoff only on the default key. Upgrade path: send the first configured key of the action instead of the literal byte.

**Emacs key interception**: Ghostel binds `C-g` in `ghostel-mode-map` and `ghostel-char-mode-map`, and char mode pushes its keymap into `emulation-mode-map-alists` (`ghostel.el:1370-1373,1385-1387,1451-1468`). The package already prepends its own emulation alist ahead of Ghostel's in Session buffers (`claude-code-ide-session.el:213-217`), which is how `s-v` wins today. `C-g` and Return bindings in that same map therefore win in every Ghostel input mode and Evil state, which is why each command must look up and run the shadowed binding unless it is Ghostel's terminal send (`ghostel-send-C-g`, `ghostel--send-event`) or line-mode send (`ghostel-line-mode-send-or-open-link`) in an omp buffer. The `C-g` command keeps `ghostel-send-C-g`'s side effects (`quit-flag` nil, `deactivate-mark`, `ghostel.el:1804-1812`).

## R5. Returning the edit: file on the Agent host

**Decision** (Clarification 1): omp keeps its temp file. Emacs visits that file, saves on finish, and sends `done`. omp reads the file. On cancel Emacs sends `cancel` and omp discards.

**Evidence and reuse**:
- omp already writes `os.tmpdir()/omp-editor-<id><ext>` and reads it back after the child exits (`external-editor.ts:66-89`). The handoff reuses that lifecycle. On macOS `os.tmpdir()` is under `/var/folders/.../T/`, on Linux `/tmp`. Both match `claude-code-ide--temporary-prompt-buffer-regexp` (`claude-code-ide.el:296-298`).
- Remote file names use `claude-code-ide-remote-project-rpc-directory` (`claude-code-ide-remote-project.el:815-819`), the public helper the constitution requires instead of a hand-built `/ssh:` or `/rpc:` string. It returns a directory, so the file name is that directory plus `file-name-nondirectory`. Availability check: `claude-code-ide-remote-project-target-available-p` (`:1449-1457`) proves only Emacs compatibility and a loadable client. Admission is a separate policy: the manager requires the host in both `claude-code-ide-remote-hosts` and `claude-code-ide-remote-project-view-hosts` (`claude-code-ide-manager.el:843-852`). A bare `find-file-noselect` on an RPC name bypasses the package-owned guards and can block the main thread on connect (`:592-625`), so the visit must run through the owned worker (`:1296-1345`) behind a new public operation.
- Remote attach binds the Session buffer's `default-directory` to `temporary-file-directory` (`claude-code-ide.el:1828-1831`). The handler MUST take the host from the Session record, not from `default-directory`.
- `with-editor-mode` supplies the finish and cancel keys and buffer-local hooks (`with-editor.el:308-316,329-365`). Order matters: the `pre-*` hooks run before `with-editor-return` saves, the `post-*` hooks run after, in a temporary buffer once the prompt buffer is killed. With no server client and no pid, the return saves and kills on finish, and saves, deletes, and kills on cancel (`with-editor.el:367-397`). Done and cancel therefore both go on the `post-*` hooks with the Session buffer captured in the closure: a cancel sent from `pre-cancel` could let a fast Agent delete the file before the cancel save at `:375`. Emacs deleting the temp file on cancel is harmless: omp removes it with `force: true` anyway.

**Routing**: `claude-code-ide--find-prompt-buffer` matches `buffer-file-name` against local patterns. A remote file name starts with `/rpc:host:`. It must match the local name (`file-remote-p NAME 'localname`) when a remote prefix is present. `with-editor-server-window-alist` is left alone: it only takes `(REGEXP . FUNCTION)` matched against the full name (`with-editor.el:257-266,545-550`), and the handler displays the buffer itself. This is the one remote-only difference under constitution principle VI, and the constraint is the file name prefix.

**Dispatcher registration**: Ghostel looks up the current buffer's `ghostel-eval-cmds` and shows a message on a miss (`ghostel.el:3257-3277`). zmx fans the OSC to every client, so a buffer-local whitelist would leave that message in every non-Session Ghostel buffer. One global entry whose handler returns nil when `claude-code-ide--session-for-buffer` is nil (`claude-code-ide.el:623-643`) keeps other buffers silent and gives the live-registry ownership check FR-010 asks for. The Session name predicate alone (`claude-code-ide-session.el:108-121`) does not prove registry ownership.

**Deferral**: the OSC callback runs inside the native parser call. The handler sends `ack` synchronously after preflight. A local visit is scheduled with `run-at-time 0`. A remote visit runs in the owned worker, never on a main-thread timer, because the connection can block.

## R6. Fallback timing and interruption

**Decision**: omp waits 500 ms for `ack`. No `ack` means "no accepting client": omp removes its listener and continues with the existing `$VISUAL`/`$EDITOR` path, including the existing "No editor configured" warning. The `getEditorCommand()` guard moves after the handoff attempt, otherwise an Emacs-attached Session with no `$EDITOR` never reaches the handoff.

While waiting for `done`/`cancel` there is no deadline. A `ctrl+c` byte (`\x03`) on input resolves the wait as cancel, so the Session stays interruptible (FR-009).

**Evidence for the callers**: `interactive-mode.ts:4302-4360` (plan and annotation), `hook-editor.ts:257-267`, `input-controller.ts:2418-2438`, `todo-command-controller.ts:410-445`. Each stops the TUI before the editor and restarts it after, in its own order, with its own apply step in between. The helper keeps those orders through an awaited `apply` callback.

## R7. Testing

- Package: ERT in `claude-code-ide-tests.el`, gate `./scripts/compile-and-test.sh`. Mock `ghostel--send-string`, `find-file-noselect`, and the RPC availability predicate at their existing interfaces. No display, no Ghostel required.
- omp: `bun test` in `packages/coding-agent` (`*.test.ts`). A fake terminal object with `write` and an input-listener registry covers the handoff helper without a PTY.

## R8. Settings

**Decision**: no new setting. A user without an Emacs client pays 500 ms once per editor request and then gets the old behavior. If a real complaint appears, add `editor.terminalHandoff` (boolean, default true) next to the existing `tui.*` keys in `settings-schema.ts`.
