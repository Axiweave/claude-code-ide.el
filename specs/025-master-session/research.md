# Research: Master Session for Chat Dispatch

Facts come from three read-only scouts, run on 2026-11-09 against the working trees of the package, omp (`~/agents/oh-my-pi`, branch `024-session-launch-intake`), and the Intake (`~/agents/cci-intake`). Anchors are `file:line` in those trees.

## D1. The Master Session is an Intake Launch of kind `master`

- **Decision**: Add a `kind` column to `launches` with the values `session` (default) and `master`. A new route `POST /v1/master` returns the live master Launch, or creates one. The Intake starts it with `[master]` settings from its own configuration: `path`, `omp`, `launch_session`, and `prompt`. It always runs on the host `local`, which is the Intake host.
- **Rationale**: FR-008 and FR-045 need the Intake to know the Master Session. A Launch already has a state, a zmx name, the reconcile loop, stop, and adoption. One idempotent route makes FR-002 hold: the route never creates a second master while one is `queued`, `starting`, or `running`.
- **Alternatives considered**: (a) Emacs starts the master and the Intake finds it by label. This gives two start paths, and it conflicts with Q2: the open command must fail when the Intake is down. (b) A Linear-style project entry for the master. A project needs Linear mapping fields and slots, and the master is not a project.

## D2. The master directory need not be a Git checkout

- **Decision**: `omp launch-session` checks `--cwd is not a Git checkout` only when `--branch` is given. Without `--branch`, any existing absolute directory is valid.
- **Rationale**: The check exists for the worktree step (`commands/launch-session.ts:24-28`). `spawnSession` makes a worktree only when `branch` is set (`session/sibling-spawn.ts:~187`). FR-003 asks for a directory that belongs to no project. A forced `git init` would make the package group it as a Git project.
- **Alternatives considered**: Ask the user to run `git init` in the master directory. This works with no omp change, but it leaks a fake repository into the manager and into `git` tools.

## D3. Emacs reads two zmx labels for the Master rules

- **Decision**: The Intake passes `--label cci-role=master` on the master Launch, and `--label cci-origin=master` on each Launch whose origin is the Master Session. Emacs reads both labels from the zmx list entry in `claude-code-ide--attach-spawned-entry` (`claude-code-ide.el:2713-2729`). One function, `claude-code-ide--spawn-switch-p`, holds the switch rule for all adopted Sessions:
  1. The entry has `cci-origin=master`: do not switch (FR-020).
  2. The entry is the master that the open command waits for: switch (FR-001).
  3. Otherwise: follow `claude-code-ide-switch-on-spawn` (FR-021).
- **Rationale**: Both adoption paths, push and pull, and the `/spawn` path end in that one function with the zmx entry in hand. Local and remote entries carry the same fields (`claude-code-ide-zmx.el:692`, `:901`). So no push form, SSE parser, or `adopt-session` signature changes. A label also survives an Emacs restart, when the pull stream gives no history. FR-004 forbids detection by name or directory, and a label is neither.
- **Alternatives considered**: (a) A third argument to `claude-code-ide-adopt-session` plus `origin.source` in the pull path. This changes three call paths, and push and pull race on the adopted list, so both must carry it. (b) Ask the Intake on each adopt. This adds an HTTP call to a path that works without the Intake today.
- **Encoding**: label values are base64url (`sibling-spawn.ts:63-65`). Emacs decodes them with `base64-decode-string` and its BASE64URL argument (Emacs 27.1+, within the 28.1 floor).

## D4. Origin `master` comes from a master-only token

- **Decision**: `[master].token_file` names a second bearer token. The `cci` command line (D9) uses only this token. The Intake gives every request with this token the origin `master`: a Launch request records its Trigger with `source = "master"`, and `startLoop` passes `cci-origin=master` to omp. A request with the shared token can never get the origin `master`. The request body has no `origin` field. `triggers.source` has no CHECK, so only the TypeScript type widens (`db.ts:9-12`).
- **Rationale**: The question here is identity, not secrecy. With a body field, a call that forgets the field gets the 024 default (the main checkout), no focus rule (FR-020), and no Notices (FR-040). With the token, every `cci` call is a master call, and no other caller can claim to be the master.
- **Known limit**: The master has the full tool set (D10), and both token files are in the same home directory. A raw `curl` with the shared token still bypasses FR-012, FR-015, FR-020, FR-040, and FR-051 (the `held` gate applies only to master-token Launches, D12). A master-token Launch still waits, because `confirm` and `decline` answer 403 to that token. The master's `AGENTS.md` tells it to use only `cci`.
- **Alternatives considered**: A body field `origin: "master"`. It fails open when the field is missing.

## D5. FR-015: a master request names its checkout choice

- **Decision**: A Launch request with the master token must carry exactly one of `worktree` (an object) and `"main_checkout": true`. Otherwise the Intake answers 400 and records nothing. This is the existing 400 style (`launches.ts:61-70`). A shared-token request keeps the 024 rule: no `worktree` means the main checkout. A shared-token request with `main_checkout` gets 400.
- **Rationale**: In 024, an omitted `worktree` runs in `project.path` (`launches.ts:90`). A forgotten field from the master would edit the user's checkout. The Intake now refuses the request instead. The `cci` command line sends `worktree: {}` unless the master passes `--main`.

## D6. Notices: a turn counter label, one row for each worker, and their own sender

- **Decision**:
  - omp adds `cci-turn=<n>` to the same `zmx set` that publishes `cci-state=idle` on `agent_end` (`modes/interactive-mode.ts:9023-9025`, `session/sibling-spawn.ts:277-290`). `n` counts `agent_end` events in this omp process and starts at 1. One `zmx set` call writes both labels, so the Intake never sees `idle` with an old counter. The counter never starts again inside one Launch: omp is the zmx session's command, so when omp exits, the zmx session ends, and the Launch ends with it.
  - The Intake keeps `launches.notified_turn`. In the reconcile loop (`launches.ts:219-224`), for a `running` Launch with origin `master`: when `cci-state` is `idle`, `cci-turn` is present, and `cci-turn` is above `notified_turn` (or `notified_turn` is NULL), the Intake writes a Notice and stores the new `notified_turn` in one transaction. This is the FR-040 rule.
  - The `launches` change listener (`main.ts:10-15`) writes a Notice when a Launch with origin `master` changes to `ended`, `failed`, or `refused`.
  - Table `notices` has one row for each worker (`worker_id` is the primary key). A new Notice replaces the row and sets it to `pending`. This is the coalescing that FR-045 needs.
  - `sendNotices()` runs on the master Launch's follow-up chain, so Notices and follow-ups to the master keep one order. It sends only when a master Launch is `running` and its `agent_state` is set, which is the T082 readiness rule. For each `pending` row, oldest first, it runs `zmx send <master> pi:send;queue.<b64>`. Exit 0 marks the row `sent`. Any other exit returns the row to `pending` for the next tick.
- **Rationale**:
  - The 10 s tick can miss a short turn, because the `agent_state` change test (`launches.ts:222`) sees `idle` on both sides. A counter cannot miss a turn (FR-040, FR-044).
  - `notified_turn` is in the database, so a restart sends no duplicate (US4 AC5).
  - Notices are not rows in `followups`. A follow-up belongs to one Launch, and `refusePendingFollowups` refuses it when that Launch ends (`launches.ts:46`). That would lose a Notice when the master goes down, against FR-045. A row for each worker, sent to whichever master runs, keeps it.
  - `queue` mode waits for the master's current turn (`interactive-mode.ts:4434`, `:4450-4459`). This is FR-041. `runCommands: false` means a Notice cannot run a slash command.
  - A failed `zmx send` goes back to `pending`. 024 refuses to retry a step whose result is unknown. Here a duplicate Notice holds only Intake facts, and a lost one breaks FR-045, so a retry is the safer side. For the same reason, `recover()` sets each row left in `sending` by a crash back to `pending`.
- **Alternatives considered**: (a) Trigger on the `cci-state` change. The tick misses short turns (advisory, `launches.ts:214-215`). (b) Make each Notice a follow-up on the master Launch. Notices are lost when the master ends (above). (c) "Not equal" on the turn. It guards against a counter that starts again, which cannot happen inside one Launch. A process-unique value such as `<start-ms>.<n>` would cover that case, but the case does not exist.
- **Older omp**: with no `cci-turn` label, the Intake sends no turn Notices. Notices for `ended`, `failed`, and `refused` still work.

## D7. Notice text is built from fields only

- **Decision**: The text is one line: `[intake notice] launch <id> project=<project> host=<host> state=<idle|ended|failed|refused> turn=<n|->`. Every value comes from config or from Intake-generated IDs. It has no `reason` field, because a `failed` reason can hold omp stderr text.
- **Rationale**: FR-043 and SC-008. A Notice turn then carries no text from a worker.

## D8. Recent output through `zmx history`

- **Decision**: `GET /v1/launches/{id}/output?lines=N` runs `zmx history <name>` through `run(host, …)` for a `running` Launch. It keeps the last `N` lines, with a default of 200 and a maximum of 2000. The answer is `{ "text": … }`. Other states give 409.
- **Rationale**: FR-031 needs the same path for local and remote hosts. `run()` already gives that (`hosts.ts:57`). omp has no command line that prints a Session's last reply (`commands/session.ts:25`; RPC `get_last_assistant_text` exists only in RPC mode). `zmx help` confirms `zmx history <session>`. `run()` keeps the full stdout (`hosts.ts`), so the Intake cuts it.
- **Note**: The text includes TUI chrome, and it is untrusted. The `cci` command line prints it between marker lines (D9).

## D9. The master's interface: a `cci` command line in the Intake repository

- **Decision**: Add `src/cli.ts` to the Intake, with a `package.json` `bin` entry `cci`. It reads the Intake configuration for `listen` and `[master].token_file`, so the token never shows in the chat or in a process argument. Because it sends the master token, every `cci` call has the origin `master` (D4). The subcommands are `projects`, `launch`, `list`, `show`, `output`, `send`, and `stop` (contract `cci-cli.md`). The master's `AGENTS.md` in the master directory names this command. The user writes that file. The package does not ship it.
- **Rationale**: An Agent that builds JSON for `curl` in bash fails on quotes and newlines. Each subcommand is one HTTP call. The text comes on stdin, so it needs no escaping.
- **Alternatives considered**: (a) Raw `curl` in the master's instructions. It breaks on quoting and shows the token in the shell history. (b) An MCP server. It adds a new dependency and a new process for nine HTTP calls.

## D10. FR-007: the master has the full tool set

- **Decision**: `[master].omp` starts omp with no `--tools` limit. The master's `AGENTS.md` keeps it to dispatch, tracking, and steering.
- **Rationale**: The user chose the full tool set (spec Clarifications). The master needs `bash` for `cci` anyway, and `bash` can write files. So a tool limit gives only a partial guard.
- **Alternatives considered**: `--tools read,grep,find,bash,todo` with `--no-extensions`. It removes `edit`, `write`, `eval`, and `task`, but `bash` stays as a way to write files. A dedicated `cci` tool without `bash` would be the only hard limit. That needs an omp extension.

## D11. The master does not use a host slot

- **Decision**: A `master` Launch does not count against `max_sessions`, and `startNext` starts it before the queued Launches.
- **Rationale**: The open command must not wait behind a full local host. One extra Session on the Intake host is small.

## D12. Confirmation: state `held`, two routes, and one Emacs command

- **Decision**:
  - Intake configuration: `[master] confirm = false`.
  - With `confirm = true`, a Launch with origin `master` starts in the new state `held`. It does not use a slot, and `startNext` skips it.
  - `POST /v1/launches/{id}/confirm` changes `held` to `queued`.
  - `POST /v1/launches/{id}/decline` changes `held` to `refused`, with the reason `declined by user`. A Notice reports the refusal to the master (D6), which is FR-052.
  - Both routes answer 403 to the master token, so the master cannot confirm its own Launches. `cci` has no `confirm` or `decline` subcommand.
  - Emacs gets the command `claude-code-ide-intake-confirm`. It reads the `held` Launches, asks with `completing-read` when there are several, and shows the project, host, and full prompt in a `yes-or-no-p` question. Then it posts `confirm` or `decline`. When `claude-code-ide-intake-mode` gets a `held` event, it shows one message that names the command.
- **Rationale**: A minibuffer question does not change the selected window (FR-051). A question that opens by itself from a process filter would take the user's keys in the middle of typing, so a command asks only when the user runs it. The master also tells the user in the chat that the Launch waits.
- **Alternatives considered**: An immediate `yes-or-no-p` from the SSE filter. It takes over the user's typing, and with two Emacs instances both would ask.

## D13. The Master section in the Session manager

- **Decision**: The Session struct and the manager item get a `master` slot. Emacs sets it when the zmx entry has `cci-role=master`, in `claude-code-ide--attach-zmx-entry` (`claude-code-ide.el:2574`) and in the spawn adoption path. `--render` (`claude-code-ide-manager.el:3278`) draws the master rows under one `Master` heading before the Project groups. `--group-headings` and `--sorted-items` leave out master rows. The slot is in `--serialize-item` and `--deserialize-item` (`manager.el:1594`, `:1614`), so a disconnected master row stays in its section.
- **Rationale**: FR-005. The grouping key of a directory outside Git would give the master its own one-row "project" group. That is the wrong message.

## D14. The open command: `claude-code-ide-master`

- **Decision**: The command is in `claude-code-ide-intake.el`. It needs `claude-code-ide-intake-url` and `curl`. When the URL is nil or `(executable-find "curl")` is nil, it signals a `user-error` (constitution III). It calls `POST /v1/master`:
  - Connection failure or 5xx: one message that names the URL (FR-009). Nothing more happens.
  - The master is `running` and attached in Emacs: show it.
  - Otherwise: poll `GET /v1/launches/{id}` once a second, for up to 45 s. The Intake sets `name` and `running` in one change (`launches.ts:158-159`, `:178-179`) and pushes its own adopt call at that moment (`main.ts:12`). So the pending pair cannot exist before `running`, and the push may reach Emacs first.
  - At `running`, set `claude-code-ide--master-open-pending` to `(EMACS-HOST . NAME)`. EMACS-HOST is the Launch's `emacs_host` (`:null` becomes nil), as in `claude-code-ide-intake--adopt` (`claude-code-ide-intake.el:104-109`). The Launch's `host` key is `local` for this machine and would never match rule 2.
  - Then: if the Session is live, show it and clear the pair. If the pair is in `claude-code-ide--pending-adoptions`, an attach is in flight, and `--attach-spawned-entry` decides the switch at attach time (`claude-code-ide.el:2722`), so rule 2 applies with no further call. Otherwise remove the pair from `claude-code-ide--adopted-sessions` and adopt through `claude-code-ide-intake--adopt`. `adopt-session` never adopts a pair a second time (`claude-code-ide.el:2806-2808`), so without this removal a master that the user disconnected would not attach again (spec edge case).
  - `--curl` (`claude-code-ide-intake.el:66-102`) gets optional `method` and `body` arguments. Both go on curl's stdin configuration, so the token stays off the argument list. The command also writes the HTTP status, so that a 4xx answer can show its `error` text.
- **Rationale**: Adoption is asynchronous, and `adopt-session` returns before the attach. The pending name lets the one switch rule show the Session, and it needs no new callback path. The poll covers an Emacs with no pull mode and no push target.

## D15. Constitution I: what the package owns

The package owns the label names `cci-role` and `cci-origin`, the open and confirm commands, the switch rule, and the Master section. The master directory, its `AGENTS.md`, its opening prompt, and its omp command are all in the Intake configuration (`[master]`) and in the user's files. This is FR-006.

## D16. Schema change without a migration

- **Decision**: Change the `CREATE TABLE` statements: `launches.kind`, `launches.notified_turn`, `held` in the state CHECK, and the new `notices` table. The quickstart deletes `~/.local/state/cci-intake/intake.db` once.
- **Rationale**: The project has no backward-compatibility rule (AGENTS.md). 024 removed its only migration shim and recreated the database.
