# Contract: Notices

A Notice is a `queue` packet from the Intake to the Master Session. It uses the 024 packet `pi:send;queue.<base64url>` (`specs/024-session-launch-intake/contracts/omp-send-packet.md`).

## Text

It is exactly one line, with no newline at the end:

```text
[intake notice] launch <id> project=<project> host=<host> state=<state> turn=<turn>
```

| Field | Source | Values |
|---|---|---|
| `<id>` | Launch ID made by the Intake | `[a-z0-9]+` |
| `<project>` | project key in the configuration | config key |
| `<host>` | host key in the configuration | config key |
| `<state>` | Notice event | `idle`, `ended`, `failed`, `refused` |
| `<turn>` | `cci-turn` for `idle`, else `-` | decimal or `-` |

The text holds no `reason` and no worker output (FR-043). A test checks that each field matches its pattern for generated Launches, and that no other text is present.

## When the Intake writes a Notice

See `data-model.md`, "Notice events". The Intake writes Notices only for Launches with origin `master` (FR-032).

## Delivery rules

1. The Intake sends only to the `master` Launch that is `running`, and only when its `agent_state` is set. If no master is ready, Notices wait (FR-045).
2. The Intake keeps at most one waiting Notice for each worker, with the newest text (FR-045).
3. The Notices go out oldest first. They use the master's per-Launch chain, the same chain as follow-ups to the master.
4. After `zmx send` exits 0, the row is `sent`. A later restart sends it never again (FR-044).
5. If `zmx send` fails, the row goes back to `pending`. The next reconcile tick sends it again. At start, `recover()` sets each row that a crash left in `sending` back to `pending` (FR-045). A duplicate Notice is the accepted cost.
6. omp delivers a `queue` packet after the master's current turn (FR-041), with `runCommands: false`. A Notice cannot start a Launch, because the Intake never starts a Launch from a Notice (FR-042).
