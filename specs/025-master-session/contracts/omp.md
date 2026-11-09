# Contract: omp changes

These are changes to `specs/024-session-launch-intake/contracts/omp-launch-session.md` and `specs/021-spawn-session/contracts/zmx-labels.md`.

## `omp launch-session --cwd`

| Case | 024 | 025 |
|---|---|---|
| `--branch` given, `--cwd` not a Git checkout | error `--cwd is not a Git checkout` | same |
| No `--branch`, `--cwd` not a Git checkout | error | accepted. The Session runs in `--cwd`. |
| `--cwd` missing, or not absolute | error | same |

The Intake passes these labels with `--label`. omp needs no change for them:

- `cci-role=master` on the master Launch.
- `cci-origin=master` on each Launch with origin `master`.

## Label `cci-turn`

- **Writer**: the omp process that has state publishing on (`OMP_PUBLISH_STATE` or `OMP_SPAWN_PARENT`, together with `ZMX_SESSION`).
- **When**: on each `agent_end`. It goes in the same `zmx set` call as `cci-state=idle` and the empty `cci-work`.
- **Value**: base64url of the decimal count of `agent_end` events in this omp process. The first value is `1`.
- **Missing**: before the first `agent_end`, and in older omp builds. Readers then treat the turn as unknown.
- A test drives two `agent_end` events. It checks that each `zmx set` argument list has `cci-state` and `cci-turn` together, and that the turn values are `1`, then `2`.

## CHANGELOG

One entry under the coding-agent `Unreleased` section. It names the `cci-turn` label and the `--cwd` rule.
