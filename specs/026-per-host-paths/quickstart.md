# Quickstart: Per-Host Project Paths

These scenarios prove the feature from end to end. The rules are in `contracts/intake-config.md` and `contracts/intake-http.md`.

## Prerequisites

- The Intake at `~/agents/cci-intake`, with the 025 `[master]` setup and `cci` on `PATH`.
- `ssh v12dev` works without a password. omp is at `/home/yufu/.bun/bin/omp`, and zmx is on `PATH` on v12dev.
- A scratch Git repo on each host: `/private/tmp/cci-026` on the MacBook and `/home/yufu/tmp/cci-026` on v12dev. Each repo needs one commit.
- Emacs with `claude-code-ide-intake-url` and `claude-code-ide-intake-client` set (025 quickstart).

Add this project to `~/.config/cci-intake/config.toml`, and restart the Intake:

```toml
[projects.p026]
hosts = ["local", "v12dev"]
default_host = "local"
path = { local = "/private/tmp/cci-026", v12dev = "/home/yufu/tmp/cci-026" }
omp = { local = ["/Users/fuyu0425/.bun/bin/omp"], v12dev = ["/home/yufu/.bun/bin/omp"] }
launch_session = { local = ["/Users/fuyu0425/.bun/bin/omp", "launch-session"], v12dev = ["/home/yufu/.bun/bin/omp", "launch-session"] }
```

## Automated

1. In the Intake repository, run `bun test`. Everything passes, and the seeded property test prints its seed.
2. In the package repository, run `./scripts/compile-and-test.sh`. There are 0 unexpected results.

## Live scenarios

1. **Project list (US3, FR-007)**: Run `cci projects`. For `p026`, `paths` shows `local` → `/private/tmp/cci-026` and `v12dev` → `/home/yufu/tmp/cci-026`.
2. **Default host (US1/AC2)**: Run `echo "Create LOCAL.md with the word one" | cci launch p026`. Then `cci show <id>` shows the `host` `local` and a `dir` under a worktree of `/private/tmp/cci-026`. Emacs attaches the Worker Session.
3. **Named remote host (US1/AC1, US2/AC1)**: Run `echo "Create REMOTE.md with the word two" | cci launch p026 --host v12dev`. Then `cci show <id>` shows the `host` `v12dev` and a worktree of `/home/yufu/tmp/cci-026`. The Session runs the v12dev omp. Emacs attaches it over TRAMP.
4. **Main checkout (US1/AC3)**: Run `echo "Print the branch" | cci launch p026 --main`. The Session `dir` is `/private/tmp/cci-026` itself.
5. **Through the Master Session**: In the master, ask "In p026 on v12dev, list the files". The master starts the Launch on v12dev and reports the Launch.
6. **`default` entry (FR-003)**: Change `launch_session` to `{ default = ["omp", "launch-session"] }`, and set `omp` to one value that works on both hosts. Restart the Intake. Scenario 3 still starts.
7. **Refusals (FR-003, SC-002)**: Make each change below, then restart the Intake. Each start fails with the message from `contracts/intake-config.md`:
   - Remove the `v12dev` entry from `path`, and give no `default` entry.
   - Add `nope = "/x"` to `path`.
   - Add `[hosts.default]`.
8. **Single value unchanged (FR-008, SC-003)**: The 025 projects with one `path` string still start Launches in the same directory.

## Cleanup

Stop the test Launches (`cci stop <id>`). Remove `[projects.p026]` from the configuration. Delete both scratch repos and their worktrees.
