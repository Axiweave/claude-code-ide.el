# Contract: Stock Zmx Attach Guard

**Status**: Implemented and verified against stock zmx 0.7.1 (local) and 0.8.0 (`ramhorn`). No zmx change is required or permitted.
**Decision**: The user rejected a patched zmx on 2026-09-05. The feature must work with the zmx already installed on each host.
**Research**: [R1](../research.md#r1-attach-to-existing-sessions-with-stock-zmx)

## Attach Command

```text
env -u ZMX_SESSION -u ZMX_SESSION_PREFIX zmx attach NAME false
```

Stock `zmx attach NAME [COMMAND...]` ignores COMMAND when NAME exists and only uses it when creating a session. The guard command `false` exits at once. If NAME vanished between discovery and attach, zmx creates a session that runs `false`, the session ends immediately, and the client exits nonzero. No shell, Agent, or persistent replacement session remains.

The Emacs constant `claude-code-ide-zmx--attach-guard` holds the guard word. `claude-code-ide-zmx--attach-args` builds the argument list for both the local wrapper and the remote SSH command.

## Required Behavior

1. Validate the session name before dispatch. Reject empty names, option-like names, path separators, control characters, and `*`.
2. Unset `ZMX_SESSION` and `ZMX_SESSION_PREFIX` so the attach does not switch the calling client or prefix the name.
3. Preserve ordinary local creation when a creation command is present: `zmx attach NAME CMD...` stays unchanged.
4. Never append an Agent command, login shell, or discovered command text to an existing-session attach.
5. Do not run a capability probe. Stock `zmx list` and `zmx attach` are the only remote operations discovery and attachment use.

## Discovery Rows

Stock zmx 0.8 changed detailed `zmx list` rows: rows are indented and `start_dir=` became `cwd=file://HOST/PATH`. The shared parser `claude-code-ide-zmx--parse-list-line` trims the row and derives `:start_dir` from `:cwd`. Both local and remote discovery use it.

## Verified Evidence - 2026-09-05

Local stock zmx 0.7.1 and `ramhorn` stock zmx 0.8.0, each in an isolated `ZMX_DIR`:

```text
zmx attach cci-probe-gone false   -> exit=1
zmx list --short                  -> empty, exit 0
```

Live attachment from a disposable batch Emacs with the Ghostel backend against the running session `cci-omp-saga-sdk-1lEr7U` on `ramhorn`:

- Discovery completed in 0.10 seconds and parsed the 0.8.0 row.
- Attachment reached a live terminal in 4.2 seconds. `zmx list` reported `clients=2` during the attachment.
- Killing the Emacs buffer detached only. `zmx list` reported `clients=1` and the same PID `411529` afterward. The manager retained the remembered row.
- No Agent input was sent. No Stop or kill ran.

## Accepted Limitation

A target that disappears in the race window produces one short-lived zmx session that runs `false` and exits. This leaves a log file under the zmx log directory and no running process. The user accepted this instead of maintaining a patched zmx on every host.

## Superseded Contract

The earlier `zmx attach --existing` prerequisite and its patched checkout under `/Users/fuyu0425/tools/zmx` are no longer part of this feature. Emacs never sends `--existing`.
