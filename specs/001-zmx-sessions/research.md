# Research: zmx-backed persistent agent sessions

Phase 0 output. All Technical Context unknowns resolved. Primary source: the
reference implementation cloned at `refs/emacs-term-sessions` (term-sessions.el,
GPL-3+), whose zmx layer was read in full this session. It stays a reference,
never a dependency (ADR 0001).

## R1: zmx CLI surface

- **Decision**: Use exactly four zmx invocations: `zmx attach <name> [cmd...]`
  (creates the session when missing, attaches otherwise), `zmx list` /
  `zmx list --short`, and `zmx kill <name>`. Ignore `send`, `run`, `wait`,
  `history`, and `version`.
- **Rationale**: The four calls cover every FR. `attach` doubling as create
  removes a create/attach branch. The reference implementation confirms the
  attach-creates behavior and the argument shapes.
- **Alternatives considered**: `zmx run`/`wait` for job control — out of scope,
  detached.el territory. `zmx history` for transcript recovery — follow-up.

## R2: `zmx list` output parsing

- **Decision**: Parse tab-separated `key=value` rows into plists; accept
  `--short` (bare names) as fallback for older builds. Fields used: `name`,
  `start_dir`, `cmd`. Tolerate absent fields.
- **Rationale**: This is the format the reference parser
  (`term-sessions--parse-key-value-fields`) handles, including the
  older-build fallback. Tolerant parsing removes any zmx version pin — the
  one Outstanding item from clarification.
- **Alternatives considered**: JSON output — zmx does not offer it. Pinning a
  minimum zmx version — needless; the tolerant parser is smaller than a
  version check.

## R3: Command wrapping and quoting

- **Decision**: Build the wrapped command with
  `(combine-and-quote-strings (append (list zmx-program "attach" name) (split-string-and-unquote cmd)))`
  at the shared seam `claude-code-ide--create-terminal-with-command`.
- **Rationale**: The agent builders produce shell command strings (for example
  `"claude -c"`). Splitting to argv and re-quoting keeps flags intact and is
  the exact recipe the reference `term-sessions--attach-command` uses. Placing
  it at the shared seam satisfies constitution principle I: zero per-agent code.
- **Alternatives considered**: Wrapping inside each `--build-*-command` —
  rejected, four duplicated call sites. Passing the raw string as one argv
  element — rejected, zmx would exec a program literally named `claude -c`.

## R4: Environment propagation

- **Decision**: Keep env handling unchanged. Env vars flow into the terminal
  process (`vterm-environment` etc.); when `zmx attach` creates the session,
  the new PTY inherits them.
- **Rationale**: First attach is process creation, so inheritance holds. Later
  attaches keep the original environment — the accepted stale-port limitation
  in ADR 0001 and the spec's Edge Cases.

## R5: Detach mechanics

- **Decision**: No changes to buffer-kill or Emacs-exit paths. Killing the
  terminal buffer or process kills only the local `zmx attach` client, which
  is a detach by definition. Only `claude-code-ide-stop` gains a zmx branch
  (prompt, then `zmx kill`).
- **Rationale**: Verified in source: session cleanup
  (`claude-code-ide--cleanup-on-exit`, `kill-emacs-hook` at
  claude-code-ide.el:1119) touches only the Emacs-side process and buffer.
  The zmx server process is not a child of the attach client.

## R6: zmx session naming

- **Decision**: `<prefix><agent>-<project>-<id-short>` where prefix defaults to
  `cci-` (defcustom `claude-code-ide-zmx-session-prefix`), agent is the CLI
  type symbol name, project is the sanitized directory basename (lowercase,
  non-alphanumerics collapsed to `-`), and id-short is the random suffix that
  `make-temp-name` already appends to the session-id
  (claude-code-ide.el:1710).
- **Rationale**: Reuses the existing uniqueness source instead of minting a
  second one. The sanitizer mirrors the reference implementation's cleaner and
  keeps names shell-safe.

## R7: CLI-type inference for adoption

- **Decision**: Take the first word of the zmx `cmd` field, match its file
  name base against the values in `claude-code-ide-agent-definitions` plus the
  current `claude-code-ide-cli-path`. No match or ambiguity → `completing-read`
  over agent names.
- **Rationale**: Agent commands are single well-known binaries (`claude`,
  `codex`, `opencode`, `pi`, `omp`), so head-word matching is sufficient and
  cheap. The prompt fallback is FR-008's requirement.
- **Alternatives considered**: Encoding the CLI type only in the session name —
  works for Emacs-created sessions but fails the terminal-launched adoption
  case, which is the point of the feature.

## R8: Test strategy without zmx

- **Decision**: Route every subprocess call through one function,
  `claude-code-ide-zmx--call`, and one availability check,
  `claude-code-ide-zmx--ensure`. Tests bind them with `cl-letf` to canned
  outputs, following the suite's existing vterm/websocket mock pattern.
  Parser and name-builder tests are pure-function tests needing no mocks.
- **Rationale**: Constitution principle II requires batch tests with no
  optional dependency installed. A single choke point makes the mock trivial.
