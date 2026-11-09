# Contract: Intake HTTP interface

The base URL is one of the `listen` addresses, for example `http://127.0.0.1:7311`. Every request must send `Authorization: Bearer <token>`. A missing or wrong token gets `401` with an empty body, and the Intake records nothing (FR-020). Bodies are JSON in UTF-8.

## Launch object

```json
{
  "id": "k3v9x0q2m1a8b7c4",
  "origin": {"source": "linear", "link": "https://linear.app/acme/issue/ENG-123", "actor": "usr_…"},
  "project": "api",
  "host": "v12dev",
  "emacs_host": "v12dev",
  "name": "cci-omp-api-x1y2z3",
  "dir": "/home/me/src/api/.worktrees/eng-123",
  "branch": "eng-123",
  "state": "running",
  "agent_state": "working",
  "reason": null,
  "created_at": "2026-11-08T10:00:00Z",
  "updated_at": "2026-11-08T10:00:07Z"
}
```

- `emacs_host` is present only when the request names a client with `?client=NAME`. It is the host string that this Emacs uses for the Launch's host, or `null` for a host that is local to that Emacs (research D11). A Launch whose host the client map does not name has no `emacs_host` key, and that Emacs ignores it.
- `name` and `branch` are `null` before the Launch starts. Before the start, `dir` holds the repository path. After the start, it holds the worktree path from `launch-session`.
- `project`, `host`, and `dir` are `null` for a `refused` Launch whose issue matches no project rule, whatever its gate result.
- A `refused` Launch has a `reason` that starts with its gate result: `source_off`, `untrusted`, `duplicate`, or `unmapped`.
- A `failed` Launch has a `reason` that says why. A `starting` Launch has a `reason` while it waits for its label after a `launch-session` result that was not clear (research D5). The Intake clears it when the Launch becomes `running`. Any other Launch has `reason` `null`.

## `POST /v1/launches`

Request:

```json
{"project": "api", "prompt": "Fix the flaky login test", "host": "v12dev",
 "worktree": {"branch": "fix-login"}, "key": "ci-run-8812"}
```

- `project` and `prompt` are required. `host`, `worktree`, and `key` are optional.
- Without `host`, the Launch uses the project's `default_host`.
- Without `worktree`, the Session runs in the project's `path` (FR-021).
- `worktree.branch` is optional. Without it, the Intake uses `launch-<id>`.

Responses:

| Status | When | Body |
|---|---|---|
| `202` | A new Launch is recorded. | Launch object (`queued`). |
| `200` | `key` matches an earlier request. | The existing Launch object. |
| `400` | Unknown project, host not in the project's `hosts`, empty prompt, or a malformed body. | `{"error": "<reason>"}` |
| `409` | The API source is off (FR-041). The Intake records the Trigger and a `refused` Launch. | `{"error": "source api is off"}` |

## `GET /v1/launches`

Query: `state` (repeatable), `client`. The response is `{"launches": [Launch…]}`, newest first. One call gives the full current state (FR-028).

## `GET /v1/launches/{id}`

`200` with a Launch object plus a `followups` array, or `404`. Only this route adds `followups`.

```json
"followups": [{"id": "p2r8…", "state": "sent", "reason": null},
              {"id": "x9a1…", "state": "refused", "reason": "launch is ended"}]
```

- The array is in arrival order. It is empty when the Launch has no follow-ups.
- `state` is `pending`, `sending`, `sent`, `failed`, or `refused`. `sent` means that `zmx send` handed the text to the Session. It does not mean that the Agent read it.
- `reason` is set for `failed` and `refused`, for example `result unknown` after a restart during a send.

## `POST /v1/launches/{id}/stop`

The Intake runs `zmx kill NAME` on the Launch's host, then runs `zmx list` to check that the name is gone. It does not touch the worktree or the branch (FR-029).

| Status | When |
|---|---|
| `200` | The name is gone. The body is the Launch object (`ended`). |
| `404` | No Launch has this ID. The body is `{"error": "no such launch"}`. |
| `409` | The Launch is not `running`. |
| `502` | The kill or the list check failed. The body has `{"error"}`, and the state does not change. |

## `POST /v1/launches/{id}/input`

Request: `{"text": "Also update the README", "mode": "guide", "key": "optional"}`. `mode` is optional, and its default is `followups.mode` from the configuration.

A follow-up `key` has its own namespace. The same string as a Launch `key` gives a separate record. A repeated follow-up `key` returns the first follow-up with `200`.

| Status | When | Body |
|---|---|---|
| `202` | The follow-up is recorded and queued for sending. The Intake sends a follow-up only when its Launch is `running` and its `agent_state` is set. Until then, the follow-up stays `pending`. | `{"id", "state": "pending"}` |
| `400` | `text` is empty or only white space, `mode` is not known, or the body is malformed. The Intake records nothing. | `{"error"}` |
| `404` | No Launch has this ID. The Intake records nothing. | `{"error": "no such launch"}` |
| `409` | The API source is off (FR-041). The Intake records the Trigger with gate `source_off` and no follow-up. | `{"error": "source api is off"}` |
| `409` | The Launch is not live (`queued`, `starting`, or `running`). The Intake records the follow-up as `refused`. | `{"error"}` |
| `413` | `text` is over 64 KiB. The Intake records the follow-up as `refused` with an empty `text`. | `{"error"}` |

## `GET /v1/events`

Query: `client` (optional, as for the list). A `client` that names no `[[emacs]]` entry gets `400` with `{"error": "unknown client: NAME"}`. Otherwise the response is `text/event-stream`. The Intake sends one event per Launch change:

```text
event: launch
data: {Launch object on one line}

```

The Intake sends a `: ping` comment every 30 s. The stream has no replay and no `id:` field. A client that reconnects calls `GET /v1/launches` once to catch up (FR-028).
