# Research: Spawn and Remove Sibling Sessions

## Pre-plan evidence (2026-11-01)

These facts come from the current code and from a zmx 0.8.1 test on the scratch sessions `cci-spike-run` and `cci-spike-att`. Both scratch sessions were killed after the test. The plan must keep these facts true.

| Topic | Evidence | Consequence |
|---|---|---|
| Agent → Emacs channel | omp writes `ESC]52;e;"claude-code-ide-session-editor-request" …` with `quoteOscArg` (`oh-my-pi/.../utils/external-editor.ts:219`). ghostel no longer acts on `51;E` (`ghostel/CHANGELOG.md:1666-1674`). `ghostel--osc52-eval` splits with `split-string-and-unquote` (`ghostel.el:3713-3718`). | Use `52;e` and one new `ghostel-eval-cmds` entry. |
| Handler context | The handler runs inside the VT parser. The editor request moves its work to `run-at-time` (`claude-code-ide-session.el:621-632`). | The spawn handler only validates and schedules. `zmx list` and attach run later. For `:host` the list is a remote call. |
| zmx create invariant | The package runs `env -u ZMX_SESSION -u ZMX_SESSION_PREFIX zmx attach NAME CMD` (`claude-code-ide-zmx.el:816-820, 875-883`). zmx help: `ZMX_SESSION` "makes attach switch this session". omp inherits A's name (`ide-state.ts:82`). | omp must remove both variables before it creates B. |
| `zmx run NAME -d CMD` | Creates the session and returns. Types the command into a login bash shell, appends `echo ZMX_TASK_COMPLETED`, records no `cmd=`. Help: stdin comes from `/dev/null`. | Not usable for an interactive Agent. CLI-type detection cannot read the command. |
| `zmx attach NAME CMD`, stdin not a TTY | Creates the session, prints `session "NAME" created`, returns at once. `zmx list` shows `clients=0` and the correct `cmd=`. | This is the create step. `--labels` sets labels in the same step. |
| Reattach replay | A PTY attach to both scratch sessions returned no `ESC]52` bytes. `history --vt` has none either. | An announcement does not fire again at reattach. |
| No client attached | Output from the child went to zero clients. | The announcement must come from A, not from B. With no Emacs on A it is lost. B stays discoverable through attach. |
| MCP discovery | omp finds the IDE bridge by lockfile poll (`oh-my-pi/.../mcp/manager.ts:1718-1720`). | Inherited env changes attribution only. MCP can reach a different Emacs than the one that shows A, so it is not the trigger. |
| Answer path | zmx drops APC answers from a client that is not the input leader (`ISSUE.org` Z1). | No answer from Emacs to omp. The announcement is one-way. |
| Tool gating pattern | `/guided-goal` adds `goal` to the active tools before its interview and records the previous set (`interactive-mode.ts:8388-8396`). `isToolAllowed` keeps `goal` out of the default set (`tools/index.ts:756-765`). | The spawn tool follows the same pattern. |
| Existing fork launch | `/fork pane` and `/fork window` build a child `omp --fork <session-file>` command with profile, model, thinking level, and scope env, then ask a multiplexer to run it (`command-controller.ts:1519-1646`). The multiplexer classifier has no zmx support. | Reuse the child-command builder. Add zmx as a launch target or call it from the spawn tool. |
| Exit-path row cleanup | `claude-code-ide--cleanup-on-exit` keeps a `[disconnected]` row for a zmx-backed Session. Its own verify call runs only for a local Session (`claude-code-ide.el:1264-1265`). A remote Session gets the same verify from its attach sentinel once the attach is ready (`:2147-2154`, `launch-ready` set at `:2189` for launch and attach). | FR-021 already holds for local and remote Sessions. No code change. Do not remove the host condition: that would send a second remote check and break `claude-code-ide-test-remote-verified-exit-skips-unready-attach`. |
| zmx ends with its command | `zmx attach cci-spike-exit sh -c 'sleep 1'` was listed at once and gone 2 seconds later. | Self-removal is omp `/exit` or `/quit`. No kill call is needed for the Session's own zmx session. |
| `/fork` refusals | `/fork pane` and `/fork window` refuse an unsaved session (`command-controller.ts:1537-1540`) and a session started with `--api-key` (`:1544-1548`). `zmx list` prints the full `cmd=`, as the spike showed. | FR-020 keeps both refusals for B. |
| zmx labels | `zmx attach --labels "k1=v1 k2=v2" NAME CMD` sets the labels at create time. `zmx list` prints each label as one more tab-separated `k=v` field after `cmd=`. `zmx get NAME K` prints the value. `zmx set NAME k=v` changes a label on a live session. The test used `cci-spike-lbl`, then killed it. | The parent link, the worktree record, and the working state are labels. Both package list parsers accept the extra `k=v` fields (`claude-code-ide-zmx.el:686`, `:895-940`). See the next row for the value encoding. |
| zmx title | `zmx list` prints no `title=` field, even after the child sets an OSC 0 title (`cci-spike-ttl`). | A cannot read B's working state from the title. B publishes it as a label. |
| Bun env | `Bun.spawnSync(["env"], {env: {...process.env, ZMX_SESSION: undefined}})` prints no `ZMX_SESSION`. | omp removes A's variables with `undefined` values. It needs no `env -u` prefix. |
| zmx versions (T002) | `zmx version` gives 0.8.1 on the local machine, `vps`, and `v12mac`, and `0.8.1-cci014-backpressure` on `v12dev`. On `v12dev`, `zmx attach --labels`, `zmx set` (change and remove), `zmx get`, `zmx list`, and `zmx kill` gave the expected labels (`cci-spike-v12`, killed after the test). `ramhorn` did not answer SSH (connect timeout), so its version is unknown. | The local machine, `vps`, `v12mac`, and `v12dev` are supported. Check `ramhorn` before you use it as a spawn host. |
| Child `ZMX_SESSION` (T002) | `env -u ZMX_SESSION -u ZMX_SESSION_PREFIX zmx attach cci-spike-env sh -c 'printenv ZMX_SESSION; sleep 5' </dev/null`, then `zmx history cci-spike-env`, printed `cci-spike-env`. The session was killed after the test. | zmx sets B's own name in B's env. B can publish `cci-state` and can run its own `/spawn`. |
| zmx label charset (T035) | A percent-encoded value failed: `Error: key-value kvs can only contain [a-z, A-Z, 0-9, -_.] characters: value=[Run%20the%20shell]`. | omp writes every `cci-*` value as unpadded base64url text. |
| Agent command check (T035) | A source run of omp gave B `cmd=bun …/cli.ts`. Emacs skipped B with "Attached 0 zmx sessions; skipped …", because `claude-code-ide-zmx-infer-cli-command` does not know `bun`. | B runs the executable of A's own zmx `cmd=`, which Emacs already accepted. |
| Parallel spawn calls (T035) | Code reading: the tool set of a model request is fixed when the request starts. Every call in one assistant message runs, also after the first call closes the window. In two live tries the model sent only one call, so a live run did not show the double spawn. | The handler refuses a second call in the same agent run (SC-008). |

## Phase 0 decisions

### D1. Announcement format

- **Decision**: omp writes `ESC]52;e;"claude-code-ide-session-spawn-announce" "<B zmx name>" ESC\`. It uses `quoteOscArg` and `writeTerminalSequence`, and wraps the bytes for tmux when `TMUX` is set. See `contracts/osc-spawn-announce.md`.
- **Rationale**: This is the same channel and quoting as the editor request (`utils/external-editor.ts:219`). zmx already knows B's directory and command, so the name is enough.
- **Alternatives**: A directory argument. It would be a second source for a fact that zmx owns, and a fake announcement could pair a real name with a wrong directory.

### D2. Emacs adoption reuses `attach-all`

- **Decision**: The handler checks the buffer and the name, then schedules one timer. The timer lists zmx on A's host, keeps only the entry with B's name, and calls `claude-code-ide--attach-zmx-entries`. Local Sessions use `claude-code-ide--zmx-adoptable-sessions`. Remote Sessions use `claude-code-ide-zmx-discover-remote` with `claude-code-ide--remote-discovery-callback`. After the attach, `claude-code-ide--live-session-for-target` finds B, and `claude-code-ide-manager-switch-to-session` shows it when `claude-code-ide-switch-on-spawn` is non-nil.
- **Rationale**: `attach-zmx-entries` already rejects an entry with an `:error`, an unknown `:cmd`, or a missing or invalid `:start_dir` (FR-011). The remote path already checks host approval and removes targets that are live. Local and remote use one path (principle VI).
- **Alternatives**: A new attach function. It would copy those checks.

### D3. Package name check

- **Decision**: Add `claude-code-ide-zmx--package-name-p`. It is `claude-code-ide-zmx--valid-name-p` plus a prefix check on `claude-code-ide-zmx-session-prefix`. The handler calls it before it schedules work.
- **Rationale**: FR-011 needs "a valid package name". The package has no such check today.

### D4. FR-021 needs no package change

- **Decision**: Keep `claude-code-ide--cleanup-on-exit` as it is. See the "Exit-path row cleanup" row. The remove flow ends B's zmx session. B's attach client then exits, and the existing local or remote verify removes the row and the buffer.

### D5. Spawn window follows the `loop` tool pattern

- **Decision**: InteractiveMode sets one session-held spawn handler at startup and keeps it for the life of the Session. The handler does the spawn work. A separate window flag on the session controls exposure. `/spawn` sets the flag and adds the hidden tool `spawn_session` to the active tools. `isToolAllowed` admits the tool only while the flag is set, the same way it checks the loop handler for `loop` (`tools/index.ts:766`). The window ends at the first spawn call, at a Session switch (`#reconcileModeFromSession`), or at `agent_end` when the run's messages have no `spawn_session` call and no `ask` call. The end clears the flag and restores the previous tool set. The handler stays. The handler also refuses a second call in the same agent run, before its first `await`, so parallel calls in one message create one session (SC-008). The refusal resets at `agent_start` and when `/spawn` opens its window, because a queued `/spawn` joins the running agent run.
- **Rationale**: A runtime gate cannot come back through a stale tool snapshot. The tool stays free of TUI imports. `#beginGuidedLoopInterview` and `#endGuidedLoopInterview` (`interactive-mode.ts:8464-8480`) are the lifecycle to copy. Because the handler does not depend on `/spawn`, the tool works whenever it is in the tool set (FR-018). A later change that exposes the tool by default changes only the `isToolAllowed` check. It needs no new tool and no new handler.
- **Edge**: When `ask.enabled` is off, the model cannot ask the FR-003 question. The model then picks the most likely mode, as the FR-003 exception requires. The confirmation setting (FR-022) is the only check for this case.
- **Alternatives**: The `goal` pattern. It gates on goal state, which is heavier.

### D6. Child command reuses the `/fork` builder

- **Decision**: Move the argv build of `#handleForkTerminalCommand` (`command-controller.ts:1543-1613`, with `FORK_LAUNCH_OVERRIDES`, `forkScopeEnvCommand`, `hasForkApiKeyOverride`) into one exported helper. It returns `{ argv, env }` and takes an optional fork session file and an optional `model`. `/fork pane` and the spawn both call it. `/fork` passes no `model`. `/fork` keeps its `env` prefix form, and the spawn passes `env` to `ptree.exec`.
- **Rationale**: One builder keeps the profile, model, thinking level, prompt-cache key, and the `--api-key` refusal the same for both (FR-020). The `model` argument covers the spec assumption "B uses A's model unless the request names a different one". It replaces only the `--model` value, so profile and thinking level still come from A.

### D7. Start content goes through a file named in the environment

- **Decision**: omp writes the opening prompt, the handoff note, or the handoff summary to a mode-0600 file in the OS temp directory. It names the file in B's `OMP_SPAWN_START_FILE`. `createSibling` sets or clears that variable for each child. Fork modes add `--fork <session file>` to argv. At startup B reads the file, deletes it and the variable, and sends the text as a plain first message (`takeSpawnStartText`, `main.ts`). A failed creation deletes the file.
- **Rationale**: `zmx list` shows only argv, so the text stays out of `cmd=`. B's first message shows only the text. A cleared variable means a restart or a child of B never reads a stale path.
- **Alternatives**: An `@file` argument (the first version). omp wraps its content in a `<file name="…">` block, which B then shows as its first message. A positional message puts the full prompt in `cmd=`. Piped stdin turns omp into print mode (`main.ts:1960-1968`).

### D8. Handoff summary without compaction

- **Decision**: Add the public method `AgentSession.generateHandoffDocument(customInstructions?, options?)`. It returns the result of the private `SessionHandoff.generateDocument`. The spawn writes the document to the start file. It never calls `AgentSession.handoff`.
- **Rationale**: `generateDocument` reads a snapshot and changes no history (`session/session-handoff.ts:~93`). `handoff` commits a compaction (`session/session-maintenance.ts:2206`), which FR-007 forbids.

### D9. zmx create

- **Decision**: `ptree.exec(["zmx", "attach", "--labels", labels, name, ...argv], { cwd: bDir, env, allowNonZero: true, timeout })`. `env` is the builder env with `ZMX_SESSION`, `ZMX_SESSION_PREFIX`, and `EMACS_BUFFER_NAME` set to `undefined`, and `OMP_SPAWN_PARENT` set to A's name. `stdin` is `ignore` by default, so zmx creates the session and returns. A non-zero exit shows the zmx error, runs `zmx kill <name>` without a check, and sends no announcement (FR-009). When the spawn made a new worktree, the failure path also removes it and its branch with `removeSessionWorktree(wt, false)`, so a failed spawn leaves nothing behind.
- **Executable**: `argv` starts with the executable of A's own zmx `cmd=` (`zmxSessionExecutable`, which skips `command`, `exec`, `env`, `nohup`, and `VAR=` words). Emacs already accepted that command as a known Agent (FR-011). When the lookup fails, omp uses `resolveCliEntryCmd`.
- **Name**: `<prefix>omp-<sanitized basename of bDir>-<6 random lowercase letters or digits>`. The prefix is the part of A's `ZMX_SESSION` before its first `omp-`. When A's name has no `omp-`, omp uses `cci-`. The sanitize step lowercases and turns each run of other characters into `-`, the same as `claude-code-ide-zmx--sanitize`.
- **Rationale**: The package recognizes the name and infers omp from `cmd=` (FR-005, FR-011). B keeps `TERM_PROGRAM`, `FORCE_CODE_TERMINAL`, and `PI_FORCE_IMAGE_PROTOCOL` from A, which are correct for a Ghostel terminal too.

### D10. Labels

- **Decision**: B's zmx session gets `cci-parent=<A name>` (FR-006). A spawned worktree adds `cci-wt-path`, `cci-wt-branch`, `cci-wt-base`, and `cci-wt-source` (FR-023). At the first `message_start` of a run, B sets `cci-state=working` and `cci-work=<first line of the first user or assistant message that is not only a tag, at most 80 characters>`. At `agent_end`, B sets `cci-state=idle` and removes `cci-work`. B uses one `zmx set $ZMX_SESSION` call each time, and only when `OMP_SPAWN_PARENT` is set. Every value is unpadded base64url text, because zmx accepts only `[A-Za-z0-9-_.]` in a value. See `contracts/zmx-labels.md`.
- **Rationale**: The labels live as long as the session, so they need no file and no cleanup. A reads them with one `zmx list`. `cci-state` and `cci-work` let the remove confirmation name the running work (FR-015).
- **Alternatives**: A JSON record file per child. It needs cleanup and a path scheme.

### D11. Remove flow

- **Decision**: `/despawn` runs `zmx list`, keeps the sessions whose `cci-parent` equals A's `ZMX_SESSION`, and shows them with `showHookSelector`. With a worktree record, omp rebuilds a `SessionWorktree` and gets `decideWorktreeExit(cfgWorktreeOnExit.get(settings), inspectSessionWorktree(wt))`. One `showHookSelector` dialog is the whole remove confirmation. It names the target. When `cci-state=working`, it adds "It is working on: <cci-work>" (FR-015). It offers the worktree choice that the exit action allows (FR-024). When the user chose a removal, omp builds the plan with `planWorktreeExit([wt], "remove", async () => true, warn)`. Then omp runs `zmx kill <name>` and `removeExitWorktrees(plan)`. See contracts/omp-spawn.md `/despawn`.
- **Rationale**: FR-024 puts the `ask` question inside the remove confirmation, so the worktree choice and the kill confirmation are one dialog. `decideWorktreeExit` and `planWorktreeExit` already implement keep, ask, and remove with the dirty, moved, and off-branch checks. `removeExitWorktrees` checks the fingerprint again after B ends. A worktree without a record is never in the plan.
- **Alternatives**: Add the child worktree to A's `#ownedWorktrees`. Then A's own `/exit` would also ask about it.

### D12. Command names and setting

- **Decision**: `/spawn <request>` and `/despawn`. They go in `BUILTIN_SESSION_SLASH_COMMANDS` next to `/fork`. The confirmation setting is `spawn.confirm` (boolean, default `false`) in `tools/settings.ts`.
- **Rationale**: Neither name collides with `/new`, `/fork`, `/handoff`, `/wt`, `/exit`, or `/quit`.

### D13. Busy Session and refusals

- **Decision**: `/spawn` refuses at once when `ZMX_SESSION` is unset or the child argv has `--api-key` (FR-020). The tool refuses a fork mode when the session has no saved file. A running turn queues the kickoff with `followUp`, as `/guided-goal` does.
