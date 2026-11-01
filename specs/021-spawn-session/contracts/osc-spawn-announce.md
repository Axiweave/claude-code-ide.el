# Contract: Spawn Announcement (omp → Emacs)

## Wire format

```text
ESC ] 52 ; e ; "claude-code-ide-session-spawn-announce" SP "<B zmx name>" ESC \
```

- omp quotes each argument with `quoteOscArg`: wrap the value in `"`, and escape `\` and `"` with `\`.
- omp writes the bytes with `writeTerminalSequence`. Inside tmux it first wraps them with `wrapTmuxPassthroughIfNeeded`.
- omp writes exactly one announcement after a successful `zmx attach`. It writes none after a refusal, a declined confirmation, or a failed creation (FR-009, FR-020, FR-022).

## Emacs handler

`(claude-code-ide-session-spawn-announce NAME)` is registered once in `ghostel-eval-cmds`, the same way as `claude-code-ide-session-editor-request`.

Inside the VT parser, the handler MUST:

1. Return nil unless `claude-code-ide--session-for-buffer` gives a live session whose CLI type is `omp`.
2. Return nil unless `claude-code-ide-zmx--package-name-p` accepts NAME.
3. Schedule `run-at-time 0` with A's host and NAME, then return. It MUST NOT call zmx or attach inline.

The timer MUST:

1. List zmx on A's host. A local Session uses `claude-code-ide--zmx-adoptable-sessions`. A remote Session uses `claude-code-ide-zmx-discover-remote` with `claude-code-ide--remote-discovery-callback`.
2. Keep only the entry whose `:name` is NAME. When none is left, log the reason and stop. This covers a session that is gone and a session that is already attached.
3. Call `claude-code-ide--attach-zmx-entries` with that one entry. It rejects an unknown `:cmd` or a bad `:start_dir`.
4. When `claude-code-ide-switch-on-spawn` is non-nil and `claude-code-ide--live-session-for-target` finds B, call `claude-code-ide-manager-switch-to-session`.

## Errors

- A failed check, list, or attach writes one log line and raises no error in the terminal.
- For a host that is not in `claude-code-ide-remote-hosts`, Emacs sends no remote request. It shows one message that names the host and B (US4 scenario 2).
