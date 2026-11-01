# Research: `/fork spawn`

## D1. Reuse the `/spawn` creation steps through one extracted method

- **Decision**: Split `#handleSpawnRequest` (`interactive-mode.ts` ~8645-8759) into two parts:
  - **Tool part.** It keeps the `#spawnRunUsed` guard and `#endSpawnWindow()`. Then it calls `#spawnSibling(request, cfgSpawnConfirm.get(this.settings))`.
  - **`#spawnSibling(request, confirm)`.** It holds every step after the window closes: the zmx check, `zmxSessionExecutable`, `buildForkChildLaunch`, the fork flush, the confirmation when `confirm` is true, worktree creation, `createSibling`, and the announcement.

  `/fork spawn` calls `#spawnSibling({ mode: "fork" }, false)`.
- **Rationale**: Fork mode already does the work that the spec asks for:
  - it flushes A, refuses when A has no saved conversation, and adds `--fork <file>`;
  - it sends no start file, so B waits;
  - it uses A's own zmx `cmd=` executable (FR-011 of spec 021), sets the parent link, and announces.

  One path keeps `/fork spawn` and the fork mode of `/spawn` the same (FR-002, FR-005).
- **Alternatives**:
  - **Call `#handleSpawnRequest` directly.** It would close an open `/spawn` window, use up that run's spawn slot, and ask `spawn.confirm`. Each of these breaks the spec (edge case "A `/spawn` window is open", and the `spawn.confirm` assumption).
  - **Copy the fork steps into a new method.** That gives two copies of the zmx and refusal logic, which drift apart.

## D2. A separate context method, not a fourth `/fork` placement

- **Decision**: Add `handleForkSpawnCommand(): Promise<void>` to `InteractiveModeContext` (`modes/types.ts`) and to `InteractiveMode`. The `/fork` slash command sends `spawn` there.
- **Rationale**: `handleForkCommand(placement)` passes `"pane" | "window"` to the terminal-launch code (`getTerminalLaunchPlacement`, `createDefaultTerminalLaunchRequest`). A Sibling Session is not a terminal placement, and the spawn state is in `InteractiveMode`, not in `CommandController`.
- **Alternatives**: Widen the placement type to `"spawn"`. Every terminal-launch type would then need to exclude it.

## D3. The mid-turn question and the error display

- **Decision**: When `session.isStreaming` is true, `handleForkSpawnCommand` asks the same `showHookConfirm` question as `/fork pane`, with the same text. A "no" answer creates nothing.

  `#spawnSibling` no longer calls `showError`. Its callers show the error:
  - `handleForkSpawnCommand` shows `Spawn failed: <message>` for a refusal and for a creation failure;
  - the tool part shows the same text and then throws to the tool, as before.

  On success, `#spawnSibling` keeps `showStatus("Spawned <name>")`.
- **Rationale**: FR-007 and FR-009 need every refusal to be visible in A. With `/fork spawn`, no tool result carries the error. One display point gives one message per failure.

  The tool path now also shows refusals in A, not only creation failures. The user then sees why a `/spawn` did nothing, also when the model does not repeat the reason.
- **Alternatives**: Keep `showError` inside `#spawnSibling` for creation failures only, and have `/fork spawn` show only the refusals. That needs an error type to tell the two apart.

## D4. No new zmx, label, or Emacs contract

- **Decision**: B uses the spec 021 contracts unchanged:
  - `cci-parent` and the other labels (`contracts/zmx-labels.md`);
  - the OSC announcement (`contracts/osc-spawn-announce.md`);
  - `/despawn` (`contracts/omp-spawn.md`).
- **Rationale**: FR-006 and FR-011 ask for the same result as a `/spawn` B. The package and `/despawn` cannot tell the two kinds of B apart, and they do not need to.

## D5. Documentation

- **Decision**: Update these files:
  - the `/fork` row and text in `docs/session-operations-export-share-fork-resume.md`;
  - the Unreleased "Added" entry in `packages/coding-agent/CHANGELOG.md`;
  - the `/spawn and /despawn sibling sessions` entry in `UPSTREAM_DIVERGENCES.md`, which gets one sentence and the new key path.
- **Rationale**: The `/fork` usage and inline hint come from the subcommand list. The docs list each `/fork` form.
