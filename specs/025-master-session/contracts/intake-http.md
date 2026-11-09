# Contract: Intake HTTP changes

This is a change to `specs/024-session-launch-intake/contracts/intake-http.md`. Auth, error shape, and the routes not named here stay the same.

## The Launch object

It gets two new fields:

| Field | Type | Value |
|---|---|---|
| `kind` | string | `session` or `master` |
| `prompt` | string | The opening prompt. `claude-code-ide-intake-confirm` shows it in the question (FR-051). |

`state` can now also be `held`. `origin.source` can now also be `master`.

## `POST /v1/master`

It needs no body. It takes the same optional `?client=<name>` query as the other Launch routes. With a known `client`, the answer has `emacs_host` (`serialize(l, client)`, `http.ts:35-36`). The route answers through `reply(…, client)`, as `POST /v1/launches` does (`http.ts:54`, `:102`).

| Status | When | Body |
|---|---|---|
| 200 | A `master` Launch is `queued`, `starting`, or `running` | that Launch |
| 202 | No live master. The Intake records a new `master` Launch in `queued` and starts it at once (no slot). | the new Launch |
| 404 | The configuration has no `[master]` table | `{ "error": "no [master] in config" }` |
| 400 | `?client=` names no `[[emacs]]` entry. The Intake checks this before it records anything, as `/v1/events` does (`http.ts:108-110`). | `{ "error": "unknown client: <name>" }` |

The check and the insert are one transaction, so two calls at the same time give one master (FR-002, FR-008).

## Master token

`[master].token_file` holds a second bearer token. The Intake checks a request against both tokens. A request with the master token has the origin `master`. A request with the shared token never has it. Every route that accepts the shared token also accepts the master token, except `confirm` and `decline` (403).

A raw call with the shared token gets no master origin. The master can make such a call, because it has the full tool set and can read the shared token file (research D4, Known limit).

## `POST /v1/launches` (changed)

New body field:

| Field | Type | Rule |
|---|---|---|
| `main_checkout` | `true` or absent | Allowed only with the master token. |

New 400 cases. In each case the Intake records nothing.

| Case | `error` |
|---|---|
| Master token, with neither `worktree` nor `main_checkout: true` | `master launch needs worktree or main_checkout` |
| Master token, with both | `worktree and main_checkout are exclusive` |
| Shared token, with `main_checkout` | `main_checkout needs the master token` |

With the master token, the Trigger has `source = master`, and its ID is `master:<key>` when `key` is given, otherwise `master:<launch id>`. The same key gives the same Launch, as in 024. `startLoop` adds `--label cci-origin=master`.

With `[master].confirm = true`, an accepted request with the master token gives 202 and a Launch in `held`.

## `GET /v1/projects` (new)

| Status | Body |
|---|---|
| 200 | `{ "projects": [ { "name", "path", "hosts", "default_host", "description" } ] }` |

The list is in config order. `description` is `null` when the project has none.

## `GET /v1/launches/{id}/output?lines=N` (new)

| Status | When | Body |
|---|---|---|
| 200 | The Launch is `running` | `{ "text": "<last N lines of zmx history>" }` |
| 400 | `lines` is not an integer from 1 to 2000 | `{ "error" }` |
| 404 | Unknown Launch | `{ "error" }` |
| 409 | The Launch is not `running` | `{ "error": "launch is <state>" }` |
| 502 | `zmx history` exited with a code other than 0 | `{ "error": "zmx history failed: <code>" }` |

The default of `lines` is 200. The Intake runs `zmx history <name>` through `run(host, …)`, so local and remote hosts behave the same (FR-031).

## `POST /v1/launches/{id}/confirm` and `/decline` (new)

| Status | When | Body |
|---|---|---|
| 200 | The Launch was `held`. `confirm` sets it to `queued`. `decline` sets it to `refused`, with `reason = "declined by user"`. | the Launch |
| 404 | Unknown Launch | `{ "error" }` |
| 409 | The Launch is not `held` | `{ "error": "launch is <state>" }` |
| 403 | The request uses the master token | `{ "error": "the master cannot confirm or decline" }` |

## `GET /v1/launches`

The existing `state` filter takes `held`. No other change. The list covers all origins (Q3, FR-030).

## SSE `GET /v1/events`

The existing `launch` event carries the new fields. A change to `held` emits an event, as every Launch change does.
