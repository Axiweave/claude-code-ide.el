# Research: Predefined Manager Layouts

**Date**: 2026-09-12 | **Feature**: `007-add-layout-presets`

This document resolves the technical questions in [plan.md](plan.md).
It records source-backed design decisions, not implemented behavior.
The four user decisions in [spec.md](spec.md) remain unchanged.

## Sources and scope

Primary sources are the current package, its installed Ghostel dependency, the installed RPC client, and Emacs runtime documentation.
The package requires Emacs 28.1 or later. The optional remote project client has a higher requirement of Emacs 30.1.
The inspected live Emacs runs version 31.1.50.

- [Package dependencies](../../claude-code-ide.el#L9).
- [Constitution](../../.specify/memory/constitution.md).
- [Domain vocabulary](../../CONTEXT.md).
- [Session ownership decision](../../docs/adr/0001-zmx-backed-agent-sessions.md).
- [Remote directory decision](../../docs/adr/0003-session-directory-stays-bare.md).
- [Ghostel shell creation](../../../ghostel/lisp/ghostel.el#L5367).
- [Ghostel shell preferences](../../../ghostel/lisp/ghostel-shell.el#L57).
- Installed `tramp-rpc-process.el`, located through the live Emacs `locate-library` result.

## R1. Use one preference and six fixed descriptors

**Decision**: Add `claude-code-ide-manager-layout-preset`, defaulting to `magit-left`.
Its values are `magit-left`, `magit-right`, `shell-left`, `shell-right`, `dired-left`, and `dired-right`.
A private constant table maps each value to its companion kind and companion side.
The table is not a user-extensible registration interface.

**Rationale**: Two existing sites choose orientation independently.
The local builder uses the old side preference at [manager:4617](../../claude-code-ide-manager.el#L4617).
The delayed remote display uses it at [manager:4541](../../claude-code-ide-manager.el#L4541).
Both must consume the same resolved descriptor.
Validate an unknown symbol before removing saved state or starting companion work.

**Alternatives considered**:

- Keep the old side setting as an alias: rejected by the user's explicit cutover decision.
- A layout registration framework: deferred with whole-layout customization.
- Six interactive commands: unnecessary because the existing preference and reset workflow is sufficient.

Remove the old package option and its production reads during implementation.
Replace its orientation test with observable preset-layout coverage.
The earlier feature-005 contract remains historical context, not the current preference contract.

## R2. Separate shell ownership from saved window state

**Decision**: Use one runtime-only manager hash table from canonical Session ID to companion shell buffer.
Do not key it by directory, Worktree, host, frame, or current Agent buffer name.
Use direct buffer identity for reuse. Buffer names are display and saved-layout metadata only.

**Rationale**: The actual manager enumerates Session IDs through `claude-code-ide-manager--live-session-keys` at [manager:1675](../../claude-code-ide-manager.el#L1675).
Directory lookup remains a legacy fallback in [manager:826–840](../../claude-code-ide-manager.el#L826), not the ownership model for new shells.
The reset command removes the saved layout before reconstruction at [manager:4757](../../claude-code-ide-manager.el#L4757).
Storing the only shell reference inside that layout would therefore lose a live shell on reset.

**Alternatives considered**:

- Store ownership only in the layout plist: rejected because reset discards that plist.
- Use `ghostel-project` or directory-based terminal lookup: rejected because same-directory Sessions must have distinct shells.
- Store process state in a new persisted Session schema: unnecessary. Liveness can be derived from the buffer's process.

The saved layout gains small descriptive fields, defined in [data-model.md](data-model.md).
The shell table stays independent from those fields and never enters manager persistence.

## R3. Create ordinary shells through Ghostel's existing interface

**Decision**: Put the Ghostel-specific creation and liveness operations in the existing terminal Session layer.
Creation uses `ghostel-create` with a unique name, nil display action, and the selected local or qualified remote directory.
Leave Ghostel's ordinary terminal identity and shell preferences intact.
The manager owns the Session association and the windows.

**Rationale**: [`ghostel-create`](../../../ghostel/lisp/ghostel.el#L5367) always creates a new shell and returns its buffer.
With nil display action, [`ghostel--create`](../../../ghostel/lisp/ghostel.el#L5255) does not call `pop-to-buffer`.
Its caller controls reuse and display.
[`ghostel-exec`](../../../ghostel/lisp/ghostel.el#L5326) omits ordinary shell integration, so it is not the right interface here.
The Agent creation path would also add Session, CLI, and optional zmx behavior that this shell must not receive.

Check Ghostel availability only when a shell must be created.
Check `buffer-live-p`, Ghostel mode, and the buffer-local `ghostel--process` with `process-live-p` for reuse.
A terminal handle or a live buffer alone does not prove a live shell.

**Alternatives considered**:

- Copy Ghostel shell resolution and launch code: rejected because it would diverge from user preferences.
- Call the interactive `ghostel` command: rejected because it selects a window and can reuse a terminal slot.
- Change Ghostel itself: not required by the inspected creation and process interfaces.

Creation failure must leave the Agent usable.
A uniquely named, unpublished buffer allocated by the failed request may be cleaned up if it has no live process.
A shell that already started must not be silently killed because later display or initialization failed.
Keep it as an ordinary terminal and report the failure if it cannot become the companion.

## R4. Preserve ordinary Ghostel exit behavior

**Decision**: Do not override `ghostel-kill-buffer-on-exit`.
If the shell process exits and its buffer survives, restore the old output with reset guidance.
If the buffer no longer exists, restore the remaining windows and show the guidance without starting a shell.

**Rationale**: Ghostel defaults this preference to t at [ghostel:419](../../../ghostel/lisp/ghostel.el#L419).
Its [sentinel](../../../ghostel/lisp/ghostel.el#L3883) either kills the exited buffer or appends an exit marker.
The specification promises output only when it remains available.

**Alternatives considered**:

- Force output retention: rejected because the user asked to retain ordinary shell preferences.
- Automatically restart on return: rejected by clarification 4.
- Treat closing a window as shell exit: rejected because the process can remain live in its buffer.

## R5. Reuse native window-state restoration

**Decision**: Extend the existing layout plist and restoration function rather than create another window-tree format.
Store the applied preset and companion metadata with the saved layout.
A missing or exited saved companion must not turn an ordinary return into a default-layout shell launch.
Retain the selected window when it still exists. Otherwise, select the Agent window.

**Rationale**: [Layout capture](../../claude-code-ide-manager.el#L4304) already uses writable `window-state-get` data.
[Restoration](../../claude-code-ide-manager.el#L4354) already substitutes renamed buffers and calls `window-state-put` with `safe`.
[Persistence filtering](../../claude-code-ide-manager.el#L1447) already removes memory-only buffer references.
Extend those existing operations for companion metadata.
Do not put a shell into the remote Project-view identity guard, which rejects stale or missing Project views before restoration.

A batch experiment on Emacs 31.1.50 captured two windows, killed the companion buffer, and restored the saved state.
The result was one selected Agent window, no recreated companion buffer, and no error:

```text
restored=((" *layout-probe-agent*" t))
recreated-missing-buffer=nil
```

This proves the inspected runtime behavior, not compatibility testing on Emacs 28.1.
The implementation must keep a regression check for the package's supported Emacs versions.
If native restoration fails for another reason, a saved shell layout still uses an Agent-only recovery path until explicit reset.

**Alternatives considered**:

- A custom recursive window-state parser: not justified by the native behavior.
- Rebuild every layout on return: rejected because it loses saved arrangement, focus, and process identity.
- Read the current default during restoration: rejected because changing a preference must not alter a saved layout.

## R6. Release shells on removal, retain them on disconnection

**Decision**: Release the manager's shell-table entry when the owning Session ends or is removed.
Do not kill the shell buffer, process, or remote connection.
Retain the entry across temporary remote disconnection when the remembered Session ID remains available for reattachment.

**Rationale**: [`claude-code-ide-manager-session-ended`](../../claude-code-ide-manager.el#L3259) already distinguishes retained remote rows from forgotten rows.
[`claude-code-ide--cleanup-on-exit`](../../claude-code-ide.el#L1349) removes the live Agent record before resource cleanup.
The manager's remembered remote row therefore matters when deciding whether the Session identity survives.
A companion shell is a separate buffer and process, so Agent cleanup must never receive it as the Agent buffer.

**Alternatives considered**:

- Put the shell under Agent process cleanup: rejected because a running command must survive Session removal.
- Release on any attachment sentinel: rejected because remote disconnection is not confirmed Session termination.
- Reclaim a released shell by directory or name: rejected because ownership follows Session identity, not a reusable label.

Survival applies within the running Emacs instance.
Ordinary Emacs shutdown and Ghostel buffer deletion retain their existing behavior.

## R7. Use admitted RPC paths, not a second package-level transport

**Decision**: Build a remote companion directory with `claude-code-ide-remote-project-rpc-directory` after exact-host admission.
Run creation through the existing remote attempt worker and client safety checks.
Let the installed RPC client choose its configured PTY transport.
Do not construct a new `/ssh:` path or a separate package-owned SSH command.

**Rationale**: [Manager admission](../../claude-code-ide-manager.el#L789) checks both the configured host and enabled project access.
[Remote path qualification](../../claude-code-ide-remote-project.el#L763) keeps bare Session directory metadata out of local file operations.
The existing [worker](../../claude-code-ide-remote-project.el#L1157) performs guarded client loading, health checks, and preparation off the main thread.
The optional remote client requires Emacs 30.1 at [remote-project:1259](../../claude-code-ide-remote-project.el#L1259).
This does not raise the local package's Emacs 28.1 requirement.

The installed `tramp-rpc-handle-make-process` supports PTYs in `tramp-rpc-process.el:831–837`.
Its PTY dispatcher at lines 1010–1031 uses `tramp-rpc-use-direct-ssh-pty` when enabled, or an RPC PTY otherwise.
The direct SSH path reuses the existing ControlMaster socket.
An RPC-qualified path therefore does not promise that all terminal bytes use the RPC socket.
The feature preserves that client policy rather than overriding it.

**Alternatives considered**:

- Force the RPC-only PTY policy: unnecessary and would change user transport preferences.
- Start the shell synchronously in the manager: rejected because remote I/O could block the Agent interface.
- Skip project-access admission because SSH attachment works: rejected by the specification and constitution.

## R8. Preserve remote shell preferences without local substitution

**Decision**: Let Ghostel resolve the shell for the `rpc` method, including a catch-all preference and connection-local `shell-file-name`.
Do not copy the `ssh` preference into `rpc` or force a login shell.
Keep an explicit `rpc` entry as an optional user configuration, not an installation prerequisite.

**Rationale**: [`ghostel--resolve-shell-spec`](../../../ghostel/lisp/ghostel-shell.el#L263) checks method-specific and catch-all entries first.
It then reads the connection-local shell value before its final configured shell fallback.
The defaults list SSH-style methods and Docker, but no `rpc` entry.
Recognized remote shells receive type-aware arguments from [`ghostel--default-remote-shell-args`](../../../ghostel/lisp/ghostel-shell.el#L252).
A selected program still executes on the remote host because the process directory remains RPC-qualified.
Failure must produce an explanation, not a local terminal.

**Alternatives considered**:

- Treat a missing `rpc` preference entry as unsupported: inconsistent with Ghostel's existing fallback contract.
- Guess the remote user's shell from the local environment: unnecessary and unsafe for portability.

## R9. Distinguish companion providers from remote location identity

**Decision**: Preserve the meaning of the existing remote view key's first three fields: host, location kind, and canonical location.
Add a runtime provider descriptor to shared Git/Dired view keys.
The descriptor records companion kind, captured provider function, and requested RPC directory.
Shells bypass the shared Project-view registry and publish only into their Session's shell table.

**Rationale**: [`--resolve-view-key`](../../claude-code-ide-remote-project.el#L740) uses `git` versus `directory` to describe the location, not the selected preset.
Replacing that field with `shell` or `dired` would break location and Worktree semantics.
[`--prepare-view`](../../claude-code-ide-remote-project.el#L959) currently invokes the configurable status provider.
[`--lookup-native-view`](../../claude-code-ide-remote-project.el#L797) can prefer a Magit buffer before Dired.
A Dired preset must instead call `dired-noselect` for the exact requested Session directory and reject Magit substitution.

Git provider invocation receives the captured Session directory, even if the location key identifies its Worktree root.
The default Magit provider can still select its normal repository view.
The requested directory remains part of the provider descriptor so different custom views do not accidentally share a cache entry.
An explicit non-Session Project-view request retains its existing Git-provider semantics and callback contract.

Native Magit or Dired functions may return one buffer for multiple provider keys.
Cleanup must check every registered owner of that exact buffer before killing a feature-created view.
A provider switch must never destroy another Session's saved or visible view.
Keep the existing conservative treatment of custom, modified, and preexisting buffers.

**Alternatives considered**:

- Reuse the location triple alone: rejected because a Dired request could receive a cached Magit view.
- Store shells in the shared registry: rejected because same-directory Sessions must have distinct processes.
- Disable all native view reuse: unnecessary and contrary to the existing view ownership behavior.

## R10. Capture request intent before asynchronous work

**Decision**: Capture the applied preset, provider, companion side, exact directory, and create permission at request admission.
Add those fields to the existing attempt and frame display intent rather than create another scheduler.
All completion paths must verify current attempt, host admission, Session ID, attachment, frame epoch, and captured layout request.
Changing a preference alone does not change an admitted request or a saved layout.
An explicit reset supersedes the old request.

**Rationale**: Existing [attempt checks](../../claude-code-ide-remote-project.el#L226) cover attempt, host, and attachment identity.
Existing [frame intent](../../claude-code-ide-manager.el#L1074) records display ownership and an epoch.
These checks do not currently include a preset or captured provider.
The [completion path](../../claude-code-ide-remote-project.el#L1023) currently assumes every result is a shared Project view.
Extend it with a shell-result branch before shared-view registration.

A stale result must never appear in the current layout.
If a stale request already started a shell, retain that buffer as an ordinary terminal rather than kill a running command.
It must not replace the current Session's companion association.
Cancel unfinished request work through the existing attempt mechanism without closing a shared remote connection.

**Alternatives considered**:

- Read the global preset during completion: rejected because it can apply a preference that the user has not reset into the Session.
- Add only the preset to a cache key: insufficient because orientation, frame ownership, and startup permission also affect publication.
- A second worker pool for shells: unnecessary because the existing admitted attempt machinery supplies the required lifecycle.

## R11. Keep verification honest

**Decision**: Preserve the required repository gate and report its existing failure as an error.
Do not install dependencies, alter unrelated tests, or treat a complete design as a passed implementation gate.
Use behavioral ERT checks and live Emacs scenarios during implementation, as defined in [quickstart.md](quickstart.md).

**Rationale**: The last observed gate passed compilation but failed ten existing tests that require unavailable Magit modules in its batch load path.
The live Emacs uses a different package directory and can locate Magit.
That environment difference does not prove that the required gate passes.
The implementation must satisfy the exact gate, including optional-dependency rules.

**Alternatives considered**:

- Run only the new layout tests: insufficient for constitution principle II.
- Mark the existing failures as a justified exception: rejected because the gate is non-negotiable.
- Run remote feature acceptance during planning: rejected because the feature is not implemented and remote access is not needed to write the design.

## Resolution summary

All technical research questions have concrete design decisions.
No product clarification remains open.
The only outstanding execution prerequisite is the repository quality gate, which must pass before implementation acceptance.
No source implementation, new test suite, or remote connection was created by this planning command.
