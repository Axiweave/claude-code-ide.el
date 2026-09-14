# Quickstart: Attached-Editor Handoff for Oh My Pi

Validation guide. Implementation code lives in `tasks.md` and the source files.

## Prerequisites

- This package loaded in a running Emacs with an `emacsclient` server, Ghostel with its native module.
- The Oh My Pi checkout at `~/agents/oh-my-pi` with the Agent change built. The `omp` on `PATH` resolves to that checkout (`readlink -f "$(which omp)"`).
- For the remote scenario: an approved remote host with the RPC client configured, a zmx-backed Oh My Pi Session created by an Emacs on that host, and this local Emacs attached to it.
- Two disposable Sessions only. Do not use a Session that holds real work.

## 1. Batch gates

Package:

```bash
./scripts/compile-and-test.sh
```

Expected: zero unexpected results.

Agent:

```bash
cd ~/agents/oh-my-pi/packages/coding-agent && bun test test/external-editor.test.ts test/modes/composer-editor-handoff.test.ts
```

Expected: all tests pass, including the handoff cases: ack then done returns the file text and awaits `apply` before resolving; no ack within the window returns `undefined` when no editor is configured, else spawns the editor and awaits `apply` before `ui.start()`; cancel returns `null`; stale id ignored; `ctrl+c` before the ack and `ctrl+c` after the ack both return `null`, keep the draft, and do not reach `handleCtrlC`; `ctrl+c` with no pending request passes through; a second entry while one is pending returns `null` without a file or packet; an `editor-open` marker followed by `\x07` in one chunk arms the nonce, is consumed, and the key still reaches the editor action; the same for `editor-submit` and `\r` reaching `onSubmit` with `editorOrigin` set; the nonce is gone at the event after the key; a plain `\x07` without a marker yields an empty nonce; a 64 KB mixed-character file (quotes, backslashes, tabs, non-ASCII, blank lines) round-trips identically on the handoff and the fallback path; a deferred async `apply` sees no `ui.start()` and no render before it settles.

## 2. Reload into the running Emacs

```bash
emacsclient --eval '(load-file "'"$PWD"'/claude-code-ide-remote-project.el")'
emacsclient --eval '(load-file "'"$PWD"'/claude-code-ide-session.el")'
emacsclient --eval '(load-file "'"$PWD"'/claude-code-ide.el")'
```

Load the remote-project file first: `require` never reloads a feature that is already provided, so the manager's later `require` would keep the old definitions.

Expected: each returns `t`. Confirm the bindings landed in the existing emulation map:

```bash
emacsclient --eval '(let ((map (cdar claude-code-ide-session--emulation-mode-map-alist))) (list (lookup-key map (kbd "C-g")) (lookup-key map (kbd "RET")) (assoc "claude-code-ide-session-editor-request" ghostel-eval-cmds)))'
```

Expected: `(claude-code-ide-session-send-control-g-marked claude-code-ide-session-send-return-marked ("claude-code-ide-session-editor-request" claude-code-ide-session-editor-request))`. `<return>` is not bound: it reaches `RET` through `function-key-map`. The nonce is per Emacs process and appears on first use:

```bash
emacsclient --eval '(claude-code-ide-session--editor-nonce)'
```

Expected: a non-empty string.

## 3. Local Session, local Emacs (User Story 2)

1. Start a local Oh My Pi Session from this Emacs (post-upgrade `omp`).
2. Type `hello` in the composer. Press `C-g` in the Session buffer.
3. Expected within one second: a buffer visiting `/var/folders/.../T/omp-editor-*.md` (macOS) or `/tmp/omp-editor-*.md` (Linux) opens in the current window, in `markdown-mode` if installed, with ` WE` in the mode line. The Session stays live and keeps rendering.
4. Add ` world`. Press `C-c C-c`.
5. Expected: the composer shows `hello world`. The prompt buffer is gone.
6. Press `C-g` again, then `C-c C-k`.
7. Expected: the composer still shows `hello world`.

## 4. Remote Session, local Emacs (User Story 1)

1. From the remote Emacs, create the Session. From this Emacs, attach to it through the manager.
2. In the local Session buffer, type `ping`, press `C-g`.
3. Expected within about one second: a buffer visiting `/rpc:<host>:/tmp/omp-editor-*.md` (or the host's temp dir) opens in this Emacs. Nothing opens in the remote Emacs.
4. Edit, `C-c C-c`. Expected: the remote Session composer shows the edit.
5. Switch: from the remote Emacs, press `C-g` in its Session buffer. Expected: the buffer opens there, not here. No restart, no setting changed.

## 5. Plain terminal fallback (User Story 3)

1. Set `VISUAL`/`EDITOR` in Emacs before the Session starts (the Agent inherits the Emacs environment). Start a disposable Session, copy its name with `M-x claude-code-ide-copy-zmx-name`, then `env -u ZMX_SESSION -u ZMX_SESSION_PREFIX zmx attach NAME false` from a plain terminal while the Emacs windows stay open.
2. Press `C-g` in the terminal.
3. Expected: the configured `$EDITOR` opens in the terminal at once. The request carries no nonce, so the Agent skips the offer and the 500 ms window. No Emacs opens a buffer.
4. Detach the terminal.

## 6. Two Emacs instances (edge case)

1. Attach the same Session in two Emacs instances of this package.
2. Press `C-g` in instance A. Expected: exactly one prompt buffer, in A.
3. Press `C-g` in instance B. Expected: exactly one prompt buffer, in B.

## 7. Declined remote access (FR-014)

1. In this Emacs, make the RPC client unavailable for the test only, for example `(cl-letf (((symbol-function 'claude-code-ide-remote-project-target-available-p) #'ignore)) ...)` around a manual request, or use a host that is not approved.
2. Press `C-g` in the remote Session buffer.
3. Expected: one message that names the reason, no prompt buffer here, and after about half a second the remote `$EDITOR` opens in the Session as before the change.

## 8. Other entries (User Story 4)

Repeat step 3 or 4 with `/todo edit`, the plan editor, the plan annotation editor, and the hook instructions editor. Expected: the same buffer behavior and the edited text lands in the right place.

## Cleanup

- Stop the disposable Sessions through the manager. Confirm the zmx targets are gone with `zmx ls`.
- Remove any `omp-editor-*` file left in the temp directory of the Agent host.
- Do not commit. Record results in this file under a Results heading.
