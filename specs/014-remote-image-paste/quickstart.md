# Quickstart: Remote Image Paste

Runnable checks for this feature, in the order that finds a fault cheapest. Steps 1
and 2 run without a terminal. Steps 3 to 6 need a live Emacs, Ghostel, and one
approved remote host.

Paths used below:

```text
package repo:  /Users/fuyu0425/.spacemacs.d-30/site-lisp/claude-code-ide.el
Ghostel repo:  /Users/fuyu0425/.spacemacs.d-30/site-lisp/ghostel
```

## Prerequisites

1. Ghostel builds against a ghostty pin at or after ghostty commit
   `e4240606752e5e4eb480b69104d75db0054f71c8`, so the module exports
   `ghostty_terminal_paste` and the terminal clipboard-read option (research R3).
2. An Agent that implements the client side of OSC 5522 is available on the remote
   host. Today that is `omp`.
3. The remote host is already in `claude-code-ide-remote-hosts`, and stock `zmx` is
   installed there. This is the same host used for feature 013.
4. A screenshot or any image is on the clipboard.

## 1. Ghostel protocol checks

```sh
cd /Users/fuyu0425/.spacemacs.d-30/site-lisp/ghostel
make test-zig
make test-native
```

Expected: the Zig tests cover the paste-event packet (MIME list, grant, terminators),
the granted read reply (MIME selection, 4096-byte chunking, ordering), the refusal for
a missing or spent grant, the refusal for an unavailable MIME, and the bracketed-paste
fallback when the mode is off. All pass. The native and Elisp suites pass with the
existing OSC 52 tests unchanged.

## 2. Package batch checks

```sh
cd /Users/fuyu0425/.spacemacs.d-30/site-lisp/claude-code-ide.el
emacs -batch -l ert -l claude-code-ide-tests.el \
  --eval '(ert-run-tests-batch-and-exit "claude-code-ide-test-session-paste")'
./scripts/compile-and-test.sh
```

Expected: the route cases pass (local Session unchanged, remote and capable uses the
terminal paste, each refusal explains and sends nothing), the existing paste tests pass
unchanged, byte-compilation is clean, and the full suite passes.

## 3. Local parity check

In a live Emacs, with Ghostel loaded:

1. Start a local `omp` Session.
2. Copy a screenshot. Press `s-v` in the Session buffer.
3. Confirm the Agent reports an image attachment with the expected dimensions.

Expected: unchanged behavior. The package still sends `C-v` for a local Session, and
the Agent reads the local clipboard itself. Nothing in the terminal path is involved.

Repeat with `claude` and `codex` for one text paste and one image paste each. Expected:
unchanged behavior for both.

## 4. Remote end-to-end check

This is the check the feature exists for.

1. Start an Agent on the remote host: `C-u M-x claude-code-ide-attach`, select the
   approved host, select the `omp` Session, attach it.
2. Wait for the Agent prompt to appear in the Ghostel buffer.
3. Copy a screenshot on the local machine.
4. Press `s-v` in the remote Session buffer.
5. Wait up to 10 seconds.

Expected:

- The Agent reports an image attachment, exactly as a local Agent does.
- The attachment carries the image's true dimensions, which shows the bytes arrived
  unmodified.
- No file appears on the remote host, and the Session's working directory is
  unchanged. Verify with a remote directory listing taken before and after.
- No cleanup step is required.

## 5. Large-image check

1. Copy a screenshot of at least 5 MB, for example a full retina capture.
2. Paste it into the remote Session.

Expected: the attachment arrives within 10 seconds, and the image is usable. The
package applies no cap of its own; if the Agent refuses the size, the Agent's own rule
did it.

## 6. Failure checks

Each produces one visible explanation, sends nothing, and leaves the Session usable.
Verify the Agent receives no attachment in every case.

| Condition | How to create it | Expected |
|---|---|---|
| Terminal lacks native support | Load an older Ghostel build | The Session says the installed build cannot deliver clipboard images, and names the alternative |
| Local client is not the input leader | Attach to the same remote Session from a second terminal, then paste in Emacs | The Session names the leadership condition and the action that restores delivery |
| CLI has no client-side implementation | Attach a `claude` Session on the remote host and paste an image | Behavior is unchanged for that Agent; no new message |
| Clipboard holds text only | Copy text and press the gesture | Normal text paste, exactly as today |
| Clipboard is empty | Clear the clipboard and press the gesture | An explanation, and no attachment |

## Evidence to record

- The Zig and native test command output from step 1.
- The ERT selector output and the full gate result from step 2.
- The local Session transcript from step 3, showing the attachment and its dimensions.
- The remote Session transcript from step 4, showing the attachment, plus the remote
  directory listing before and after.
- The timing observed in step 5.
- The five explanation messages from step 6.
