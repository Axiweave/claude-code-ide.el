# Data Model: Per-Host Project Paths

## Intake configuration (changed)

| Key | Type | Rule |
|---|---|---|
| `[hosts.<name>]` | table | The name `default` is refused (research D3). The other rules are unchanged. |
| `[projects.<key>].path` | string, or table of strings keyed by host | A table key is a project host or `default`. Each project host needs its own entry or a `default` entry (D4). |
| `[projects.<key>].omp` | string array, or table of string arrays keyed by host | Each array is checked as today: not empty, and the basename of element 0 is `omp`. The table rules are the same as for `path`. |
| `[projects.<key>].launch_session` | string array, or table of string arrays keyed by host | Each array must not be empty. The table rules are the same as for `path`. |
| `[master]` | table | No change. One `path`, one `omp`, one `launch_session` (D8). |

Example:

```toml
[projects.app]
hosts = ["local", "v12dev"]
default_host = "local"
path = { local = "/Users/me/src/app", v12dev = "/home/yufu/src/app" }
omp = { local = ["/Users/me/.bun/bin/omp"], v12dev = ["/home/yufu/.bun/bin/omp"] }
launch_session = { default = ["omp", "launch-session"] }
```

## Project (in memory, after load)

| Field | Type | Note |
|---|---|---|
| `hosts` | string[] | Unchanged. The order comes from the configuration. |
| `default_host` | string | Unchanged. |
| `on` | `Record<host, HostRun>` | New. There is exactly one entry for each host in `hosts`, and no `default` key. |
| `path`, `omp`, `launch_session` | — | Removed. They are now in `on[host]`. |
| `description`, `linear_*` | — | Unchanged. |

`HostRun = { path: string; omp: string[]; launch_session: string[] }`. `MasterConf` has the same three fields, so the Launch start reads `HostRun` from either the master or `project.on[host]`.

## Launch (SQLite, unchanged)

`dir` holds `on[host].path` from the time when the Intake recorded the Launch (D5). There is no schema change.
