# Research: Per-Host Project Paths

## D1. One key, two value forms

- **Decision**: `path` takes a string or a table of strings keyed by host. `omp` and `launch_session` each take an array of strings, or a table of such arrays keyed by host. A table can have a `default` entry.
- **Rationale**: This is the clarified syntax. It matches the existing `[[emacs]] hosts = { local = "", v12dev = "v12dev" }` form. A TOML string or array can never be mistaken for a table, so the form is clear from the value type.
- **Alternatives considered**: a sub-table for each host (`[projects.app.on.v12dev]`), and new plural keys (`paths`, `omps`). The user chose the same key with a table.

## D2. Resolve at load into one record for each host

- **Decision**: `loadConfig` turns the three keys into `Project.on: Record<host, { path, omp, launch_session }>`, with one entry for each project host. `Project.path`, `Project.omp`, and `Project.launch_session` are removed.
- **Rationale**: The checks for a missing host, an extra host, and a bad command then happen once, at start (FR-003, FR-004). The runtime never handles the two forms or the `default` entry. The `[master]` table already has `path`, `omp`, and `launch_session`. So the Launch start reads one shape: `isMaster ? config.master : project.on[host]`.
- **Alternatives considered**: three separate maps (`path: Record<host, string>` and so on). That gives three lookups, and the master and the projects keep different shapes. Another option was to keep the raw value and resolve at each use. Then every caller must handle `default`, and a bad host shows up only at Launch time.

## D3. `default` is a reserved name

- **Decision**: The Intake refuses a `[hosts]` entry named `default` with `hosts.default: "default" is reserved for the fallback entry of a per-host table`. In a per-host table, the key `default` always means the fallback.
- **Rationale**: Without this rule, `path = { default = "…" }` would be unclear for a host that is really named `default`. `HOST_RE` accepts `default` today.
- **Alternatives considered**: a different fallback key such as `"*"`. That is harder to type in TOML, because it needs quotes, and the user chose `default`.

## D4. The rules for a table

- **Decision**: For each key that has a table form, in this order:
  1. Each table key that is not `default` must be one of the project hosts. Otherwise the Intake refuses with `<key>.<host>: "<host>" is not in projects.<name>.hosts`.
  2. Each project host takes its own entry, or else the `default` entry. When neither exists, the Intake refuses with `<key>: no value for host "<host>" and no default entry`.
  3. Each value gets today's check: `path` must be a string. `omp` must pass `ompArgv`. `launch_session` must be a non-empty array of strings. The error key ends with the table key, for example `projects.api.omp.v12dev` or `projects.api.omp.default`.
- **Rationale**: Each message names the project, the key, and the host (FR-003, SC-002). Rule 3 also checks a `default` entry that no host uses. So a broken entry fails at start, not after a later change to `hosts`.
- **Alternatives considered**: ignore an unused `default` entry without a check. That hides a typo until a host needs the entry.

## D5. The Launch keeps its path

- **Decision**: No change. `requestLaunch` writes `dir` into the Launch row when it records the Launch. The start reads `launch.dir`. The commands come from the current configuration at start, as today.
- **Rationale**: The existing behavior already satisfies FR-006. The Intake reads its configuration only at process start, so a recorded Launch and a later configuration can differ only across an Intake restart. That case already keeps the recorded `dir`.

## D6. Linear uses the default host

- **Decision**: `linear.ts` sets `dir` from `project.on[project.default_host].path`.
- **Rationale**: A Linear Launch always uses `default_host` today, so it uses that host's path (spec edge case).

## D7. `GET /v1/projects` shows `paths`

- **Decision**: Each project object replaces `path` (a string) with `paths`, an object that maps each project host to its path, in `hosts` order. The answer always uses the object form, also when the configuration gives one string.
- **Rationale**: FR-007 and SC-004. The master reads one shape. A new name makes the break clear, so an old reader of the `path` string gets no value instead of the wrong type. `cci projects` prints the answer unchanged. The user's `AGENTS.md` does not read `path`.
- **Alternatives considered**: keep the name `path` with two possible types. This gives a reader two types for one field.

## D8. The master stays the same

- **Decision**: The `[master]` table keeps one `path`, one `omp`, and one `launch_session`, with no table form.
- **Rationale**: The master always runs on `local` (spec Assumptions).
