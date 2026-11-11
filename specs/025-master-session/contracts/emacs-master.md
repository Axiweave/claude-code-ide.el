# Contract: Emacs Master Session

## Switch rule (FR-020, FR-021, FR-022)

`claude-code-ide--spawn-switch-p ENTRY HOST NAME` is the one place for the Master Session rules. `claude-code-ide--attach-spawned-entry` calls it in place of the bare `claude-code-ide-switch-on-spawn` test. The rules apply in this order:

| # | Condition | Result |
|---|---|---|
| 1 | `ENTRY` has label `cci-origin` with value `master`, or label `cci-parent` names a live Master Session on `HOST` | nil: no switch, no window change |
| 2 | `(HOST . NAME)` is equal to `claude-code-ide--master-open-pending` | t, and the variable becomes nil |
| 3 | otherwise | `claude-code-ide-switch-on-spawn` |

Label values are base64url. The rule decodes them before it compares.

ERT: the rule table is a property over all combinations of the `cci-origin` label (none, `master`, other), the `cci-parent` label (none, a live Master Session, a live plain Session), pending (none, the same pair, another pair), and the option (t, nil). The test runs the combinations for a local and for a remote entry, and checks `switched` against the table.

## Master mark (FR-004, FR-005)

- At attach, a zmx entry with `cci-role` = `master` sets the Session's `master` slot. Names and directories never set it.
- The Session manager draws the rows that have the `master` slot under one heading, `Master`, before all Project groups. These rows are in no Project group.
- A disconnected master row keeps the slot after an Emacs restart, through the item serialization.

## Command `claude-code-ide-master` (FR-001, FR-002, FR-009)

It is interactive, with no arguments.

Both requests carry `?client=` with the URL-encoded value of `claude-code-ide-intake-client`, as pull mode does (`claude-code-ide-intake.el:160-167`): `POST /v1/master?client=…` and `GET /v1/launches/{id}?client=…`. Without it, the Intake leaves out `emacs_host`, and the command cannot build the pair.

| Case | Behavior |
|---|---|
| `claude-code-ide-intake-url` is nil, `(executable-find "curl")` is nil, or `claude-code-ide-intake-token-file` is not readable | `user-error` that names the option or `curl`. No process starts. |
| `POST /v1/master` cannot connect, or gets 5xx | one `message`: `Intake at <url> is not reachable` (or the HTTP status). It starts nothing and attaches nothing. |
| 4xx (404 without `[master]`, 400 `unknown client`) | one `message` with the Intake's `error` text. No poll and no adopt. |
| 200 or 202, the Launch is `running`, and the Session is live in Emacs | shows the Session in the selected window |
| 200 or 202, any other case | polls `GET /v1/launches/{id}` every 1 s, for up to 45 s. The Intake sets `name` and `running` in one change and pushes its own adopt call at that moment, so the pending pair cannot exist before `running`. At `running`, it sets `claude-code-ide--master-open-pending` to `(EMACS-HOST . NAME)`, where EMACS-HOST is the Launch's `emacs_host` (`:null` becomes nil), never its `host` key. Then: (1) the Session is live: show it and clear the pair. (2) The pair is in `claude-code-ide--pending-adoptions`: do nothing more, because the switch is decided at attach time and rule 2 applies. (3) Otherwise: remove the pair from `claude-code-ide--adopted-sessions`, so a disconnected master attaches again, and adopt it through `claude-code-ide-intake--adopt`. Rule 2 shows it. A Launch with no `emacs_host` gives one message that no Emacs target maps its host. If 45 s pass, or the state becomes `failed`, it clears the pending pair and shows one message with the state and reason. |

## Command `claude-code-ide-intake-confirm` (FR-051, FR-052)

It is interactive, with no arguments. When `claude-code-ide-intake-url` or `(executable-find "curl")` is nil, or `claude-code-ide-intake-token-file` is not readable, it gives a `user-error` and starts no process.

1. Get `GET /v1/launches?state=held`. If the list is empty, show one message.
2. If several Launches are `held`, choose one with `completing-read`. Each candidate shows `<id> <project>@<host>`.
3. Ask `yes-or-no-p` with the project, the host, and the full prompt. The question uses only the minibuffer, so the selected window does not change.
4. Post `confirm` for yes and `decline` for no. Show the new state.

`claude-code-ide-intake-mode`: a `launch` event with state `held` shows one message: `Launch <id> for <project>@<host> waits: M-x claude-code-ide-intake-confirm`.

## `claude-code-ide-intake--curl`

It gets optional `METHOD` and `BODY` arguments. The method, the `Content-Type` header, and the body go through curl's stdin configuration, so neither the token nor the body is in a process argument. The callback gets the HTTP status and the body text. The existing GET callers keep their current behavior.
