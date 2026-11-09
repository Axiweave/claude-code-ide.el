# Contract: Intake configuration, per-host project values

This contract changes the project keys from 024 `contracts/intake-config.md`. Every other key keeps its rules. See `data-model.md` for the types and research D1–D4 for the reasons.

## Value forms

| Key | One value for all hosts | A value for each host |
|---|---|---|
| `path` | `"/src/app"` | `{ local = "/Users/me/src/app", v12dev = "/home/yufu/src/app" }` |
| `omp` | `["/path/omp"]` | `{ local = ["/Users/me/.bun/bin/omp"], v12dev = ["/home/yufu/.bun/bin/omp"] }` |
| `launch_session` | `["omp", "launch-session"]` | `{ default = ["omp", "launch-session"], v12dev = ["/home/yufu/.bun/bin/omp", "launch-session"] }` |

A table can mix host entries and one `default` entry. The value of each project host is its own entry when there is one. Otherwise, it is the `default` entry.

## Refusals at start

The Intake writes one line to stderr and exits with a non-zero code, as for every other configuration error. `<p>` is the project key.

| Case | Message key | Message text |
|---|---|---|
| A `[hosts]` entry named `default` | `hosts.default` | `"default" is reserved for the fallback entry of a per-host table` |
| A table key that is not a project host and is not `default` | `projects.<p>.<key>.<host>` | `"<host>" is not in projects.<p>.hosts` |
| A project host with no entry and no `default` entry | `projects.<p>.<key>` | `no value for host "<host>" and no default entry` |
| A `path` entry that is not a string | `projects.<p>.path.<entry>` | `expected a string` |
| An `omp` entry that is empty, or whose program is not omp | `projects.<p>.omp.<entry>` | the message of today's `omp` check |
| A `launch_session` entry that is empty | `projects.<p>.launch_session.<entry>` | `must not be empty` |
| A value that is neither the single form nor a table | `projects.<p>.<key>` | the message of today's type check (`expected a string` or `expected an array of strings`) |

`<entry>` is the table key: a host name or `default`. The Intake also checks a `default` entry that no host uses.

## Use

| Launch source | Path | Commands |
|---|---|---|
| `POST /v1/launches`, `cci launch` | `on[host].path`, where `host` is the request host or `default_host` | `on[host].launch_session`, `on[host].omp` |
| Linear | `on[default_host].path` | `on[default_host]` commands |
| Master (`POST /v1/master`) | `[master].path` | `[master]` commands |

The Intake records the path in the Launch row when it records the Launch. It reads the commands from the configuration when the Launch starts.
