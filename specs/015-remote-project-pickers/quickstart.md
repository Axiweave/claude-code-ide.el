# Quickstart: Remote Preview for the Project File Pickers

## Targeted Tests

```bash
emacs -batch -L . -l ert -l claude-code-ide-tests.el \
  --eval '(ert-run-tests-batch-and-exit "claude-code-ide-test-send-file\\|claude-code-ide-test-send-project")'
```

Cases that cover this specification:

- `claude-code-ide-test-send-file-from-home-remote-target`
- `claude-code-ide-test-send-file-from-home-remote-rejects-local-file`
- `claude-code-ide-test-send-file-from-home-keeps-absolute-path`
- `claude-code-ide-test-send-file-remote-target`
- `claude-code-ide-test-send-file-remote-rejects-local-pick`
- `claude-code-ide-test-send-file`
- `claude-code-ide-test-send-project`
- `claude-code-ide-test-send-file-uses-configured-picker`

Helper `claude-code-ide-tests--reject-remote-name-dispatch` fails a test that
passes an RPC name to `expand-file-name` or `file-relative-name`.

Superseded case: `claude-code-ide-test-send-file-preserves-remote-target-policy`
(spec 009). It pinned the old picker contract. Its replacement is
`claude-code-ide-test-send-file-remote-target`.

## Full Gate

```bash
./scripts/compile-and-test.sh
```

Expected result: clean byte compilation and zero unexpected ERT results.

## Live Checks

In a running Emacs with a remote Session:

1. `M-x claude-code-ide-send-file-from-home` shows `File: /rpc:HOST:~/`.
2. Pick `/rpc:HOST:~/notes.txt`. The Agent receives `/Users/<you>/notes.txt`.
3. `M-x claude-code-ide-send-file` for the same Session shows
   `File: /rpc:HOST:/<session-directory>/`.
4. Pick a file inside the Session directory. The Agent receives a relative path.
5. Set `claude-code-ide-file-reference-picker-function` to a test function.
   `f` and `h` both call it with the search directory and the Session host.
