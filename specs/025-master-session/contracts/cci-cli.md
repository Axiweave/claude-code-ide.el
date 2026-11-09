# Contract: `cci` command line

`cci` is `src/cli.ts` in the Intake repository, linked through the `bin` entry of `package.json`. The Master Session calls it through `bash`. It reads the Intake configuration (`--config`, or the default path) for `listen` and `[master].token_file`, and it sends only the master token. So every call has the origin `master` (research D4). Each subcommand makes one HTTP call. The output is JSON on stdout. An HTTP answer that is not 2xx gives exit 1 and prints the `error` text on stderr. A connection failure gives exit 2 and prints `Intake at <url> is not reachable` on stderr. Without `[master].token_file`, `cci` exits 2 with `no [master] in config`.

| Subcommand | HTTP call | Notes |
|---|---|---|
| `cci projects` | `GET /v1/projects` | |
| `cci launch <project> [--host H] [--main] [--branch B] [--key K]` | `POST /v1/launches` | The prompt comes on stdin. The body has `worktree: {branch?}` unless `--main` is given. With `--main`, it has `main_checkout: true`. |
| `cci list [--state S]...` | `GET /v1/launches` | |
| `cci show <id>` | `GET /v1/launches/{id}` | |
| `cci output <id> [--lines N]` | `GET /v1/launches/{id}/output` | It prints the text between the lines `----- BEGIN UNTRUSTED OUTPUT <id> -----` and `----- END UNTRUSTED OUTPUT <id> -----`, not as JSON. |
| `cci send <id> [--mode queue\|guide\|stop]` | `POST /v1/launches/{id}/input` | The text comes on stdin. |
| `cci stop <id>` | `POST /v1/launches/{id}/stop` | |

The token is never in a process argument, the output, or an error text.
