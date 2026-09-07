# Research: Remote RPC Project Views

**Date**: 2026-09-06
**Scope**: Read-only source research and isolated local experiments. No remote host connection, server installation, source change, or live Emacs reload occurred.

## Decisions

### R1. Use the installed client, not the reference checkout

**Decision**: Soft-load the installed `tramp-rpc` package at the first permitted preparation attempt.

**Rationale**: The user owns package installation and server selection. The sibling source checkout is reference material, not a runtime dependency.

**Evidence**: A separate `emacs --batch -Q` process loaded the installed package and Magit. It reported Emacs 31.1.50 and TRAMP 2.8.2.31.1. The client header declares version 0.13.1 and requires Emacs 30.1, msgpack 0.1.1, and TRAMP 2.8.1.4.

**Alternatives rejected**: Add the checkout to `load-path`, vendor the client, auto-install it, or raise the package's Emacs baseline.

### R2. Use a worker thread and an attempt-owned deadline

**Decision**: Perform connection acquisition, health, identity resolution, and status preparation in a cooperative Emacs worker. Keep display changes on the main thread.

**Rationale**: The installed synchronous RPC wait uses `accept-process-output` with external timers suspended. Calling it from a later main-thread timer still blocks normal interaction.

**Evidence**: `tramp-rpc-transport.el:1779-1908` contains the wait and timeout paths. Isolated experiments exercised the actual installed synchronous request function against a stalled local pipe. Main-thread timers continued for both main-created and worker-created transports.

A newly created process belongs to its creator thread until that thread exits or releases it. Release owned stdout and stderr locks after successful native startup.

Use `set-process-thread` with nil only when the current feature worker owns the process. E8 proves another consumer can use the transport while that worker remains alive.

**Boundary**: Cooperative threads do not preempt arbitrary CPU-bound user Lisp. The provider must follow the existing directory-to-buffer contract and allow normal Emacs wait points. Do not claim safety for a custom provider that starts unmanaged work or directly changes unrelated windows.

**Alternatives rejected**: A main-thread timer, `with-timeout` around a blocking provider, a second Emacs process that reconstructs Magit buffers, and a replacement RPC transport.

### R3. Separate abandonment from `quit` and from client timeout

**Decision**: Use a private condition outside both the `error` and `quit` condition families. Invalidate immediately, but defer signaling during already admitted connection initialization.

**Rationale**: Ordinary errors trigger the local provider's Dired fallback. `quit` triggers installed-client connection retirement. A private abandonment condition must do neither.

**Evidence**:

- `tramp-rpc-transport.el:682-699` releases pending IDs on every nonlocal exit, but retires the generation specifically on `quit`.
- `tramp-rpc-transport.el:1245-1270` also catches startup `error` and `quit` for transport cleanup.
- `tramp-rpc-transport.el:1888-1897` retires the generation on its own RPC timeout.
- The full-call experiment verified that the private condition bypasses an outer `(error quit)` handler and leaves the pipe live.

Use the condition pattern below, not `define-error` with its default `error` parent:

```elisp
(put 'claude-code-ide-remote-project-abandoned
     'error-conditions '(claude-code-ide-remote-project-abandoned))
(put 'claude-code-ide-remote-project-abandoned
     'error-message "Project-view preparation canceled")
```

The feature's 30-second timer must not alter `tramp-rpc` timeout variables. A natural client timeout remains a transport event, not a feature cancellation mechanism.

Guard both `tramp-rpc--connect` and `tramp-rpc--start-server-process` at entry and completion. Convert a stale return or error to private abandonment before provider fallback.

If cancellation occurs during authentication, the server-start entry checkpoint prevents a new RPC process. Let the admitted authentication operation finish under its native timeout.

If server startup already entered its readiness wait, let the original client finish its handshake and connection bookkeeping. Then abandon before further feature requests.

This avoids both connection retirement and partially initialized live generations. Do not synthesize connected properties or connection-local settings in the feature.

E6 disproved immediate signaling during initial startup. E8 and E10 verified the guarded completion alternative. The feature still reports abandonment at its own deadline.

**Alternatives rejected**: `keyboard-quit`, signaling `quit`, deleting the RPC process, TRAMP connection cleanup, or setting the RPC call timeout to the feature deadline.

### R4. Guard connection creation without changing binary selection

**Decision**: Guard binary selection at `tramp-rpc--connect`, only for an owned preparation worker and its exact target. Add the server-start checkpoints described in R3.

Determine the client's normal selection before applying the guard:

| Effective normal configuration | Selected binary |
|--------------------------------|-----------------|
| `tramp-rpc-deploy-never-deploy` is nil | `tramp-rpc-deploy-expected-binary-localname` |
| Never-deploy is non-nil and an explicit path exists | That explicit path |
| Never-deploy is non-nil with no explicit path | `tramp-rpc-deploy-binary-name` |

Within that connection call, bind never-deploy to `t` and remote-binary-path to the selected value. Repeat this guard on reconnect. Do not alter global or saved values.

**Rationale**: An outer dynamic binding alone does not cover arbitrary buffer-local overrides. The connection boundary is the narrow place where the installed client chooses deployment behavior.

**Evidence**:

- `tramp-rpc-deploy.el:1274-1282` computes the normal expected path without network access.
- `tramp-rpc-deploy.el:1284-1378` shows that `auto-deploy=nil` can still obtain a local artifact for checksum comparison.
- Its never-deploy branch returns the selected path without artifact acquisition.
- `tramp-rpc-transport.el:1344-1391` selects the never-deploy connection branch without the normal missing-binary deployment fallback.
- The isolated failure-path experiment executed this branch twice for each normal selection case. Forbidden acquisition and transfer sentinels did not fire.

**Alternatives rejected**: Set only `auto-deploy=nil`, force a new binary path, change deployment defaults globally, or temporarily replace the client package.

### R5. Require an actual response through a public operation

**Decision**: Run `(process-file "true" nil nil nil)` with the intended `/rpc:` directory as `default-directory`. Require exit status zero.

**Rationale**: This request checks the server's usable process interface and working-directory access without requiring Git. A cached directory predicate cannot establish current health.

**Evidence**: `tramp-rpc.el:2185-2301` routes uncached `process-file` operations through `process.run`. Its Magit process cache only serves eligible Git operations. A `true` request therefore requires a response in the current attempt.

A missing basic POSIX command or inaccessible directory is a health failure with guidance. Do not fall back to scp, ssh shell parsing, zmx metadata commands, or cached installation records.

**Alternatives rejected**: Cached `system.info` helpers, package/deployment records, `file-directory-p` alone, or zmx control-command success.

### R6. Keep authentication noninteractive and no less strict

**Decision**: For owned connection attempts, prepend `-o BatchMode=yes` and `-o StrictHostKeyChecking=yes` to the effective raw SSH arguments. Preserve the remaining arguments and global settings.

**Rationale**: Automatic view preparation must not ask for credentials or add host trust. The user can establish credentials or trust separately, then use `R`.

**Evidence**: `tramp-rpc-transport.el:1012-1035` and `1115-1135` place raw SSH arguments before the client's defaults. The source explicitly documents OpenSSH's first-value precedence.

The installed client currently defaults to `StrictHostKeyChecking=accept-new`. Merely preserving that default would allow first-use trust changes during automatic preparation. A stricter per-attempt argument is therefore necessary.

Reuse an already established client connection when the client normally does so. Do not change SSH aliases, identity files, proxy routes, or connection-sharing ownership.

Apply the SSH argument binding around the whole native connection call, including first ControlMaster establishment. A binding only around server startup misses authentication.

Bind `tramp-error-show-message-timeout` to nil throughout worker work. This prevents the login-error path from selecting a buffer, discarding input, or pausing.

The error still reaches the feature's main-thread guidance path. Keep global settings and `tramp-verbose` unchanged. E9 verifies this diagnostic boundary.

**Alternatives rejected**: Accept a new key automatically, request passwords from a background view, disable host-key verification, or replace authentication with the zmx transport.

### R7. Reuse the local provider without using its display side effects

**Decision**: Call `claude-code-ide-manager--open-status-buffer` inside the worker. Bind Magit's no-window controls during preparation.

```elisp
(let ((magit-display-buffer-function #'ignore)
      (magit-display-buffer-noselect t)
      (warning-minimum-level :emergency))
  (claude-code-ide-manager--open-status-buffer directory))
```

**Rationale**: The manager already owns the provider selection and Dired fallback. The worker must not select or replace windows while waiting for remote data.

**Evidence**:

- `claude-code-ide-manager.el:126-135,3338-3354` defines the directory-to-buffer customization and fallback.
- Installed `magit-mode.el:664-726` displays the buffer before refreshing it. The no-select variable prevents use of a nil display window.
- An initial experiment with only `magit-display-buffer-function=ignore` failed with `window-live-p, nil`.
- Adding `magit-display-buffer-noselect=t` let actual installed Magit prepare a local status buffer without changing the window state.
- Magit's remote Git warning uses `display-warning`, outside its normal display function.
- E9 verifies that the warning threshold prevents that window while normal warning logging remains available.

Bind `inhibit-interaction` to `t` for worker work. Keep `warning-minimum-log-level` unchanged. An interactive provider follows the existing error/fallback path without opening a prompt.

Do not change user VC exclusions, project-cache settings, Magit refresh settings, or the configured provider globally. Unknown custom buffer ownership remains ineligible for cleanup.

**Alternatives rejected**: Hard-code Magit, bypass Dired fallback, call the provider on the main thread, or restore an old window configuration after a long worker operation.

### R8. Separate view identity from Session identity

**Decision**: Use `(exact-host git worktree-root)` or `(exact-host directory directory-path)` for view sharing. Keep Session keys and directory metadata unchanged.

Resolve `.git` ancestry through public remote file operations after health. Both a `.git` directory and a linked Worktree's `.git` file identify a Git root. Canonicalize only within permitted remote preparation.

**Rationale**: Sessions in different subdirectories of one Worktree need the same view. Host aliases must not collapse into one ownership domain.

Serialize feature writers per resolved view identity. A Session switch does not cancel the writer. Each requesting Session keeps independent display intent and suppression.

**Alternatives rejected**: Directory-keyed Sessions, host-name normalization through DNS, global writer serialization, or shared manual-close state.

### R9. Detect closure through command history, not absence

**Decision**: Use public `pre-command-hook` and `post-command-hook` observations with a per-frame manager layout epoch.

Before a command, record the current Session, visible terminal, actual displayed Project-view buffer, and epoch. After the command, mark suppression only if that same view disappeared without a Session or epoch change.

Manager switches, reset, detach, layout restore, and asynchronous display advance the epoch. They therefore cannot count as manual closure. A pending view that never appeared has no before-command display record.

**Evidence**: An isolated command-loop prototype used real `C-x 0`, `C-x k RET`, and manager-like commands through `execute-kbd-macro`. It distinguished window dismissal, shared-buffer killing, Session switches, pending results, and reset.

A buffer-local kill hook may invalidate the shared buffer record. It must not mark every sharing Session as manually closed. Session suppression stays in memory across reattach, not in terminal buffer-local state or a new cross-restart store.

**Alternatives rejected**: An absent window alone, one closure hook per sharing Session, buffer-local suppression, or persistent closure history.

### R10. Clean up only at the explicit detach boundary

**Decision**: Capture ownership before `claude-code-ide-manager-detach-at-point` removes the terminal. Apply eligible cleanup only after detach succeeds.

**Evidence**: `claude-code-ide-manager.el:3643-3685` is the explicit detach command. It can invoke generic exit handling and then remove a remote row.

Preserve buffers unless all eligibility facts are already known. A same-host attached Session with unknown project identity prevents an exclusivity claim. Source-file buffers never enter the candidate set.

**Alternatives rejected**: Generic kill/exit cleanup, project-directory buffer sweeps, remote identity resolution during detach, or shared-connection cleanup.

## Experiments Run

Each experiment ran in a separate Emacs process under a temporary directory. Most used batch mode. E7 also used an isolated terminal Emacs.

The temporary scripts did not load the live user profile or change the application checkout. No experiment connected to a remote host.

### E1. Pending wrapper and local Magit

Final run exited zero:

```text
RPC_WRAPPER_PROBE ticks=31 main-process-echoes=31 canceled=t shared-pipe-live=(run open listen connect stop) pending-ids=nil
LOCAL_MAGIT_THREAD mode=magit-status-mode window-state-unchanged=t ticks-during=1
```

The pipe was a local `cat` process, not an RPC server. The echo count proves main-thread process output continued during the worker wait. The Magit case used a temporary local Git repository.

### E2. Actual installed synchronous call and deployment failure branches

Final run exited zero:

```text
FULL_RPC_CALL creator=main ticks=32 abandoned=t error-or-quit-caught=nil pipe-live=t pending=nil
FULL_RPC_CALL creator=worker ticks=42 abandoned=t error-or-quit-caught=nil pipe-live=t pending=nil
NO_PROVISION case=normal reconnects=2 selected="~/.cache/emacs/tramp-rpc/tramp-rpc-server-git-1269309ca25f-772de39e5d4d" acquisition=0
NO_PROVISION case=bare reconnects=2 selected="tramp-rpc-server" acquisition=0
NO_PROVISION case=explicit reconnects=2 selected="/operator/server" acquisition=0
DEPLOY_SETTINGS unchanged=t
```

The request case called installed `tramp-rpc--call` against a deliberately stalled local pipe. It exercised request encoding, pending-ID tracking, the installed wait loop, and nonlocal cancellation.

The deployment case used the actual connection/deployment branch with SSH startup replaced by a synthetic missing-server error. It did not establish real SSH connectivity or real server compatibility.

### E3. Observable closure

The command-loop prototype exited zero:

```text
CLOSURE window-dismissal=A-only
CLOSURE ordinary-session-switch=not-closed
CLOSURE reset-and-never-displayed-pending=not-closed
CLOSURE shared-buffer-kill=A-only; sibling=B-can-recreate
CLOSURE reattach-state=A-still-suppressed
CLOSURE explicit-reset=cleared
```

This proves the observation rule in a real Emacs command loop. It does not claim that the feature's manager integration already exists.

### E4. Late responses and reuse after worker exit

A local framed-response fixture exercised the installed filter and request function after abandonment. The run exited zero:

```text
REUSE late-response-discarded=t second-main-thread-rpc=t pipe-live=t process-thread=nil
```

The installed filter discarded the old request's response. A new main-thread RPC call then succeeded on the same transport after its creator worker exited.

The fixture synthesized protocol responses through a local pipe. This proves client transport reuse, not a real server's compatibility.

### E5. Buffer-local configuration and initial authentication guard

A prototype around-connection adapter ran before the original installed connection function. It covered four worker connection calls across normal and explicit-path buffer-local configurations.

The actual installed ControlMaster function built its arguments with no existing socket. A local process fixture replaced SSH, so no authentication or network access occurred.

The run exited zero:

```text
SCOPED_GUARD worker-reconnects=4 normal-selection="~/.cache/emacs/tramp-rpc/tramp-rpc-server-git-1269309ca25f-772de39e5d4d" explicit-selection="/operator/selected"
AUTH_MASTER no-existing-socket=t owned-first-strict=yes owned-batch=yes unrelated-original=t global-settings-unchanged=t
```

This confirms that binding raw arguments around the whole connection function also covers the initial ControlMaster call. A server-start-only binding would be too late.

A separate local `ssh -G` check confirmed first-value precedence without connecting:

```text
SSH_CONFIG_ONLY batchmode=yes stricthostkeychecking=true connection-attempted=no
```

### E6. Initial startup abandonment exposes incomplete initialization

An isolated experiment called the actual installed `tramp-rpc--start-server-process`. A local pipe replaced SSH, while the normal connection registry and startup handler remained active.

The worker abandoned its initial `system.info` wait. The experiment exited zero with:

```text
STARTUP_ABANDON generation-retained=t pipe-live=t pending=nil connected-property=missing profile-value=nil
```

The private condition avoided connection retirement. However, it also bypassed the startup code that applies connection-local profiles and records TRAMP's connected properties.

The installed `--ensure-connection` fast path then sees a live registered transport. It does not finish the skipped startup steps.

This disproved immediate startup signaling. A live pipe alone does not prove complete client initialization. E8 resolves the gap through guarded native completion.

### E7. Scheduling and native keyboard quit

The installed wait continued to yield with both tested polling intervals:

```text
SCHEDULING poll=0 main-ticks-before-worker-finished=34 worker-owned-during=t owner-after=nil
SCHEDULING poll=0.01 main-ticks-before-worker-finished=36 worker-owned-during=t owner-after=nil
```

An isolated terminal Emacs then received a real `C-g` while the worker waited in the installed RPC call:

```text
QUIT-RESULT main-command=t worker-quit=nil retire-called=nil worker-live=t
```

The main command loop received quit. The worker did not receive `quit` or retire its transport. No extra polling or keyboard-quit workaround is justified.

### E8. Complete native startup and release process ownership

The prototype guarded the actual installed server-start function. Local process fixtures supplied its response or exercised its existing timeout. The run exited zero:

```text
STARTUP_FINISH canceled=t native-connected=t native-profile=configured feature-next-phase=nil
UNLOCKED_REUSE worker-alive-on-mutex=t stdout-owner=nil stderr-owner=nil other-main-rpc=t feature-requests-after-cancel=0
STARTUP_PRECHECK invalid-token=t new-process=0 frames=0
STARTUP_NATIVE_TIMEOUT canceled=t native-timeouts=1 provider-next-phase=nil generation-removed=t
```

The successful canceled startup completed native connected properties and connection-local profiles. The feature did not enter its next phase.

The worker then remained alive on a mutex. Both transport processes were unlocked, and another main-thread RPC call succeeded on the same connection.

An invalid pre-entry token created no process or request. A missing response triggered the client's natural timeout and cleanup, not feature retirement.

### E9. Suppress worker diagnostic windows without hiding errors

The experiment exercised the installed TRAMP error function and Magit's remote Git warning path in an isolated Emacs:

```text
ERROR_DISPLAY guarded=nil pop=1 discard=1 pause=1 condition=remote-file-error
ERROR_DISPLAY guarded=t pop=0 discard=0 pause=0 condition=remote-file-error
MAGIT_WARNING guarded=nil windows-added=1 warning-logged=t provider-error=error
MAGIT_WARNING guarded=t windows-added=0 warning-logged=t provider-error=error
DIAGNOSTIC_SETTINGS unchanged=t
```

The TRAMP binding removed the popup, input discard, and display pause. It preserved the same error condition.

The provider warning threshold prevented the warning window. The warning still reached `*Warnings*` under the unchanged logging policy.

These are actual diagnostic functions with local failure fixtures, not a real SSH authentication or remote Git test.

### E10. Cancel during native authentication without starting RPC

The experiment used the installed connection and ControlMaster functions with a local authentication-process fixture. It canceled while that native process was pending.

```text
AUTH_FINISH canceled=t native-auth-completed=t auth-process-retained=t rpc-starts=0 generations=0
```

The run exited zero. Native authentication completed without feature-induced process retirement. The server-start admission checkpoint prevented any RPC process or registered generation.

## Evidence Limits and Implementation Gates

The experiments establish the selected primitives, not the completed feature. No real server was contacted. No remote delay, disconnection, or real Magit-over-RPC scenario ran.

Implementation must exercise the complete guarded path against an authorized server. It must also test cancellation during connection startup, provider fallback, identity resolution, and shared-buffer preparation. Preserve ordinary client timeout behavior in those checks.

The full compile-and-test script was not run for this document-only change. It byte-compiles application files in the shared checkout. Run it after implementation, when that work is authorized.

No product clarification remains open. E8 resolves E6's startup gap. The real-host scenarios remain implementation acceptance gates, not authorization to run them now.

## Primary Source Locations

Repository evidence uses the current checkout:

- `claude-code-ide-manager.el`: provider, layout, first-managed display, reset, and detach.
- `claude-code-ide-transient.el:668-701`: manager action menu. `C` is free in this menu.
- `.specify/memory/constitution.md`: version 1.1.0, especially principles III, V, and VI.

Installed-client evidence uses:

```text
/Users/fuyu0425/.emacs.d.spacemacs-32/elpa/31.1/develop/tramp-rpc/lisp/
/Users/fuyu0425/.emacs.d.spacemacs-32/elpa/31.1/develop/magit-20260822.1158/
```

Additional diagnostic evidence comes from installed `tramp-message.el:417-457` and Magit's `magit-git.el:746-809`.

Line numbers are research anchors, not a dependency on those exact installation paths. Implementation must check the installed client's required interfaces before enabling the adapter.
