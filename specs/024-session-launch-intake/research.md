# Research: Launch Agent Sessions from Outside Events

## Pre-plan evidence (2026-11-08)

The facts below come from the current code, the Linear schema, and zmx 0.8.1 tests on the scratch session `cci-spike-send`. Each test killed its session afterward. Paths that start with `oh-my-pi/` are under `~/agents/oh-my-pi/packages/`.

| Topic | Evidence | Consequence |
|---|---|---|
| CLI name | `omp launch` already exists (`oh-my-pi/coding-agent/src/cli-commands.ts:25-32`). | The new command is `omp launch-session`. |
| Subcommand pattern | One entry in `commands` (`cli-commands.ts:25-39`) plus a `Command` class. `commands/commands.ts:61-86` is a headless template with `--json`. | Copy that pattern. |
| `/spawn` core | `createSibling` (`session/sibling-spawn.ts:104-145`), `siblingName` (`:40-52`), `encodeLabels` (`:66`), and the start-file write (`modes/interactive-mode.ts:8906-8912`) are free of the TUI. `#spawnSibling` (`:8806-8936`) also uses the live session, dialogs, and the OSC 52 announcement. | Move the core into one shared function. `/spawn` and `launch-session` both call it (FR-002). |
| Branch suffix | `freeBranchName(cwd, branch)` returns `branch`, `branch-2`, … (`session/session-worktree.ts:83-90`). `createSessionWorktree(cwd, settings, branch, …)` takes an explicit branch (`:134`). | FR-055 needs no new code. |
| Opening prompt | The child reads the start file with `takeSpawnStartText` (`sibling-spawn.ts:258`, `main.ts:868-871`). `zmx list` prints the full `cmd=` (spec 021 research, row "`/fork` refusals"). | The prompt goes through the start file, never through argv. |
| Agent command check | Emacs skips a `cmd=` that it does not know, for example `bun …/cli.ts` (spec 021 research, row T035). | The Intake passes the real omp executable from its configuration. |
| State labels | `cci-state` and `cci-work` publish only when `OMP_SPAWN_PARENT && ZMX_SESSION` (`interactive-mode.ts:3116`). `createSibling` sets `OMP_SPAWN_PARENT` only from a `cci-parent` label (`sibling-spawn.ts:131`). Emacs reads neither label. | A launched Session publishes nothing today. The gate needs one more condition. |
| `zmx list` labels | `parseZmxList` reads each tab field and base64url-decodes `cci-*` values (`sibling-spawn.ts:77-93`). | The Intake reads launch and state labels from one `zmx list` call. |
| Input while a turn runs | Enter steers (`modes/controllers/input-controller.ts:1507`). Ctrl+Q queues a follow-up (`:2380`). Escape aborts (`:2434-2436`). `session.prompt(text, {streamingBehavior: "followUp" \| "steer"})` covers both, and on an idle Session it starts a turn (`session/agent-session.ts:8750-8760`). | omp already has all three follow-up values. Only a channel is missing. |
| APC input | The composer accepts `ESC _ pi:(prompt\|keyword\|action);VALUE ESC \` with no `/`, space, or control byte in VALUE (`tui/src/prompt/composer.ts:365`). | A new kind `send` with a base64url value fits the regex. |
| Typed text | A CR submits (`tui/src/components/editor.ts:2385`). Unbracketed multi-line text can replay as keys under load (`tui/src/stdin-buffer.ts:765-773`). | Typing text into the PTY is not safe for a follow-up. |
| `zmx send` local | `zmx send cci-spike-send "$(printf '\033_pi:send;queue.aGk\033\\')"` into `cat -v` showed `^[_pi:send;queue.aGk^[\`. | `zmx send` carries the packet bytes unchanged. |
| `zmx send` remote | The same packet as one single-quoted word in `ssh v12dev "zmx send cci-spike-send '…'"` showed the same bytes. | The remote path needs only POSIX single quotes. |
| Adopt function | `claude-code-ide--adopt-spawned-session HOST NAME` (`claude-code-ide.el:2725-2745`) adopts one entry. It is synchronous for a local Session. For a remote Session it calls back after one `ssh … zmx list`. It never signals. | The public command wraps it and returns at once. |
| Double adoption | Local adoption lists only unattached sessions (`claude-code-ide.el:2548-2549`). Remote adoption drops live targets in its callback (`:2662-2670`). Two remote lists in flight can both pass. | The wrapper keeps a set of pending adoptions. |
| HTTP client | The package has no HTTP client. `claude-code-ide-mcp-sse-server.el` is server only. | The pull path runs `curl -sN` as a process, like `claude-code-ide-zmx--run-remote-command` (`claude-code-ide-zmx.el:139-243`). |
| Stop | Emacs Stop runs `zmx kill NAME` (local, `claude-code-ide-zmx.el:1010-1013`) or one remote kill with a list check (`:1100+`). It removes no worktree. Emacs drops the row when the attach client ends and the name is gone (`claude-code-ide.el:1275-1310`). | The Intake runs the same `zmx kill` and the same list check (FR-029). |
| Linear label history | `IssueHistory` has `id`, `createdAt`, `actorId`, `botActor`, `addedLabelIds` (Linear SDL). `actorId` is null for automations. There is no root history query. `IssueFilter` has `updatedAt`, `team`, `labels`. | Poll issues by `updatedAt` and read each issue's `history`. |
| Linear comments | Root `comments(filter: {createdAt, issue})` exists. `Comment` has `user`, `botActor`, `issueId`. `commentCreate` takes a client-chosen `id`. | One query covers every live Launch. The client `id` is the self-skip key. |
| Linear limits | A personal API key sends `Authorization: <key>` with no `Bearer`. The limits are 2,500 requests and 3,000,000 complexity points per hour. | One label poll and one comment poll every 30 s use about 5% of each limit. |
| T022 label filter (2026-11-08, team YU) | `issues(filter: {labels: {some: {id: {eq: $l}}}})` returns the labeled issue. `labels: {id: {eq: $l}}` also works. | The poll uses `labels: {some: {id: {eq}}}`. |
| T022 comment ID reuse | A second `commentCreate` with an ID that exists returns `INPUT_ERROR` "conflict on insert of Comment". No second comment appears. | A resend at restart is safe. D15 needs no `comment(id:)` check. |
| T022 history gap | Issue YU-7, created with the label: no history entry after 3 min. Issue YU-6: labels added 7 s and about 1 min after creation got no entry. A label removed or added about 5 min after creation got an entry at once, with `actorId` and `addedLabelIds`. | Linear folds early label changes into the creation, so history alone misses an issue created with the label. D14 adds a creation Trigger. |

## Phase 0 decisions

### D1. Intake runtime

- **Decision**: Use one Bun 1.4 process: `Bun.serve` for HTTP and SSE, `bun:sqlite` in WAL mode for storage, `Bun.TOML` for configuration, and `Bun.spawn` for commands. Add no npm dependency. The repository is `~/agents/cci-intake`.
- **Rationale**: omp already uses Bun, and Bun covers every need from its standard library.
- **Alternatives**: Node plus Express and better-sqlite3 adds dependencies. Go or Rust adds a second toolchain for one small service.

### D2. One command boundary for every host

- **Decision**: Every host action goes through one function `run(host, argv, {stdin, timeoutMs})`. For the local host it runs `argv`. For any other host it runs `ssh -T -o BatchMode=yes -o ConnectTimeout=10 HOST -- <argv as single-quoted words>`. The default timeout is 30 s for the local host. For any other host it is 40 s: the 30 s plus the 10 s `ConnectTimeout`, because the timer starts before ssh connects. At the timeout, `run` sends SIGTERM to the child and gives it a 5 s grace to clean up. Then it sends SIGKILL if the child still runs. The result is exit code 124 in both cases.
- **Rationale**: Launch, list, send, and kill then have one code path (principle VI). The only remote difference is SSH transport and quoting, and the spike proved that the quoting carries the packet bytes.
- **Alternatives**: A small agent process on each host. That adds an install step on every host and a second protocol.

### D3. `omp launch-session`

- **Decision**: Add `omp launch-session --cwd DIR [--branch B] [--label k=v]… [--json] -- CHILD_ARGV…`. The command reads the opening prompt from stdin and writes it to the start file. `--branch` picks the next free name through `freeBranchName` and creates a worktree. The command prints one JSON line `{"name","dir","branch"}` and exits 0. On failure it prints `{"error"}` and exits 1, and the shared cleanup removes the zmx session, the worktree, and the branch.
- **Rationale**: The core moves from `#spawnSibling` into `spawnSession` in `session/sibling-spawn.ts`, and `/spawn` calls the same function (FR-002). The prompt goes through stdin and the start file, so `zmx list` never shows it. `CHILD_ARGV` comes from the Intake configuration, so the package owns no omp path (FR-022).
- **Alternatives**: A second copy of the spawn code breaks FR-002. A prompt argument puts private text into `cmd=`.

### D4. State labels for launched Sessions

- **Decision**: Change the gate at `interactive-mode.ts:3116` to `(OMP_SPAWN_PARENT || OMP_PUBLISH_STATE) && ZMX_SESSION`. `spawnSession` takes `publishState: true` and sets `OMP_PUBLISH_STATE=1` for `launch-session`.
- **Rationale**: A launched Session then publishes `cci-state` and `cci-work` like a Sibling Session (FR-004). It needs no fake `cci-parent` label, so `/despawn` lists stay correct.
- **Alternatives**: Remove the gate. Then every zmx omp Session runs `zmx set` on each turn.

### D5. Launch label for crash recovery

- **Decision**: Every Launch passes `--label cci-launch=<launch id>`. When the Intake finds a Launch in `starting` at restart, it lists the host. A session with that label makes the Launch `running`, and its `cci-wt-path` and `cci-wt-branch` labels give the Launch's `dir` and `branch`. When no session has the label, the Intake checks the age of the Launch. It sends a Launch with no failure reason back to `queued` only when its `updated_at` is older than 45 s: the 40 s remote command timeout plus the 5 s kill grace (D2). A younger Launch stays `starting`, and the next reconcile checks it again. A `launch-session` that is still running after the restart can therefore not start a second Session. When `launch-session` prints `{"error"}` and exits 1, it ran to its end and removed what it made, so the Intake marks the Launch `failed` at once. Any other result than exit 0 with a JSON `name` (for example a timeout with exit 124, an ssh exit 255, or output that is not JSON) can still leave a session. A remote command can also make it later, because it outlives a dropped ssh client. For these results, the Launch stays `starting` and gets the failure as its `reason`. The reconcile loop then checks it in the same way: a labeled session makes it `running` and clears the reason. When no session has the label after 45 s, the Launch becomes `failed` with that reason, not `queued`. A list that fails inside the 45 s changes nothing. A list that fails after the 45 s makes the Launch `failed`: with its stored reason, or, for a Launch that a restart cut off, with a reason that names the host (spec edge case "Host unreachable", SC-004). Limit: a host that made the session and then stays down for 45 s leaves that session with no Launch.
- **Rationale**: omp picks the random name, so a crash between the command and the database write would otherwise leave an unknown session and start a second one (FR-023, SC-003).
- **Alternatives**: Let the Intake choose the name. That splits the name rule between two programs and breaks FR-002.

### D6. Follow-up channel

- **Decision**: Add the APC kind `pi:send;<mode>.<base64url(text)>`, where `<mode>` is `queue`, `guide`, or `stop`. omp maps it as follows:
  - `queue` runs `prompt(text, {streamingBehavior: "followUp"})`.
  - `guide` runs `prompt(text, {streamingBehavior: "steer"})`.
  - `stop` runs `abort({reason: USER_INTERRUPT_LABEL})`, then `waitForIdle()`, then `prompt(text)`.
  - The packet does not need the editor, so an open dialog does not block it.
  - omp runs the handler calls of one Session in one promise chain. A second packet waits until the `abort` and `waitForIdle` of a `stop` packet end, so the arrival order stays the same.
- **Rationale**: omp's own queue holds `queue` follow-ups until the turn ends. The Intake therefore needs no turn tracking and has no race between "idle" and "send" (FR-031). One `zmx send` per follow-up, in order, gives once-only, in-order delivery.
- **Alternatives**:
  - Typed text plus CR. It always steers during a turn and can submit early.
  - A collab guest. Too much machinery.
  - A new socket in omp. It adds a second channel to a live Session.

### D7. Follow-up delivery rules

- **Decision**: The Intake sends one Launch's follow-ups one at a time, in arrival order, and only while the Launch is `running` and its `agent_state` is set. omp sets the `cci-state` label from its TUI after init, and the reconcile loop copies it into `agent_state`. Before that, omp may not read the PTY input yet, and a sent packet can get lost. The change that sets `agent_state` for the first time starts the sender. The Intake sets a follow-up to `sending` before `zmx send`. A `zmx send` that exits 0 makes the follow-up `sent`. A failed send makes it `failed` with the reason, and the Intake does not retry. At startup, a `sending` row has an unknown result. It becomes `failed` with the reason `result unknown`, and the Intake does not send it again. The text limit is 64 KiB of UTF-8. A follow-up for a Launch that is not live (`queued`, `starting`, or `running`) is `refused`. A follow-up for a `queued` or `starting` Launch stays `pending` until the Launch runs and its `agent_state` is set. It becomes `refused` when the Launch becomes `failed`.
- **Rationale**: A retry after an unknown result can deliver twice. 64 KiB becomes about 87 KiB of base64url, which is below the Linux limit of 128 KiB for one argument.
- **Alternatives**: A temporary file plus `zmx write`. That is two steps and needs a cleanup.

### D8. Launch state from `zmx list`

- **Decision**: A loop runs every 10 s for each host that has a `queued`, `starting`, or `running` Launch. It runs `zmx list` once per host. A missing name makes the Launch `ended`. A failed list changes no `running` Launch, and no `starting` Launch inside its 45 s window (D5). The list also gives `cci-state` for `agent_state` and the count for host slots. After the list, the loop calls `startNext` for the host, so a `queued` Launch starts when a slot is free (D9). A failed list before a start makes the oldest `queued` Launch on that host `failed`, with a reason that names the host (spec edge case "Host unreachable"). A Linear Launch then gets its failure comment.
- **Rationale**: This matches the Emacs rule that a failed list must not change state (`claude-code-ide.el:1275-1310`). It meets FR-026 and the "within one check" rule of SC-003.
- **Alternatives**: Use the zmx exit of the attach process. The Intake never attaches, so there is none.

### D9. Host slots and the queue

- **Decision**: Before each start, the Intake counts the package Session names (prefix `cci-`) in a fresh `zmx list` of the host. It adds each `starting` Launch on the host that has no listed session yet, for example after a restart during its start. It starts the Launch only when the count is less than `max_sessions - 1`. The Intake starts Launches one at a time per host. Queued Launches start in creation order when the reconcile loop sees a free slot.
- **Rationale**: A fresh count includes Sessions that the user started by hand (FR-025, SC-006). One start at a time per host makes the count and the start atomic for the Intake.
- **Alternatives**: Count from the database. That misses Sessions that the Intake did not start.

### D10. Trigger identity and request keys

- **Decision**: The Trigger primary key is the stable identity:
  - `linear:history:<IssueHistory.id>` for a label event.
  - `linear:issue:<Issue.id>` for an issue that has the label with no history entry that added it (D14 creation Trigger).
  - `linear:comment:<Comment.id>` for a comment follow-up.
  - `api:<request key>` for a Launch request with a key.
  - `api:<new id>` for a Launch request without a key.
  - `api-input:<request key>` or `api-input:<new id>` for a follow-up request. The separate prefix keeps a follow-up key from matching a Launch key.
  A Launch has a unique `trigger_id`. The Trigger insert and the Launch insert run in one transaction before any action.
- **Rationale**: SQLite constraints enforce FR-023 and FR-024. A duplicate insert returns the existing Launch.
- **Alternatives**: An in-memory set, as in Symphony. It does not survive a restart.

### D11. Push adoption

- **Decision**: For each `[[emacs]]` entry in the configuration, the Intake runs `emacsclient --eval '(claude-code-ide-adopt-session HOST NAME)'` after a Launch becomes `running`. A local entry runs it on the Intake machine. A remote entry runs it through D2. `HOST` comes from the entry's host map, and nil means "local to that Emacs". The call has a 10 s timeout, the result is recorded, and a failure is not retried.
- **Rationale**: Each Emacs names hosts in its own way. The Intake host is "local" to an Emacs on the same machine, but it is a Configured host for an Emacs on another machine. The map lives in the Intake configuration (FR-022). The Intake checks `HOST` and `NAME` against the D2 host pattern and the zmx name pattern before it builds the Lisp form. This means a quote cannot reach the form.
- **Alternatives**: Push without a map. That fails as soon as Emacs and the Intake run on different machines.

### D12. Public adopt command

- **Decision**: Add `claude-code-ide-adopt-session (host name)` with an autoload cookie and no `interactive` form.
  - For a host that is not a Configured host or a name that fails `claude-code-ide-zmx--package-name-p`, it returns `refused` (FR-011). The first refusal of a `(host . name)` pair shows one `message` in Emacs that names the refused value and the Session name. A later refusal of the same pair shows nothing, because the Intake sends an event on each agent-state change. It does not signal an error: `emacsclient --eval` sends an error back to the caller, and Emacs would show nothing.
  - It skips a `(host . name)` pair that is already pending, live, or adopted.
  - Otherwise it adds the pair to `claude-code-ide--pending-adoptions` and schedules `claude-code-ide--adopt-spawned-session` with `run-at-time 0`. The adopt callback removes the pair.
  - It returns the symbol `adopting`, `skipped`, or `refused`.
- **Rationale**: `emacsclient` gets an answer at once and never waits on SSH. The pending set closes the race between two remote lists, so push and pull together adopt once (SC-007). `claude-code-ide-switch-on-spawn` applies unchanged (FR-010).
- **Alternatives**: A synchronous adopt with `accept-process-output`. It freezes Emacs for up to 30 s.

### D13. Pull path in Emacs

- **Decision**: Add the new file `claude-code-ide-intake.el` with three parts.
  - Options: `claude-code-ide-intake-url` (nil turns pull off), `claude-code-ide-intake-token-file`, and `claude-code-ide-intake-client` (the Intake's `[[emacs]]` name for this Emacs, default `(system-name)`).
  - The global minor mode `claude-code-ide-intake-mode`. It signals a `user-error` when the URL is nil.
  - On start and after each reconnect, the mode opens one stream request, then runs one list request. Thus no event that comes between the two requests is lost. Both use `curl -sN --fail --config -` and send the `Authorization` header on stdin, so `ps` never shows the token.
  - A process filter splits events on a blank line. Each `launch` event with state `running` calls `claude-code-ide-adopt-session` with the mapped host and name.
  - The sentinel reconnects after 1, 2, 4 … s, up to 60 s. The first event resets the delay.
- **Rationale**: This follows the existing process-and-sentinel pattern and adds no Elisp dependency. `curl` is an outside program like `ssh` and `zmx`. A missing `curl` gives a `user-error` when the mode starts (principle III). The Intake applies the host map from D11 to the stream when the request names the client, so the Emacs code has no map.
- **Alternatives**:
  - `url-retrieve` collects the whole body before its callback, so it cannot read a stream.
  - `make-network-process` needs hand-written HTTP.
  - WebSocket needs the optional `websocket` package and a channel in both directions that this feature does not use.

### D14. Linear label poll

- **Decision**: Every 30 s, look up the IDs of every label named `trigger_label`, then run one `issues` query: `updatedAt > cursor − 2 min`, the watched team keys, any of those label IDs, ordered by `updatedAt`, `first: 25`, and `history(first: 10)` on each issue. The Intake keeps no copy of the label IDs, so a new `trigger_label` or a new team label with that name applies on the next poll. Each history node whose `addedLabelIds` holds one of the label IDs and whose `createdAt` is newer than `cursor − 2 min` becomes a Trigger with the D10 identity. An older node is a past event: an earlier poll owned it, or it is from before the first run. A later edit to its issue must not launch it (T042 run, 2026-11-09). The Launch's `created_at` is the time of the label event, on Linear's clock. The gate result is the first match in this order:
  1. `source_off`: `sources.linear.enabled` is false. The Intake polls also when the source is off, so that it records these Triggers (FR-041).
  2. `untrusted`: `actorId` is null or not in the allow-list.
  3. `duplicate`: the issue already has a `queued`, `starting`, or `running` Launch (spec edge case "Same issue, label added again").
  4. `unmapped`: no project rule matches (D16).
  5. `accepted`.
  An `accepted` Trigger gets a `queued` Launch. Every other result gets a `refused` Launch with the gate result as its reason, so the refusal shows in the Launch list (FR-028, Story 2.2). The cursor moves to the largest `updatedAt` seen. It is stored in the same transaction as the Triggers and Launches.

  **Creation Trigger** (T022 history gap, user decision of 2026-11-08). Linear writes no history entry for a label that is set at creation or in the first minutes after it. A polled issue gets one extra Trigger `linear:issue:<Issue.id>` when all three conditions hold. First, the issue has the trigger label. Second, `issue.createdAt` is newer than `cursor − 15 min`. Third, its full history has no node whose `addedLabelIds` holds the label. The actor is `issue.creator.id`. The same gate applies. The 15 min bound keeps an old issue that was created with the label from launching when someone edits it later.
- **Rationale**: The poll needs only outgoing HTTPS, so it works behind NAT. The cursor is a timestamp, so a Mac that slept catches up on its next poll. The overlap plus D10 makes repeats harmless (FR-050, SC-002, SC-004).
- **Alternatives**:
  - Webhooks need a public receiver, which is a later feature.
  - Poll by label state, as Symphony does. That loses the actor.
- **Limit**: An issue with more than 10 history events between two polls can hide its label event. The Intake pages `history(after:)` while `pageInfo.hasNextPage` is true and every node it has is newer than `cursor − 2 min`. For an issue whose `createdAt` is newer than `cursor − 15 min`, it reads the full history, because the Creation Trigger needs it.

### D15. Linear comments

- **Decision**: In the same 30 s loop, run one root `comments` query with `createdAt > comment cursor − 2 min`. The query covers each issue whose newest Launch that the gate accepted is live (`queued`, `starting`, or `running`), `ended`, or `failed`. That Launch is the target of the issue's comments. When no issue has such a Launch, the comment cursor moves to the current time, so that a later Launch never gets comments from the gap. The Intake skips a comment that is older than its target Launch's `created_at`. That comment belongs to an earlier Launch (FR-054). A follow-up for a Launch that is not yet `running` waits as `pending` (D7). The Intake skips a comment whose ID is in its own `comments` table. It also skips a comment whose body does not start with `followups.prefix` (default `/omp`). A skipped comment gets no Trigger. The prefix rule stops a loop: the Agent posts its replies with the user's Linear identity, so an author check alone would pass them (clarification of 2026-11-08). Each other comment becomes a Trigger. Its gate result is `source_off` when the Linear source is off, `untrusted` when its author is not on the allow-list, and `accepted` otherwise. An `accepted` comment becomes a follow-up with the configured mode. The follow-up text is the body after the prefix and the spaces that follow it. An empty text gives a `refused` follow-up with the reason `empty text`. A comment for an `ended` or `failed` Launch gives a `refused` follow-up with the reason `launch is ended` or `launch is failed` (US4/AC3). Every comment that the Intake posts is first stored with a new UUID and state `pending`. The Intake sends it at once, and each tick sends the pending rows again, also after a failed poll. It is sent with `commentCreate(input: {id, issueId, body})`. A pending row is sent again at restart with the same ID.
- **Rationale**: With a personal key, the Intake's comments carry the user's own user ID, so the user ID cannot tell them apart. The stored UUID can. One comment per result meets FR-052. A Launch that the gate refuses as `untrusted`, `duplicate`, or `source_off` gets no comment, so an untrusted user cannot make the Intake post (clarification of 2026-11-08). [Inference] Linear refuses a second create with the same ID. The task list includes a check of this.
- **Alternatives**: A text marker in each comment. Anyone can copy a marker.

### D16. Project mapping and opening prompt

- **Decision**: Map an issue to a project in this order:
  1. A `[repo=NAME]` tag in the description (Cyrus syntax, `refs/cyrus/packages/edge-worker/src/RepositoryRouter.ts:487-503`, with escaped brackets accepted).
  2. An issue label in `[projects.NAME].linear_labels`.
  3. The Linear project in `linear_projects`.
  4. The team in `linear_teams`.
  The branch name is the issue identifier in lowercase, for example `eng-123`. The opening prompt has the title and link, then the description inside a block that names it as text from the issue author.
- **Rationale**: This is FR-051 and FR-053. The match order is Cyrus priorities 1 to 4.
- **Alternatives**: Let a model pick the repository. This goes against FR-040.

### D17. Credential and network

- **Decision**:
  - The Intake listens only on the addresses in `listen`, for example `127.0.0.1:7311` and the machine's private-network address.
  - Each request must send `Authorization: Bearer <token>`. The Intake compares it with `crypto.timingSafeEqual`.
  - The Intake reads the token file at each request, so a new token works at once. The Intake refuses to start when the file is readable by group or other users.
  - The Linear key comes from a second file with the same rule. The Intake sends it only to `https://api.linear.app/graphql`. The `CCI_LINEAR_URL` test endpoint applies only under `bun test` (`NODE_ENV=test`).
- **Rationale**: This covers FR-020 and the edge case "Launch credential leaked". It needs no restart and no extra code.
- **Alternatives**: mTLS or OAuth. Both are too much for one user on a private network.

### D18. Tests

- **Decision**:
  - **Intake**: `bun test`. A fake `run` records each argv and answers from a script. A local `Bun.serve` answers the Linear calls. Property tests use a seeded loop that prints its seed (global rules). They cover these invariants:
    - One Trigger delivered N times, with restarts at random points, gives one Launch (SC-002).
    - The live count on a host never goes over `max_sessions - 1` (SC-006).
    - Follow-ups go out in arrival order, and each goes out at most once (FR-031).
    - Each Emacs adopts each Launch once with push and pull both on (SC-007).
  - **omp**: Tests next to `test/session/sibling-spawn.test.ts` for `spawnSession` and `launch-session`. Tests next to `test/modes/composer-editor-handoff.test.ts` for the `send` packet. Then run `bun run check` and the full suite.
  - **Package**: ERT tests in `claude-code-ide-tests.el` that reuse `claude-code-ide-tests--with-spawn-adoption` and `--with-remote-targets`. The tests mock `make-process` for curl. Then run `./scripts/compile-and-test.sh`.
- **Rationale**: SC-008, and constitution principle II.

### D19. Running the Intake

- **Decision**: The user runs `bun run src/main.ts` from a shell or through any process manager. The feature ships no launchd or systemd unit.
- **Rationale**: One user and one machine. A unit file is easy to add when the user wants the Intake to start at login.
