# Contract: `/fork spawn`

## Syntax

```text
/fork spawn
```

- `spawn` is a `/fork` subcommand, next to `pane`, `window`, and `tab`. It matches without regard to case, as the other subcommands do.
- Extra text, such as `/fork spawn foo`, shows `Usage: /fork [pane|window|tab|spawn]` and does nothing.
- The subcommand list shows `spawn` with the description "Open the fork as a sibling session in its own zmx session".

## Steps (`InteractiveMode.handleForkSpawnCommand`)

1. When `session.isStreaming` is true, ask "Fork while a response is running?" with the `/fork pane` body text. On "no", stop with no message.
2. Call `#spawnSibling({ mode: "fork" }, false)`. This method does these steps:
   1. Refuse when `ZMX_SESSION` is unset: "spawn needs a zmx session".
   2. Build the launch. Refuse on an API-key override with `FORK_API_KEY_REFUSAL`.
   3. Flush A. Refuse when there is no saved session file: "spawn cannot fork: this session has no saved conversation yet".
   4. Run `createSibling` with `--fork <file>` and `cci-parent`, and with no start file.
   5. Run `writeSpawnAnnouncement(name)` and `showStatus("Spawned <name>")`.
3. On any thrown error, run `showError("Spawn failed: <message>")`. Nothing else changes.

## Guarantees

- No `session.prompt`, `followUp`, or model request starts in A.
- A gets no conversation entry.
- The spawn window, `#spawnRunUsed`, and the active tools in A do not change.
- The `spawn.confirm` question is never asked.
- B gets no `OMP_SPAWN_START_FILE`, so it waits for input.

## Unchanged contracts

The zmx labels, the OSC announcement, Emacs attach, and `/despawn` follow `specs/021-spawn-session/contracts/`.
