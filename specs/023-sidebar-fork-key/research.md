# Research: Fork a Session from the Sidebar with `S`

## R1. Where the fork runs

- **Decision**: The fork runs in A's omp, through the existing `handleForkSpawnCommand()` in `packages/coding-agent/src/modes/interactive-mode.ts`.
- **Rationale**: omp already has everything the fork needs: A's session file, the model, the zmx parent, the refusals, and the spawn announcement. Emacs does not know A's session file. omp runs on A's host, so the remote case needs no extra code.
- **Alternatives considered**: Emacs builds an `omp --fork <file>` command line and starts a new zmx session. Rejected. Emacs would need A's session file, model, and profile, and it would copy the refusal rules.

## R2. How Emacs asks A to fork

- **Decision**: Add a new APC packet `ESC _ pi:action;fork-spawn ESC \`. Emacs sends it with the existing `claude-code-ide-session-send-omp-packet`, through A's Ghostel terminal.
- **Rationale**: The `pi:` packet family already reaches omp for local and remote Sessions, because Ghostel writes to the zmx client in both cases. The Composer input listener in `packages/tui/src/prompt/composer.ts` reads each packet as one unit and consumes it. So no byte reaches the draft (FR-004, FR-011).
- **Alternatives considered**:
  - `pi:prompt;fork` plus Return. Rejected. The `pi:prompt` value cannot hold a space, it replaces the draft's leading command, and Return submits the whole draft.
  - Paste `/fork spawn` plus Return. Rejected. The text mixes with the draft, and during a turn it queues instead of forks.
  - A dedicated `pi:fork-spawn;` kind. Rejected. The `pi:action;<name>` form fits the existing `<kind>;<value>` grammar and the existing regex, with one new kind word.

## R3. How the packet reaches InteractiveMode

- **Decision**: Composer gets one public field, `onAction?: (name: string) => void`. The packet listener calls it for a `pi:action` packet. The InteractiveMode constructor sets `this.composer.onAction` right after it adopts or builds the Composer.
- **Rationale**: The Composer listener consumes every `pi:` packet before later listeners. So InteractiveMode cannot add its own listener after it. omp builds the Composer at startup and InteractiveMode adopts it later (`composer ?? new Composer(...)` at about line 2297). One assignment after that expression covers both paths. Before adoption the field is unset, and the packet is dropped. No Session exists at that time.
- **Alternatives considered**: Pass the callback in `ComposerOptions`. Rejected. The startup Composer exists before InteractiveMode, so a constructor option misses the adopted path.

## R4. Busy turn and dialogs

- **Decision**:
  - `handleForkSpawnCommand(confirmBusy = true)`. The packet path passes `false`, so a busy turn asks nothing (FR-009). A typed `/fork spawn` keeps the question (spec 022 FR-008).
  - Before the fork, the packet path checks whether a dialog owns input. It reuses the existing condition from `#isSpeckitStartBlocked`: `ui.hasOverlay()`, `ui.getFocused() !== editor`, or `editorContainer.children[0] !== editor`. This condition moves into a private `#inputOwnedByDialog()` that both callers use.
  - When a dialog owns input, omp shows the warning "Fork request ignored: close the open dialog first." and creates nothing (FR-012).
- **Rationale**: The existing condition already covers overlays, focus moves, and ask dialogs that replace the editor slot. An open `/spawn` window is session state, not a dialog, so it does not block the fork (FR-012, spec 022).
- **Alternatives considered**: Gate in Composer on `ui.getFocused() === editor`, as `pi:prompt` does. Rejected. Composer cannot show a warning, and it misses ask dialogs that replace the editor slot.

## R5. The package side

- **Decision**: A new command `claude-code-ide-manager-fork-at-point`, bound to `S` in `claude-code-ide-manager-mode-map` and in `claude-code-ide-manager-dispatch`.
  - No row: `user-error` "No manager session at point".
  - No live buffer (from `claude-code-ide-manager--session-buffer`), or a buffer whose process is dead: `user-error` "Session is disconnected. Press c to reconnect first". The helper checks the process only for remote Sessions, so the command checks `(process-live-p (get-buffer-process buffer))` itself.
  - Not omp (`claude-code-ide--session-cli-type` in that buffer): `user-error` "Only Oh My Pi sessions can fork".
  - Else send `pi:action;fork-spawn` in that buffer and show "Fork request sent to <name>". The name comes from `claude-code-ide-manager-item-display-name`.
- **Rationale**: These helpers already exist. The row buffer is the Ghostel buffer for local and remote rows, so one send path covers both (constitution VI).
- **Removal**: `claude-code-ide-manager-start-session-at-point-skip-permissions` goes away. Its only caller was the `S` binding and the dispatch entry. The `dangerous` argument of `claude-code-ide-manager-start-session-at-point` has no other caller, so it goes away too. The remote branch then rejects only a prefix ARG. The start and open menus outside the sidebar keep their own skip entries (FR-010).

## R6. Tests

- **Decision**:
  - omp, in `test/spawn-command.test.ts`, through `mode.ui.injectDebugInput`. This runs the real input pipeline and the Composer listener. Cases: a busy turn forks without a question, a non-empty draft stays the same, an open dialog blocks with the warning, and the `/spawn` window does not block.
  - omp, same file, the startup path: build a `Composer` and start it first, then pass it as the constructor's `composer` argument. A packet fed through that adopted `ui` must create one B. The default harness builds its own Composer, so only this case covers the adopted path.
  - omp, same file, overlap: feed two packets back to back without an await between them. `createSibling` must get two calls with two different names. `#spawnSibling` keeps no shared state between calls: each call makes its own random name, reads the same fork file, and writes its own announcement. So no lock is needed.
  - omp, in `test/modes/composer-editor-handoff.test.ts`: a `pi:action` packet calls `onAction` with its name, is consumed, and leaves the draft.
  - package, in `claude-code-ide-tests.el`: the binding, the dispatch mirror, the exact packet bytes for an omp row, and each refusal sends nothing.
- **Rationale**: Each case checks a user-visible property: the draft does not change, the question does not show, a dialog blocks, two presses make two Bs, and a refusal sends nothing.

## R7. omp repo rules

- **Decision**: `docs/agents/domain.md` asks for the root `CONTEXT.md` and `docs/adr/`. Neither exists, so no glossary term or ADR applies. The fork-only `pi:action` packet goes into the existing packet entry of `UPSTREAM_DIVERGENCES.md`.
