# Contract: Emacs Session Editor Handler

Elisp surface this package adds. Symbols live in `claude-code-ide-session.el`, except the remote file operation, which lives in `claude-code-ide-remote-project.el`.

## Keys

`C-g` runs `claude-code-ide-session-send-control-g-marked`. `RET` runs `claude-code-ide-session-send-return-marked`. `<return>` reaches `RET` through `function-key-map` because no active map binds `<return>`, so `RET` alone covers both. Both bindings live in `claude-code-ide-session--emulation-mode-map-alist`, which precedes Ghostel's and Evil's alists, and are installed by a top-level `define-key` after the `defvar`. Both commands use one rule:

1. Look up the binding the package map shadows, with `emulation-mode-map-alists` bound to the current list minus `claude-code-ide-session--emulation-mode-map-alist` only. Ghostel's char-mode alist and Evil's alists still take part.
2. When the buffer's CLI type is `omp` and that binding is Ghostel's terminal send (`ghostel-send-C-g` for `C-g`, `ghostel--send-event` for Return): for `C-g`, set `quit-flag` to nil and deactivate the mark as `ghostel-send-C-g` does, then send the `pi:editor-open;<nonce>` marker followed by `\x07` in one `claude-code-ide-session-send-string`. For Return, first call `ghostel--on-user-input` exactly as `ghostel--send-event` does (`ghostel.el:1677`), so `ghostel-scroll-on-input` still anchors a scrolled buffer, then send the `pi:editor-submit;<nonce>` marker followed by `\r` in one string. `C-g` makes no such call, matching `ghostel-send-C-g`. A pre-upgrade Agent consumes the marker and still receives the key. A current Agent arms the nonce for that key, so it travels atomically with the key or with a command such as `/todo edit`.
3. Otherwise `call-interactively` the shadowed binding. Line mode, copy mode, Evil states, and every non-omp buffer keep their own Return and `C-g`. Copy-mode `C-g` leaves copy mode, as before. Line mode sends no marker: its Return writes the line as separate character events before `\r`, and those events would clear the armed nonce.
4. Record activity for idle tracking.

The public command `claude-code-ide-session-send-control-g` sends the marked keystroke in an `omp` Session and the raw keystroke elsewhere. User wrappers that call it (the common custom `C-g` binding) get the marker without changes. `claude-code-ide-session-send-control-g-marked` calls it when the shadowed binding is `ghostel-send-C-g`.

## Nonce

`claude-code-ide-session--editor-nonce` is one value per Emacs process, created on first use from `random` and the PID. It never changes and is never persisted. `claude-code-ide-session--editor-request` holds the one accepted request as `(REQUEST-ID . SESSION-BUFFER)`; the handler rejects a new request while it is set.

## Handler

`(claude-code-ide-session-editor-request REQUEST-ID NONCE PATH)`

Registered once in the global `ghostel-eval-cmds` under `with-eval-after-load 'ghostel`. Ghostel shows a message for an unknown command in any buffer (`ghostel.el:3257-3277`), so a buffer-local registration would leave that message in every non-Session Ghostel buffer. Runs with the Ghostel process buffer current.

| Condition | Result |
| --- | --- |
| `(claude-code-ide--session-for-buffer (current-buffer))` is nil, meaning no live Session owner in the registry | Return nil. Send nothing. Show nothing. |
| `NONCE` is empty or differs from this client's nonce, or a request is already accepted | Return nil. Send nothing. |
| Session host is set and the remote feature does not provide the operation (`(or (fboundp 'claude-code-ide-remote-project-open-file) (and (require 'claude-code-ide-remote-project nil t) (fboundp 'claude-code-ide-remote-project-open-file)))`, the manager's pattern at `claude-code-ide-manager.el:201-203` plus a second `fboundp` because `require` never reloads a provided feature), or `claude-code-ide-remote-hosts` omits the host, or RPC support is unavailable | Signal an actionable `user-error`. Ghostel catches it and shows the message. Send nothing. |
| Otherwise | Send `pi:editor-ack;REQUEST-ID` now. Start the visit. Return non-nil. |

The ack is a claim, not proof of a buffer. The preflight above catches the cheap failures (no client, no admission) before the ack, so the Agent falls back to `$EDITOR`. A failure after the ack (connection error, unreadable file, `find-file-noselect` or display signal) sends `pi:editor-cancel;REQUEST-ID` once, kills any buffer it opened, and shows one `message`. The Agent then keeps its previous text, which is the same outcome as a user cancel. The Agent does not retry with `$EDITOR` after an ack, because it has already handed the file to Emacs.

Visit, local Session: `run-at-time 0`, then `find-file-noselect PATH` and `claude-code-ide-session--editor-visit`. The handler itself runs inside Ghostel's native VT callback, so no file or window work happens there. The timer skips the visit when the accepted request changed meanwhile.

Visit, remote Session: `(claude-code-ide-remote-project-open-file HOST PATH CALLBACK)`. On `:buffer`, `claude-code-ide-session--editor-visit` runs in the callback, unless the accepted request changed meanwhile. On `:error`, send cancel and one `message`. `ponytail:` an Agent interrupt during a slow remote open is not pushed to Emacs. The buffer can still appear after the Agent gave up. Its answers carry a stale id, which the Agent ignores (FR-008), and the buffer closes on finish or cancel. Upgrade path when this bites: an Agent → Emacs `claude-code-ide-session-editor-abort "<id>"` OSC that marks the id invalid so the callback kills the buffer instead of displaying it.

`claude-code-ide-session--editor-visit BUFFER`:

1. Enable `with-editor-mode`.
2. Add buffer-local hooks. `with-editor-post-finish-hook` sends `pi:editor-done;REQUEST-ID` and `with-editor-post-cancel-hook` sends `pi:editor-cancel;REQUEST-ID`. Both run after `with-editor-return` has saved (and, on cancel, deleted) the file (`with-editor.el:334-345,355-364,374-397`), so the Agent never reads stale content and never removes the file while Emacs still saves it. Both run in a temporary buffer after the prompt buffer is killed, so the answer goes to the Session buffer recorded in `claude-code-ide-session--editor-request`.
3. Display with `switch-to-buffer`, as the existing `with-editor-server-window-alist` entries do for prompt patterns. `with-editor-server-window-alist` is not touched.

## Remote file operation

`(claude-code-ide-remote-project-open-file HOST PATH CALLBACK)` in `claude-code-ide-remote-project.el`, beside `claude-code-ide-remote-project-open-target` (`:1459-1504`) and built on the same explicit callback attempt.

- Preflight, synchronous, before any connection: `claude-code-ide-zmx--validate-host` (membership in `claude-code-ide-remote-hosts`, the module's admission policy for explicit callback attempts, `:255-263`), absolute `PATH`, `claude-code-ide-remote-project-target-available-p`. Each failure signals a `user-error` that names the missing approval or the missing client. A file open is not a Project view, so `claude-code-ide-remote-project-view-hosts` does not apply.
- File name: `(concat (claude-code-ide-remote-project-rpc-directory HOST (file-name-directory PATH)) (file-name-nondirectory PATH))`.
- The attempt carries one new field, `file`. The owned worker (`:1296-1345`) gains one branch for it: after the health check, `find-file-noselect` under `inhibit-interaction`, then `run-at-time 0` a new `--finish-file-success` that rechecks `--attempt-current-p` and calls `CALLBACK`. No view registry, no publication. The existing 30-second deadline, `--finish-failure`, and `claude-code-ide-remote-project-cancel-target` apply. No main-thread timer.
- `CALLBACK` runs once on the main thread with `(:status completed :buffer BUFFER)` or `(:status failed :error STRING)`, the same shape `open-target` uses.

A dead originating Session buffer at finish or cancel time sends nothing and only closes the prompt buffer.

Tests cover: nonce mismatch, empty nonce, name-matching buffer without a registry owner (silent nil), host not in `claude-code-ide-remote-hosts` (`user-error`, no ack), remote feature unavailable and feature-provided-but-function-unbound (`user-error`, no ack), RPC unavailable (`user-error`, no ack), a remote open through the real worker dispatch with the composed RPC name, admission lost during the worker (cancel sent), a visit that fails after the ack (cancel sent, no buffer left behind), `C-g` and Return packets in an omp terminal-input buffer, Return in a scrolled buffer with `ghostel-scroll-on-input` anchoring like the shadowed path, and fall-through to the shadowed binding with no marker for a non-omp buffer, a Ghostel copy-mode buffer, a Ghostel line-mode buffer, and an Evil normal-state buffer.

## Routing change

`claude-code-ide--find-prompt-buffer` matches the local name of `buffer-file-name` (`file-remote-p NAME 'localname` when remote), so a remote prompt buffer routes like a local one.

## Errors

- Missing Ghostel or non-Session buffer on the key: existing `claude-code-ide-session--ensure-session-buffer` `user-error`.
- Host not admitted or RPC unavailable: actionable `user-error` from the handler, shown by Ghostel. No ack. The Agent falls back.
- Visit failure after the ack: cancel packet and one `message`.
