# Contract: Ghostel-Only Elisp and User Surface

**Spec**: [spec.md](../spec.md)
**Model**: [data-model.md](../data-model.md)

This package exposes Elisp commands, customization, buffer operations, and documentation.
This feature adds no HTTP, MCP, or external service endpoint.
Existing MCP and Agent capabilities remain unchanged.

## C1. Terminal construction and optional support

### Shared Agent factory

`claude-code-ide--create-terminal-with-command (buffer-name working-dir cmd env-vars)` retains its arguments and `(buffer . process)` result.
It uses `ghostel-exec` with the existing shell program, `-lc` command arguments, and dynamic environment.
It preserves local zmx wrapping, remote exclusion from local wrapping, CLI identity, and Session setup.
Success requires the requested terminal and an actual live process.

Startup must not substitute another host, directory, or terminal.
A failure preserves unrelated Sessions and processes and reports the actual cause.
Cleanup must distinguish a newly created dead partial buffer from an existing or newly live buffer.

### Shared support check

`claude-code-ide-session--ensure-ghostel ()` replaces the removed selection-dependent ensure helper.
It returns normally only when the Ghostel library and required native support are available.
It produces an actionable `user-error` when support is missing.
It does not select a runtime, install software, or alter global Ghostel preferences.

Agent creation, remote attachment, and companion creation use this check.
Each constructor's dynamic scope disables `ghostel-module-auto-install`, including the support check and constructor call.
The package does not call this check during ordinary package loading or non-terminal use.

The shared check includes both soft library loading and `ghostel--new` availability.
Do not leave the companion's native check separate from the Agent preflight.

### Creation and publication order

1. Validate the request using existing local directory or remote admission rules.
2. Disable auto-install dynamically before the shared library/native preflight.
3. Complete preflight before MCP startup or terminal creation.
4. Create the terminal with the existing environment, command, and setup timing.
5. Validate the exact returned buffer and live process before active Session registration.
6. Register the Session and install existing ownership-bound lifecycle callbacks.
7. Recheck process liveness and registry ownership after the initialization delay.
8. Display the attachment and report success only after those checks.

For companions, publish ownership only after process validation and the manager's captured-request checks.
On failure, roll back only registration and resources owned by the failed request.
Preserve pre-existing Sessions, persistent Agents, and unrelated processes.
Preserve a live ordinary companion after partial failure under the existing companion cleanup rules.
The remote workflow may retain its existing disconnected target row. That row is not a successful active Session.

### Companion construction

Keep the existing companion creator's interface and `ghostel-create` call.
Validate the requested absolute accessible directory under existing local/remote rules.
Use a fresh generated buffer name and retain ordinary shell initialization.
Return a buffer only after its buffer-local Ghostel process is live.
Reuse remains the manager's responsibility, keyed by exact Session ID.

## C2. Session input and setup

| Retained interface or operation | Observable contract |
| --- | --- |
| `claude-code-ide-session-send-string (string &optional paste)` | Raw input uses `ghostel--send-string`. Paste uses `ghostel-paste-string`. Record activity only after successful input. |
| `claude-code-ide-session-paste-clipboard ()` | Existing supported image targets for Claude, Codex, and OMP use the current Ctrl-V path. Other clipboard input uses `ghostel-yank`. |
| `claude-code-ide-session-send-escape ()` | Send the existing Escape sequence, not clipboard text. |
| Return operation | Preserve the existing carriage-return submission behavior. |
| Interrupt operation | Use Ghostel's Ctrl-C operation with the existing Session guard. |
| Control-G operation | Use Ghostel's Ctrl-G operation with existing Session and activity behavior. |
| Session setup | Preserve idempotence, setup hooks, keybindings, CLI state, and actual Ghostel mode checks. |
| `claude-code-ide-session-buffer-p` | Preserve customizable Session predicates. Ordinary terminal mode alone does not establish ownership. |
| `claude-code-ide-session-for-buffer (&optional buffer)` | Preserve exact registered-buffer lookup without remote requests. |

Keep the surviving generic terminal-send and keybinding aliases used by package consumers.
They alias surviving behavior, not retired support.
Specifically, keep `claude-code-ide--terminal-send-string`, `claude-code-ide--terminal-send-escape`, and `claude-code-ide--terminal-send-return`.
Keep the existing shared keybinding and Ghostel-configuration aliases unless every caller migrates in the same cutover.
Do not broaden image support, change Agent commands, or introduce Agent-specific terminal policy.

## C3. Display, activity, and cleanup

`claude-code-ide-prevent-reflow-glitch` remains a meaningful Ghostel setting.
Keep working-state observation, copy-mode scroll detection, the reflow filter, and the exact Ghostel cursor path.
Remove backend selection from resize observer installation and removal.
The install/remove helpers take no backend argument and target `ghostel--adjust-size` directly.
Migrate every caller and test for that arity change.

Observer installation remains idempotent.
Keep the existing first-Session installation and last-Session removal lifecycle.
Track output through both `ghostel--filter` and `ghostel--events-filter`.
Keep focus-driven activity and notifications bound to the correct Session.

Ghostel process/sentinel handling and shared buffer cleanup remain responsible for attachment lifetime.
A stale callback cannot kill a new attachment or act on another Session.
Deleting retired exit hooks must not remove shared ownership checks.

## C4. Layout and persistent-session behavior

Keep these preset values unchanged:
`magit-left`, `magit-right`, `shell-left`, `shell-right`, `dired-left`, `dired-right`.

Keep `claude-code-ide-manager-switch-to-session (session-key &optional keep-manager-focus scope)` unchanged.
Keep `claude-code-ide-manager-reset-layout (session-key &optional keep-manager-focus scope)` unchanged.
Saved-layout precedence, selected-window restoration, and live companion reuse remain unchanged.
Generic `claude-code-ide-window-side` and `claude-code-ide-window-width` remain available.

Local persistent adoption and approved remote attachment keep their exact identity and ownership rules.
Detach remains distinct from Stop.
A disconnected terminal does not prove that a persistent Agent has exited.
Remote project-view failure does not prevent an otherwise permitted terminal attachment.
No new host approval, automatic connection, local fallback, or replacement Agent is permitted.

## C5. Removed surface

This inventory is an explicit removal record under FR-013.
It lists deletion targets, not deprecated APIs or supported configuration examples.

| Removed category | Named deletion targets and scope |
| --- | --- |
| User selection | `claude-code-ide-terminal-backend`, `claude-code-ide-cli-terminal-backends` |
| Runtime selection | `claude-code-ide--resolve-terminal-backend`, `claude-code-ide--current-terminal-backend`, `claude-code-ide-session--current-terminal-backend` |
| Selection cache and lookup | `claude-code-ide--terminal-backend`, `claude-code-ide--backend-for-process` |
| Selection-dependent dependency dispatch | `claude-code-ide--terminal-ensure-backend`, replaced by the single-runtime support check in C1 |
| Resize selection | `claude-code-ide--terminal-resize-handler`, `claude-code-ide--terminal-supports-reflow-guard-p` |
| Retired settings | `claude-code-ide-vterm-anti-flicker`, `claude-code-ide-vterm-render-delay`, `claude-code-ide-eat-preserve-position` |
| Retired implementations | EAT/vterm constructors, input/display/setup branches, copy-mode helpers, renderer queues/timers, cursor workarounds, process hooks, callbacks, and exit cleanup |
| Retired aliases | EAT/vterm configure-buffer aliases and any other alias whose target provides removed support |
| Test and runner dependencies | EAT/vterm mocks, provided features, backend-choice fixtures, and `emacs-libvterm` discovery |

Legacy user assignments have no effect because the package no longer declares, reads, or dispatches on these preferences.
Do not add obsolete-variable declarations, aliases, fallback resolvers, or constant-return substitutes.
Do not remove unrelated zmx, project-view provider, popup, or Agent settings merely because their descriptions use the word backend.

## C6. Related Spacemacs consumer

Parent paths are relative to the package repository root:
- `../../lisp/pkgs/pkg-claude-code-ide.el`
- `../../tests/pkg-claude-code-ide-test.el`

Remove terminal-selection assignments and the dead retired-terminal workaround comment.
Replace the five removed resolver calls in page navigation, End, and Evil state hooks with actual Ghostel mode checks.
Preserve unrelated-buffer fallback, Plan Review key pass-through, copy-mode transitions, and visible-window-only recentering.
Keep package Session keymap scope and existing CLI distinctions.

Parent tests must exercise actual mode boundaries instead of stubbing the removed resolver.
Keep file-reference behavior and the surviving generic input alias.
Preserve the existing layout preset and generic popup settings, including unrelated uncommitted changes.
No other parent terminal workflow enters this migration.

## C7. Documentation and verification

The README's existing fork-distinction list must state Ghostel-only support and retain the original repository attribution.
Every active installation, configuration, operation, and troubleshooting section must agree.
Apply the same rule to prior feature documents, hidden automation, comments, backlog, and maintainer guidance.
The inventory covers tracked maintained files and explicitly maintained untracked feature artifacts.
Ignored `refs/`, `ref-docs/`, and `.omp/` contents belong to a separate reference/local-state inventory, not the cleanup acceptance set.
External checkouts remain unchanged except for the two named parent consumer files.

Retired product references may remain only in explicit removal records.
Each retained reference must describe deletion or governance history, not continuing support.
Do not relabel old native test evidence as a new Ghostel result.

Verification includes the full batch gate, optional-support absence, constructor failure isolation, related parent tests, and native workflow checks.
Report dependency-present integration results separately from optional-absence results.
A batch mock pass does not prove native terminal rendering or approved remote behavior.

## Compatibility boundary

The minimum Emacs version remains 28.1.
No new runtime dependency or persisted schema is required.
An editor restart is permitted for upgrade.
Do not convert live retired-terminal buffers, uninstall packages, or rewrite Git history.
If code reload leaves an old terminal buffer alive, actual mode checks must reject package terminal operations on it.
Do not reconfigure it as Ghostel, send Ghostel input to it, adopt it, or kill it during reload cleanup.
Explain the restart requirement for unsupported use without retaining a retired-terminal dispatcher.
New Session creation ignores old preferences and buffer-local backend caches.
