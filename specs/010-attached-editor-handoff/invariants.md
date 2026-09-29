# Invariants: Attached-Editor Handoff

**Audited**: 2026-09-29, against the package, Oh My Pi (`~/agents/oh-my-pi`), zmx (`~/agents/zmx`, 0.8.1), Ghostel, with-editor, and the live Emacs.

**Reported symptoms**:

- S1. Sometimes `C-g` does not open the editor.
- S2. Sometimes the handoff gets stuck, and no later request opens an editor.
- S3. Sometimes the edited text does not reach the composer after the editor closes.

Status values: **Holds**, **Fixed** (it failed, and the fix is in this change), **Open** (it can fail, and it has no fix yet).

## Agent (Oh My Pi)

| ID | Invariant | Status | Evidence |
| --- | --- | --- | --- |
| A1 | Every `ESC _ pi:editor-* ESC \` packet reaches `handleEditorInput` and is consumed, in every focus state, while the TUI runs. No editor entry stops the TUI before the handoff. | **Fixed** | `composer.ts:282-285` registers the listener first, and `tui.ts:2342-2347` runs it for every chunk. `tui/src/overlays/hook-editor.ts` called `this.#tui.stop()` before `externalEditor`, which removed stdin (`terminal.ts:2038-2044`). The hook editor and the advisor dialog therefore never received the ack (S1). The call is removed. |
| A2 | The armed nonce lives for exactly the key event it describes. Every editor entry takes it as its first synchronous statement. | **Fixed** | Seven entries hold (`input-controller.ts`, `interactive-mode.ts`, `extension-ui-controller.ts`, `selector-controller.ts`). `annotate/fullscreen.ts` passed `origin: ""` and required `$EDITOR` (S1). It now calls `takeEditorOrigin()`. |
| A3 | `\x07` and `ESC [103;5u` both match `ctrl+g`, and `\r` matches `enter`, with and without the kitty protocol. | Holds | Checked with `matchesKey` under `setKittyProtocolActive(false/true)`. |
| A4 | The pending request clears on every exit path. When a request is open, a new editor entry is visible to the user and names the way out. | **Fixed** (composer) | After an ack, the Agent waits with no deadline (`external-editor.ts`). Only `Ctrl+C` ends the wait. A busy `openInEditor` returned `null`, and callers showed nothing (S1). The composer entry now warns and names `Ctrl+C`. The other entries still return silently. |
| A5 | A request id has at most one outcome. The Agent ignores stale answers. An ack and a done in one read both count. | Holds | `handleEditorInput` compares `pending.id`. `waitForAnswer` queues answers that arrive early. |
| A6 | The ack window covers the real round trip: Agent → zmx → ssh → Ghostel → handler → ack. | **Open** | The handler preflight takes about 0.13 ms. But Ghostel runs the handler on the Emacs main thread. A main thread that is busy for more than 500 ms (for example, a synchronous tramp-rpc call or GC) misses the window. |
| A7 | The Agent does not abandon a file that an Emacs accepted late. | **Open** | After a late ack, the Agent has already opened `$EDITOR` and deletes the file when that editor exits. Emacs still opens its buffer, and its `done` has a stale id (S3). The late ack bytes go to the stdin of the `$EDITOR` child. |
| A8 | The fallback order is stop → spawn → apply → start. With no editor configured, the TUI never stops. | Holds | `external-editor.ts` decline branch. |
| A9 | `Ctrl+C` cancels a pending request and is consumed. With no pending request, it goes on unchanged. | Holds | `handleEditorInput` ctrl+c branch. |
| A10 | The OSC request frame and its quoting match Ghostel's 52;e parser. | Holds (direct), **Open** (tmux) | `quoteOscArg` matches `split-string-and-unquote`. Inside a nested tmux, the Agent wraps the request in `DCS tmux;`. tmux 3.3 and later drop this wrapper unless `allow-passthrough on` is set. |

## Multiplexer (zmx)

| ID | Invariant | Status | Evidence |
| --- | --- | --- | --- |
| Z1 | zmx forwards every Emacs → Agent write, also from a client that is not the input leader. | **Open** | `loop.zig:908-923` forwards the input of a non-leader client only when `util.isUserInput` (`util.zig:688-729`) passes. An APC-only `editor-ack/done/cancel` does not pass. The marker plus key write passes and makes the pressing Emacs the leader. If another client types before the user finishes, zmx drops `done`. The Agent then stays pending (S1, S3). The remote-created Sessions show `clients=2`. |
| Z2 | Agent output (the OSC request) reaches every attached client unchanged. | Holds | `loop.zig:417-431` sends output to all clients with no leader check. |

## Package (Emacs)

| ID | Invariant | Status | Evidence |
| --- | --- | --- | --- |
| E1 | `C-g` in a terminal-input `omp` Session sends the marker and CSI-u ctrl+g. Copy-mode `C-g` leaves copy mode. | Holds (send), **Open** (copy mode, user config) | The package emulation map comes first in every Evil state. In the user config, `claude-code-ide-session-mode-map` binds `C-g` to `leo/claude-code-ide-session-send-ctrl-g`. This binding calls `claude-code-ide-session-send-control-g` in every Ghostel mode, copy mode too. `ghostel-mode` sets `inhibit-quit` buffer-locally. [INFERENCE] A `C-g` inside the short Ghostel write sections, where `inhibit-quit` is nil, becomes a quit and sends nothing. |
| E2 | The handler is registered, runs on the main thread with the Session buffer current, and runs as soon as the output arrives. | Holds | The entry exists in the live `ghostel-eval-cmds`. `ghostel--filter` runs `ghostel--write-vt` inside `with-current-buffer` on the process buffer. |
| E3 | An accepted request always ends in `done` or `cancel`. A request that never answers blocks no other request. | **Fixed** | Seen live: `claude-code-ide-session--editor-request` stayed set to `r-159243beb97cef8d`, and the global guard rejected every later request (S2). The global slot is replaced by `claude-code-ide-session--editor-requests`. Each prompt answers only its own id. The handler ignores only a repeat of an id it already accepted. |
| E4 | The with-editor hooks land on the buffer that visits the prompt file. | **Fixed** | Seen live: `*tramp/rpc v12mac*` had `with-editor-mode`, `with-editor-kill-buffer-noop`, and the package finish and cancel hooks. `find-file-noselect-1` (`files.el`) returns `(current-buffer)` after `find-file-hook`. A hook or RPC wait that leaves another buffer current makes it return the wrong buffer. The remote worker and the local visit now use `find-buffer-visiting` on the file name. |
| E5 | The answer reaches the live Session buffer, also after a reattach. | **Open** | The request keeps the buffer object from the time of the accept. A reattach that replaces the buffer makes `--editor-answer` drop the answer (S3). |
| E6 | `C-c C-c`, `C-c C-k`, `:wq`, and `:q` in the prompt buffer run `with-editor-finish` or `with-editor-cancel`. | **Fixed** (user config) | `init-evil.el` defined `:q` and `:wq` as `kill-buffer`, which `with-editor-kill-buffer-noop` refuses. They now cancel or finish when `with-editor-mode` is on. |
| E7 | The nonce check rejects a foreign or empty nonce. The prompt opens in the window where the key was pressed, or else in the Session window. | Holds | After a reattach (E5), the target window is nil, and the prompt opens in the selected window. |
| E8 | Remote preflight fails before the ack. Every failure after the ack sends `cancel`. | Holds | The 30 s deadline and `--finish-failure` call the callback. [INFERENCE] If `make-thread` returns nil, `--abandon-attempt 'worker-unavailable` never calls the callback. |

## Cross-side

| ID | Invariant | Status | Evidence |
| --- | --- | --- | --- |
| X1 | Each stuck state has a way out that the user can find. | **Fixed** (Emacs), partial (Agent) | Emacs no longer blocks later requests. On the Agent side, `Ctrl+C` ends a pending request, and the composer warning names it. |

## Regression tests

- `claude-code-ide-test-session-editor-request-survives-find-file-hook-buffer-leak` (E4). It fails on the old local visit and shows the live symptom.
- `claude-code-ide-test-session-editor-request-unanswered-prompt-blocks-nothing` (E3).
- `claude-code-ide-test-remote-project-open-file-visits-through-worker` (E4, remote worker).
- `hook-editor.test.ts`: "keeps the TUI running while the external editor runs" (A1). It fails when the old `tui.stop()` is put back.

## Upgrade paths for open items

- Z1: add a key that passes the zmx gate to each answer packet, and make the Agent consume that key. Or let the zmx fork forward `pi:` APC input without a leader change.
- A6/A7: make the ack window longer, together with an explicit decline from Emacs. Or send an Agent → Emacs abort (`claude-code-ide-session-editor-abort`) before the fallback.
- E5: find the current Session buffer by Session id when the answer is sent.
