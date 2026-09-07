# Implementation Plan: Opt-in Remote RPC Magit View

**Feature**: `005-remote-rpc-magit` | **Date**: 2026-09-06 | **Spec**: [spec.md](spec.md)
**Git branch**: `main`. The setup script reports the feature slug as `BRANCH`. No branch switch occurred.
**Input**: `/specs/005-remote-rpc-magit/spec.md`, constitution 1.1.0, and the confirmed clarification answers.
**Scope**: Planning documents and isolated feasibility experiments only. Implementation, live configuration changes, deployment, and commits require separate authorization.

## Summary

Add an optional remote Project view to the existing managed Session layout. Keep both per-host preferences disabled by default.

First managed display starts background preparation after the terminal appears. Manager `R` resets the whole layout and starts a fresh attempt. Manager `? C` cancels preparation without detaching the terminal or retiring a shared RPC connection.

Use the installed `tramp-rpc` client, standard remote file operations, and the existing local status provider. Share one buffer per exact host and Worktree. Keep layout intent and manual-close suppression per Session.

Use one feature module for remote preparation, attempt ownership, view identity, and conservative cleanup. Keep manager layout decisions in the manager. Do not add a new transport, provider framework, persistence format, or upstream package fork.

## Technical Context

**Language/Version**: Emacs Lisp with lexical binding. The package baseline remains Emacs 28.1. The optional installed RPC client requires Emacs 30.1 or later.
**Primary Dependencies**: Existing manager, Ghostel remote attachment, TRAMP, Dired, and optional Magit. Optional `tramp-rpc` 0.13.1 currently requires TRAMP 2.8.1.4 and msgpack 0.1.1.
**Observed Environment**: Emacs 31.1.50, TRAMP 2.8.2.31.1, installed `tramp-rpc` 0.13.1, and installed Magit from 2026-08-22.
**Storage**: In-memory Session intent and view records. Reuse existing layout persistence without persisting attempts, buffer ownership, worker objects, or new suppression history.
**Testing**: Existing ERT conventions and `./scripts/compile-and-test.sh` for implementation. Isolated batch and terminal Emacs experiments establish planning feasibility. An authorized remote smoke test remains an implementation acceptance gate.
**Target Platform**: Existing supported Emacs hosts and approved SSH destinations with an operator-managed compatible RPC server. Existing remote terminal support remains Ghostel-only.
**Project Type**: Emacs package, not a service or application server.
**Performance Goals**: Terminal interaction and unrelated Sessions continue during network waits. Health has a 30-second attempt deadline. Status preparation has no new fixed deadline.
**Constraints**: No software acquisition. No feature-induced shared-connection retirement. No remote I/O during ordinary restore, rendering, preference changes, or cleanup.
**Scale/Scope**: One active attempt per Session attachment. One feature writer per view identity. Independent view identities do not share a global preparation lock.

## Constitution Check

### Initial gate

| Principle | Decision | Result |
|-----------|----------|--------|
| I. Shared core, thin adapters | Reuse the existing status provider and layout commands. Add one remote lifecycle module. | PASS |
| II. Test-first correctness and full suite | Keep observable ERT coverage for cancellation, stale completion, closure, sharing, and cleanup. Run the required script during implementation. | PASS for planning |
| III. Optional integrations | Load RPC only on a permitted enabled-host attempt. Missing dependencies retain the terminal. | PASS |
| IV. Backend neutrality | Do not branch on Agent CLI type or change terminal dispatch. Keep the existing Ghostel remote boundary. | PASS |
| V. Compatibility and dependency justification | The user requested RPC. Dired still needs a remote file backend, so it cannot replace this optional dependency. Keep Emacs 28.1 paths unchanged. | PASS |
| VI. Local and remote workflow parity | Keep local provider selection, positions, focus rules, and `R` semantics. Limit differences to explicit remote constraints below. | PASS |

### Required remote differences

| Difference from the local path | Remote constraint |
|--------------------------------|-------------------|
| Separate disabled-by-default host preferences | Remote access and remote buffer cleanup need explicit consent. |
| Terminal appears before Project view | Network latency must not block terminal use. |
| Current-attempt health response and 30-second health deadline | Cached installation state does not prove a usable remote server. |
| Attempt-scoped no-provision and noninteractive authentication guards | Automatic display must not install software or request new credentials or host trust. |
| Cancellation and late-result ownership checks | Network results can arrive after detach, reset, or a Session switch. |
| Exact-host Worktree sharing and conservative cleanup | Equal-looking paths on different hosts do not establish common ownership. |
| Per-Session suppression survives reattach in memory | A remote terminal buffer can disappear while its remembered Session remains. |

### Post-design gate

No exception or baseline increase is requested. The post-design gate remains open because experiment E6 found incomplete client initialization after startup abandonment.

The technical review must resolve that startup path before this plan can authorize task generation. [research.md](research.md) records the evidence and its limits.

Implementation must not treat these planning experiments as an authorized remote smoke test. The full suite, real-host behavior, and live manager surface remain release gates.

## Project Structure

### Documentation for this feature

```text
specs/005-remote-rpc-magit/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── user-interface.md
│   └── execution.md
└── checklists/
    └── requirements.md
```

`tasks.md` belongs to the later `/speckit.tasks` command. This plan does not create it.

### Planned source changes

```text
claude-code-ide-manager.el          # Host options, display/reset seams, closure observations, detach boundary
claude-code-ide-remote-project.el   # New: preparation, scoped RPC guard, attempt/view ownership, cleanup
claude-code-ide-transient.el        # Manager action-menu cancellation entry
claude-code-ide-zmx.el              # Existing host-option docstring only, no transport change
claude-code-ide-tests.el            # Observable regression coverage
README.org                         # Existing user documentation, during implementation
```

**Structure Decision**: One new module separates a network-backed view lifecycle from manager rendering. Use direct functions, not callback registries or an event bus.

Keep the existing Session structure, zmx command runner, metadata transport, installed RPC sources, package configuration, and Agent definitions unchanged. Use the existing manager Session-ended notification to invalidate stale attachments. Do not attach Project-view cleanup to the generic exit path.

Update the existing host-option docstring to describe the enabled first-managed-display exception. Its current claim that navigation never connects needs that qualification.

## Design and Integration

### Preparation sequence

1. Confirm the Session is attached and its exact host remains approved and enabled.
2. Display the terminal through the existing manager path.
3. Restore a surviving requested view without remote I/O, or start a permitted preparation attempt.
4. Load and check the optional installed client inside the worker.
5. Start the health deadline before connection acquisition.
6. Run an uncached public `process-file` request for `true` in the intended `/rpc:` directory.
7. Resolve the view identity through remote file operations after successful health.
8. Serialize feature status preparation for that view identity.
9. Call the existing local status provider with no-window preparation bindings.
10. Publish the buffer only if the attempt still owns its attachment and view result.
11. Display it only if the frame still requests that Session beside its visible terminal.

A switch to another Session does not cancel preparation. It removes permission to alter that frame until the original Session becomes current again.

### Existing seams

| Existing symbol | Planned change |
|-----------------|----------------|
| `claude-code-ide-manager-switch-to-session` | Trigger first managed preparation after terminal display. After restore, insert a surviving ready view that never appeared, without remote I/O. |
| `claude-code-ide-manager--build-default-layout` | Keep disabled-host and local behavior. For enabled hosts, mirror the local content-window reset with an ordinary terminal window, not a side window. |
| `claude-code-ide-manager--capture-layout` / `--restore-layout` | Capture the view name in memory with its exact buffer object. Substitute its current name on restore, or reject an unverifiable saved layout. |
| `claude-code-ide-manager-reset-layout` | Invalidate the old attempt, clear this Session's suppression, reset the full layout, and request fresh health. |
| `claude-code-ide-manager--open-status-buffer` | Reuse its configured provider and Dired fallback. A private abandonment condition must bypass ordinary error fallback. |
| `claude-code-ide-manager-session-ended` | Invalidate the exact old attachment. Keep remembered Session suppression in memory. Do not perform Project-view cleanup. |
| `claude-code-ide-manager-detach-at-point` | Capture cleanup ownership before terminal cleanup. Apply cleanup only after explicit detach succeeds. |
| `claude-code-ide-manager-dispatch` | Add `C` for Cancel Project-view preparation. Keep `R`, `o`, `K`, `D`, and `X` unchanged. |

Before implementation changes an exported symbol, inspect its references with the available language server. If Emacs Lisp has no server, inspect all repository callers with `grep`.

### Cancellation and dependency safety

Use cooperative worker threads, not a main-thread timer around synchronous TRAMP calls. A main-thread timer owns the feature health deadline.

A private abandonment condition belongs to neither `error` nor `quit`. Invalidate the token immediately. Signal the worker outside admitted connection initialization.

During native initialization, defer signaling and use guarded server-start checkpoints. The client completes its own connection bookkeeping before the canceled attempt stops.

Release only the feature worker's stdout and stderr thread locks before its post-start checkpoint. Other RPC consumers must remain usable while that worker waits.

Keep worker diagnostics out of window management. Disable TRAMP's error-buffer pause locally, retain warning logs, and prevent automatic warning-window display.

Do not set the installed client's RPC timeout to 30 seconds. Its timeout handler retires a connection. See [contracts/execution.md](contracts/execution.md) for the scoped connection guard and cancellation boundary.

### Ordinary windows and surviving results

For enabled hosts, first managed display and `R` create the terminal-first layout through the local content-window path. Close stale side windows for that terminal.

Do not route this enabled-host default through the existing side-window terminal fallback. A normal `split-window` cannot split a side window.

Completion splits only the current Session's ordinary terminal window, on the side opposite the configured terminal position. It never resets the whole frame.

If the user moved the terminal into a side window or made the split impossible, keep the ready buffer undisplayed. Report that `R` restores the default arrangement.

After a terminal-only saved layout restores, insert any surviving requested ready view through this same local display helper. This covers results completed while another Session was current.

On restore, substitute the captured view name with the current name of its exact live buffer object throughout saved window references. Include previous/next-buffer references.

If the runtime view record is missing or its buffer died, reject that enabled-host saved layout and rebuild the terminal-first default. Suppression still controls replacement preparation.

### Closure and cleanup

Observe a real command's before/after layout state. Require a previously displayed view, the same current Session, and an unchanged manager layout epoch. Manager-driven layout changes advance that epoch. Killing a shared buffer marks only the initiating Session as closed.

Keep ownership conservative. An existing or uncertain custom buffer never becomes owned merely because the provider returned it. Resolve no remote paths during cleanup. Unknown sibling identity means retain the view.

## Requirement Coverage

| Requirements | Design authority | Acceptance path |
|--------------|------------------|-----------------|
| FR-001–FR-007 | Host options, optional loading, constitution gate, scoped client ownership | Disabled-host control and local regression checks |
| FR-008–FR-014, FR-018–FR-019 | Execution contract: admission, current health, guarded connection, abandonment | Current-response, acquisition, authentication, deadline, and cancellation cases |
| FR-015–FR-017 | Existing provider/fallback and manager `R` | Magit, Dired, custom provider, and supersession cases |
| FR-020–FR-030 | Session intent, shared view key, frame epoch, and buffer-object restore | First display, bulk attach, sharing, focus, closure, reattach, and restore cases |
| FR-031 | Existing provider, VC, and cache configuration remain authoritative | Configuration before/after comparison |
| FR-032–FR-033 | Attempt/attachment identity and separate frame display permission | Late completion, Session switch, host removal, and newer attachment races |
| FR-034–FR-040 | Explicit-detach snapshot and conservative local eligibility | Complete cleanup matrix and zero remote-query/connection-cleanup observation |

## Verification Plan

| Observable contract | Verification |
|---------------------|--------------|
| Disabled hosts do nothing | ERT: startup, render, restore, preference changes, and bulk attach make no new RPC/provider calls. |
| Current health and no provisioning | ERT at the dependency boundary, then a real-host request with acquisition entry points observed. Test missing server and reconnect. |
| Responsive and safe cancellation | ERT with a delayed transport, then terminal interaction during real delayed health/status. Verify another RPC consumer remains usable. |
| Correct provider and view sharing | ERT plus Magit, non-Git Dired, custom provider, and different-subdirectory smoke cases. |
| No stale display or focus theft | ERT for reset/detach/host removal races. Live checks with terminal, manager, and another window selected. |
| Manual closure is per Session | ERT for real command-loop window dismissal and buffer killing. Include never-displayed results and ordinary switches. |
| Conservative explicit-detach cleanup | ERT for created, reused, modified, shared, source-file, and unknown-ownership buffers. Assert no remote query or connection cleanup. |
| Local behavior remains intact | Existing local layout/provider tests and the full compile-and-test script. |

[quickstart.md](quickstart.md) gives the implementation acceptance procedure. Do not write tests that only assert source text, forwarding, or incidental wording.

## Complexity Tracking

No constitutional violation needs an exception.

| Necessary complexity | Why it is needed | Simpler alternative rejected |
|----------------------|------------------|-----------------------------|
| One remote lifecycle module | Attempts outlive individual terminal displays and share view buffers. | More conditionals inside rendering would mix network ownership with layout state. |
| Scoped installed-client connection adapter | `auto-deploy=nil` still permits artifact acquisition. Buffer-local settings can override an outer dynamic binding. | Global deployment changes would affect unrelated RPC users. |
| Per-view feature writer serialization | Two Sessions may prepare the same shared buffer. | A global worker lock would delay unrelated views. |
| Command snapshot plus layout epoch | An absent window alone does not prove user dismissal. | Buffer-local suppression would disappear on reattach and affect the wrong shared Session. |
