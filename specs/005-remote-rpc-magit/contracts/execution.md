# Execution and Ownership Contract

This is an internal integration contract, not a new public transport API. The future feature module owns attempts and view records. The manager owns window layout.

## Module Boundary

Use direct functions for these operations:

| Operation | Inputs | Result and authority |
|-----------|--------|----------------------|
| Prepare | Session ID, exact attachment, frame, reason | Starts a permitted attempt or reuses an existing requested view. Never blocks the manager. |
| Cancel | Session ID, current attachment, reason | Invalidates only that attempt and stops its worker through private abandonment. |
| Record display/dismissal | Session ID, frame, exact view buffer | Updates in-memory display intent or suppression. No remote access. |
| Session ended | Session ID, exact old attachment | Invalidates old work. Does not clean up Project views or erase remembered suppression. |
| Explicit detach cleanup | Pre-detach ownership snapshot and successful detach outcome | Kills only eligible local buffer objects. No remote query or connection cleanup. |
| Get surviving view | Session ID and current attachment | Returns the matching live buffer or nil without resolving a remote path. |

Do not add callback registries, generic providers, network queues for unrelated modules, or a second Session identity system.

## Admission and Freshness

A preparation request must verify all of the following before remote access:

1. The Session is attached through the existing supported remote path.
2. The exact host remains in the existing approved host list.
3. The Project-view host option is enabled.
4. The Session has no manual-close suppression, unless this is `R`.
5. The request reason is first managed display, explicit reset, permitted reattach, or replacement of a sibling-killed requested view.

Ordinary rendering, startup, metadata refresh, preference enablement, and saved-state loading are not request reasons.

Check attempt ownership again before each feature phase and before publication. Host option and approval changes must invalidate pending attempts without performing remote I/O. A variable watcher or existing setter notification may perform that local invalidation.

Publication requires the exact current attempt and attachment. Display additionally requires the current frame's Session and visible terminal. Keyboard focus is not a freshness condition.

## Installed-Client Adapter

### Scope

Install the adapter only after the optional client passes its capability check. Guard `tramp-rpc--connect`, `tramp-rpc--establish-controlmaster`, and `tramp-rpc--start-server-process`.

The connection wrapper owns scoped configuration and the connection-in-progress flag. The server-start wrapper owns admission, native initialization completion, and the post-start checkpoint.

Both wrappers check admission and completion. If native code returns or raises `error` after invalidation, signal private abandonment before provider fallback.

The authentication wrapper checks the token before each native entry, including retries. Bind `timer-list` and `timer-idle-list` to nil around that native authentication call.

This keeps its timeout timer on the worker's dynamic timer list. The main thread retains its normal timers. Do not change the native authentication timeout.

The adapter is active only when the current thread is an owned feature worker and the connection vector matches that worker's exact target. Main-thread RPC use and unrelated workers take the original path.

Match the client's route-aware connection identity, not the vector's local directory. A reconnect from another subdirectory remains part of the owned attempt.

Do not replace the client's request encoder, process filter, connection registry, or terminal transport. Do not edit installed sources or the reference checkout.

### Binary selection and no provisioning

At each connection or reconnect entry, read the effective current client configuration before applying feature bindings.

- In normal mode, use `tramp-rpc-deploy-expected-binary-localname`.
- In normal never-deploy mode, retain the explicit path or the configured bare binary name.
- Bind `tramp-rpc-deploy-never-deploy` to `t` for this connection call.
- Bind `tramp-rpc-deploy-remote-binary-path` to that same normally selected path.

The inner connection-boundary binding covers buffer-local configuration. A single outer worker binding is insufficient if a provider changes buffers.

Retain the guard for the whole worker lifetime, including status preparation and reconnect. A health-only guard does not satisfy the contract.

Do not set `auto-deploy=nil` as the only defense. Its installed implementation still permits local artifact acquisition.

### Authentication

Bind the raw SSH arguments before invoking the original `tramp-rpc--connect` function. The binding must cover its first ControlMaster establishment and server startup.

Prepend these arguments before the existing arguments:

```text
-o BatchMode=yes -o StrictHostKeyChecking=yes
```

Preserve the remaining arguments, aliases, identity configuration, routes, and global settings. Do not turn off normal connection sharing.

If the client cannot connect with current credentials and trust, fail this optional view with setup guidance. Do not request credentials or accept a new host key during automatic preparation.

Bind `tramp-error-show-message-timeout` to nil during worker work. Preserve `tramp-verbose` and let the error reach the main-thread guidance path.

Without this binding, TRAMP's login-error path can select a buffer, discard input, and pause for 30 seconds.

### Capability check

Check all three guarded entry points, the deterministic binary selector, no-deploy variables, connection accessors, and public process-thread controls. Validate behavioral assumptions through the compatibility tests.

Do not claim compatibility from a version string alone. If a required safety interface changes, retain the terminal and report the unsupported client. Do not silently substitute a different transport.

## Worker and Deadline

Create one worker for each admitted Session attempt. Keep display and manager mutations on the main thread.

Bind `inhibit-interaction` to `t` during worker work. A provider that requires interaction follows the normal error/fallback path instead of opening a prompt.

After native server startup succeeds, unlock its stdout and stderr processes only when the current feature worker owns their thread locks.

Use `set-process-thread` with nil for those owned locks. Do this before the post-start cancellation checkpoint, and defensively after a successful connection return.

Never change an unlocked or foreign-owned process. This lets an unrelated RPC consumer read responses while the feature worker waits for its view-writer slot.

Start the 30-second health timer before the first connection acquisition. Cancel that timer when current-attempt health succeeds or fails. Identity resolution and initial provider preparation remain cancellable without a new fixed deadline.

Health uses an uncached public `process-file` call for `true` in the intended remote directory. Success requires a zero exit status from the current request.

Do not shorten the installed client's RPC timeout to implement the feature deadline. The client's timeout cleanup has different ownership semantics.

## Abandonment

For cancel, deadline, supersession, detach, disabled host, or lost approval:

1. Invalidate the attempt token on the main thread.
2. Cancel its feature deadline timer.
3. If no connection initialization is active, signal the private abandonment condition to the live worker.
4. Reject any queued completion from that token.

The condition must inherit from neither `error` nor `quit`. The worker boundary handles it without normal provider/Dired error fallback.

During an already admitted connection operation, invalidate and report immediately but defer thread signaling. Let the native operation finish under its own timeout policy.

The server-start wrapper checks the token before invoking the original function. Cancellation during authentication therefore prevents RPC server startup.

Once server startup has entered its readiness operation, let its existing handshake finish. The original client must apply its profiles and connected properties.

After a normal return, unlock the owned transport processes before checking cancellation. On either a return or an error, convert an invalid attempt to private abandonment.

This checkpoint prevents a canceled reconnect error from reaching provider fallback. It also stops the feature before another health or status request.

The connection-in-progress flag clears on every exit. The feature's health phase still ends at its own deadline, even if native initialization finishes later.

Outside connection initialization, the installed pending-request wrapper releases request IDs during the private nonlocal exit. Late replies cannot publish into the abandoned attempt.

Do not call `delete-process`, `tramp-cleanup-connection`, `tramp-rpc--disconnect`, or a connection invalidation helper for feature abandonment. Do not signal `quit` or send a remote process kill.

The installed client still owns natural transport failures and timeouts. Do not suppress them to make a failed connection appear healthy.

Never synthesize connected properties or connection-local settings after an interrupted handshake. Let the original initialization finish instead of leaving a partially initialized registered generation.

## Provider Preparation

After health, resolve Worktree identity through remote file operations. A `.git` file also marks a Worktree. A non-Git directory retains its exact directory identity.

Check and claim the view identity without yielding. A second feature attempt waits cancellably for that creator, then repeats the existing-buffer lookup.

Check native buffers as well as the feature registry. At the resolved root, use `magit-get-mode-buffer` for Magit and `dired-find-buffer-nocreate` for Dired.

Validate exact directory identity for Dired. An ancestor-directory hit does not satisfy a different non-Git view key.

Do not call `dired-noselect` merely to look for a surviving buffer. Its `dired-auto-revert-buffer` setting can cause a refresh.

If a matching buffer survives, return it unchanged. Do not call the provider, reinitialize its mode, revert it, or refresh it.

This rule includes hidden buffers, first display, reattach, and `R`. Health remains mandatory for each new permitted attempt.

Only a missing view invokes the configured local provider and normal fallback. Keep its candidate undisplayed by the manager until completion.

Record the exact new candidate through the native creation path. Do not hide it from Magit's lookup, copy buffer state, or advise ordinary provider commands.

The creation slot serializes feature attempts only. It does not serialize user-directed native Magit/Dired commands on the same project.

During initial creation, wait for completion or cancel before manually opening or refreshing the same project's native view. This is an installed-provider concurrency limitation.

After completion, native `g` retains its normal behavior. Published views never receive feature-owned writes.

On valid completion, check for a matching surviving view again. Reuse it if another creator won. Never publish a duplicate current view.

Release only a known, never-published candidate during abandonment or a lost creation race. Preserve source-file, user-claimed, and uncertain custom buffers.

Never reuse a known incomplete candidate. If ownership prevents discarding it, retain it and report that the user must resolve it before retry.

These candidates are attempt scratch resources, not published Project views. Published-view cleanup still requires its separate opt-in and explicit detach.

Bind Magit's display function to `ignore`, its no-select variable to `t`, and `magit-inhibit-save-previous-winconf` to `unset`.

The last binding prevents Magit from recording a worker-time frame configuration for a later `q`. Do not restore an old frame configuration.

Bind `warning-minimum-level` to `:emergency` during provider work. Keep `warning-minimum-log-level` unchanged to preserve the user's logging policy.

The Magit display-function binding does not cover `display-warning`. Missing or old remote Git must not create an unmanaged warning window.

A custom provider must return a buffer through the existing contract. Do not overwrite the user's provider, VC policy, or cache settings to force success. Preserve uncertain custom buffers from cleanup.

A custom provider must obey undisplayed creation and reuse without mutation. Do not add a generic buffer-state copier for providers that cannot obey this contract.

A feature cancellation must stop provider work before further remote requests or fallback begin. Cleanup during unwinding may release local request bookkeeping, but it must not publish a canceled result.

Killing a candidate invalidates its owning attempt and triggers private abandonment. It must not become an ordinary provider error followed by Dired fallback.

Recognize a created buffer only through the known creation path and exact returned buffer identity. A general before/after `buffer-list` difference is not enough when other user activity can create buffers concurrently.

## Completion and Layout

The main-thread completion handler checks the attempt and attachment before registering a buffer. It then checks frame display intent independently.

A valid result may remain undisplayed after a Session switch. Later navigation can use the surviving buffer without another remote refresh.

Enabled-host first managed display and `R` create an ordinary terminal window through the local content-window reset path. Remove stale side windows for that terminal.

For current visible Sessions, split that ordinary terminal window on the side opposite the configured terminal position. Preserve the selected window and manager.

If the terminal is now a side window or cannot split, retain the ready buffer without changing unrelated content. Give `R` as the corrective action.

After saved layout restore, insert a live requested view that is not yet visible through the same helper. This requires no health check or provider refresh.

Keep the captured Project-view name in memory with its exact buffer object. If that object survives, substitute its current name throughout saved window references.

Include previous/next-buffer references in that substitution. If the runtime view record is missing or dead, return nil from enabled-host restore and rebuild the terminal-first default.

The normal suppression and replacement rules then decide whether preparation is permitted. Never restore a different live buffer merely because its name matches an old view.

## Manual-Close Observation

The manager records a before-command snapshot only when a registered Project view and the Session terminal are actually visible.

At command completion, suppression requires:

- The snapshot's frame retains the same exact attachment token and manager layout epoch.
- The view buffer is dead or no window in that frame displays it.
- The view window was deleted, the buffer was killed, or the command started with the view window selected.

Require terminal visibility only in the before-command snapshot. Removing both windows with `C-x 1` can still express manual closure.

Do not classify Help or compilation reusing an unselected view window as dismissal. Test `q`, `C-x b`, and `C-x 1` separately.

Manager switches, reset, detach, restore, and asynchronous view insertion advance the epoch. They must not count as manual closure.

A shared buffer kill invalidates its registry entry. Only the initiating Session gains suppression. Other Sessions retain their requested view intent.

Default-layout creation and restore update the frame token. Session-ended and remembered-remote-state transitions clear only the matching stale attachment token.

Treat `q` and replacing the view through Dired `RET` as dismissal when they remove the displayed view. Test these commands separately from buffer killing.

Do not install one suppression-setting kill hook per sharing Session. Do not treat the absence of a never-displayed result as a closure event.

## Explicit Detach Cleanup

Capture candidates and known sharing evidence before the terminal's generic cleanup removes Session state. Apply Project-view cleanup only after the explicit detach succeeds.

Before each kill, check the snapshot's attachment token and the current buffer object. Preserve modified, preexisting, custom-uncertain, shared, and source-file buffers.

Unknown same-host project identity prevents an exclusivity claim. Use the existing known `:worktree-path` where valid. Do not use `:common-dir` to merge different Worktrees.

Cleanup must not run remote predicates, resolve paths, save files, prompt for remote saves, or retire connections.

Require exact `magit-status-mode` or `dired-mode`, no modification, no file, no process, and no `tramp-temp-buffer-file-name`.

Any unknown buffer-local kill or query hook vetoes cleanup. Ignore the `t` inheritance marker and allow the feature's local registry hook.

For eligible buffers, bind `kill-buffer-query-functions` to nil only for the kill. Keep global kill hooks active, including perspective and buffer-name bookkeeping.

This follows existing Session cleanup and avoids perspective query prompts. Verify the real perspective-enabled profile, not only a clean batch Emacs.

Explicit detach of a disconnected remembered row uses the same local eligibility rule. It never starts a remote query.

## Required Boundary Checks

Implementation must demonstrate these cases before release:

- Reconnect after health cannot enter artifact acquisition.
- A buffer-local deployment setting cannot disable the attempt guard.
- An unrelated RPC user retains its original deployment and authentication settings.
- Deadline and cancellation preserve an existing shared connection.
- Canceled startup either never enters server startup or completes native initialization before the post-start checkpoint.
- Owned stdout and stderr locks release before another consumer needs them, even when the creator worker remains alive.
- A native startup timeout retains client cleanup behavior and cannot trigger fallback for an abandoned attempt.
- Cancellation during failed authentication starts no second authentication process.
- The native login timeout still fires when the main thread processes timers first.
- Login failure selects no window, discards no input, and adds no display pause from worker code.
- Magit dependency warnings remain logged without adding a worker-owned window.
- No new RPC request, provider fallback, buffer publication, or layout change follows abandonment.
- Two Sessions sharing one view cannot publish duplicate current buffers.
- Reuse preserves buffer text and mode state, even while the user moves point, refreshes, or edits the surviving view.
- A second feature attempt waits for missing-view creation instead of reusing or refreshing an incomplete candidate.
- Cancellation followed by `R` never reuses an incomplete candidate left by the abandoned attempt.
- Manual window dismissal and shared-buffer killing suppress only the initiating Session.
- Cleanup has no remote I/O, save, or connection-retirement path.
