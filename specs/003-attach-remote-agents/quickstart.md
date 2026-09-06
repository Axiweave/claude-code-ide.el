# Quickstart Validation: Attach Remote Agents

**Status**: Implementation, repository gate, and all five live workflows pass on stock zmx across two hosts (`ramhorn` zmx 0.8.0, `vps` zmx 0.8.1 with omp built from the fork). vterm and Eat are out of scope: the user is deprecating them.

**Interfaces**: [Remote access contract](contracts/remote-sessions.md)
**State rules**: [Data model](data-model.md)
**Attach guard**: [Stock zmx attach guard](contracts/zmx-attach-guard.md)

## Safety and Prerequisites

Use disposable Agent sessions for every Stop and failure scenario. Never use a production Agent session for destructive validation.

Prepare these prerequisites:

1. Confirm stock zmx runs on each test host. No patch or minimum version is required.
2. Configure passwordless SSH and trusted host keys outside this feature.
3. Install a supported Agent on each test host.
4. Prepare a disposable Emacs instance with this package and its existing dependencies.
5. Select Ghostel through the existing terminal-backend configuration.
6. Replace the example host aliases with two personal test hosts.
7. Use a fresh zmx test-session name if an example name already exists.

Keep the same test-session name and project basename across both remote hosts. This deliberately tests host identity collisions.

The examples use `ramhorn`, `other-personal-host`, the project `/tmp/cci-remote-validation`, and the session `cci-remote-validation`.

## Verify Stock Zmx

Inspect the remote binary and confirm the attach guard behavior in an isolated socket directory:

```bash
ssh -T -n -o BatchMode=yes -o StrictHostKeyChecking=yes -o RemoteCommand=none ramhorn 'zmx version'
ssh -T -n -o BatchMode=yes -o StrictHostKeyChecking=yes -o RemoteCommand=none ramhorn 'd=$(mktemp -d); ZMX_DIR=$d ZMX_SESSION= zmx attach cci-probe-gone false </dev/null >/dev/null 2>&1; echo exit=$?; ZMX_DIR=$d zmx list --short; rm -rf $d'
```

Expected: `exit=1` and an empty list. Repeat for the second host.

## Prepare Disposable Agents

Start a test Agent manually on each host. These setup commands intentionally create test sessions. The Emacs remote feature must never perform this creation.

```bash
ssh -t -o BatchMode=yes -o RemoteCommand=none ramhorn 'mkdir -p /tmp/cci-remote-validation && cd /tmp/cci-remote-validation && exec env -u ZMX_SESSION -u ZMX_SESSION_PREFIX zmx attach cci-remote-validation omp'
```

```bash
ssh -t -o BatchMode=yes -o RemoteCommand=none other-personal-host 'mkdir -p /tmp/cci-remote-validation && cd /tmp/cci-remote-validation && exec env -u ZMX_SESSION -u ZMX_SESSION_PREFIX zmx attach cci-remote-validation omp'
```

Use another configured Agent command if `omp` is unavailable. Detach the setup client with zmx's client-only `Ctrl-\` shortcut. Do not use `zmx detach`, which affects all clients.

Prepare one local Agent through the package's existing local workflow. Do not require a local checkout matching the remote directory.

## Run Repository Verification

From the package repository root:

```bash
./scripts/compile-and-test.sh
```

Run the remote behavioral regressions with the same dependency load paths as the repository script:

```bash
emacs -batch -L . -l claude-code-ide-tests.el --eval '(ert-run-tests-batch-and-exit "remote")'
```

The targeted run must execute actual remote-feature regression cases. A run with zero selected tests is not evidence.

Use a fresh disposable Emacs after record-layout changes. This avoids treating old in-memory records as the new Session or manager-item shape.

In that Emacs, evaluate:

```elisp
(setq claude-code-ide-remote-hosts '("ramhorn" "other-personal-host")
      claude-code-ide-manager-persist-state t)
```

## Walkthrough 1: Discover and Attach

1. Start a stopwatch when you request `C-u M-x claude-code-ide-attach`.
2. Select `ramhorn`.
3. Select its disposable Agent.
4. Stop the stopwatch when the terminal accepts input.
5. Submit a short prompt and observe the response.
6. Record the elapsed discovery-to-attachment time.

Expected outcomes:

- Usable attachment takes at most 60 seconds under the stated prerequisites.
- The original Agent continues without a restart.
- The terminal works without a connection to current Emacs tools.
- The SSH client explicitly requests a PTY with `-t`.
- No other configured host receives automatic discovery requests.

Repeat with SSH configuration that does not set `RequestTTY`. Repeat through `C-u M-x claude-code-ide-attach-select` to exercise marked selection.

For an unrecognized wrapper command, verify that bulk attach skips and names it. Individual attach must permit existing manual Agent identification.

## Walkthrough 2: Use the Global Manager

1. Attach the disposable Agent on the second host.
2. Open the existing global manager.
3. Select each local and remote row.
4. Rename and pin one remote row.
5. Refresh the manager.
6. Select the same remote target through discovery again.

Expected outcomes:

- Both remote rows include their host labels despite identical project and zmx names.
- Input, rename, pin, and lifecycle actions affect only the intended Session.
- The second attachment attempt reuses its row and terminal.
- Remote selection does not open local Magit, Dired, or Treemacs for the remote path.
- The local Agent remains usable.

## Walkthrough 3: Disconnect and Reattach

1. Leave a remote terminal quiet for the existing output-idle interval.
2. Confirm output-idle behavior without treating it as Agent completion.
3. End only that SSH client with its escape sequence: press Return, then `~.`.
4. Wait for the connection to report its end.
5. Refresh the manager and select the disconnected row.
6. Invoke the explicit reattach action with `c`.

Expected outcomes:

- The disconnected row survives refresh and ordinary selection.
- Its output-idle and working indicators clear after detected connection failure.
- Ordinary selection does not connect.
- One explicit reattach restores the same Agent and row.
- The manager does not add a duplicate or restart work.

For the missing-target case, close the disposable target's terminal buffer to retain its row.
Stop that exact test target from its setup terminal.
Then request reattach in Emacs.

```bash
ssh -T -n -o BatchMode=yes -o RemoteCommand=none ramhorn 'env -u ZMX_SESSION -u ZMX_SESSION_PREFIX zmx kill cci-remote-validation'
ssh -T -n -o BatchMode=yes -o RemoteCommand=none ramhorn 'env -u ZMX_SESSION -u ZMX_SESSION_PREFIX zmx list --short'
```

Expected: reattach reports the missing target, retains the row, and creates no replacement. Restore the disposable test Agent manually before later workflows.

The upstream deterministic race regression must also pass. This manual missing-target case does not replace that race check.

## Walkthrough 4: Restore and Move Between Computers

1. Attach both remote test Agents with manager persistence enabled.
2. Exit the disposable Emacs normally.
3. Start that Emacs profile again.
4. Open and refresh the manager without requesting attachment.
5. Reattach one row explicitly.
6. Discover the same Agent from a second computer's Emacs.

Expected outcomes:

- Every remembered remote row returns disconnected.
- Restoration and refresh make zero remote requests.
- Host labels, names, ordering, pins, and valid local layout choices survive.
- Reattach reuses the remembered Session ID.
- The second computer reaches the same Agent without history synchronization or forced client detachment.

Repeat the restart with persistence disabled. No remote history should load into the later Emacs.

## Walkthrough 5: Confirm Detach and Stop

Use two clients attached to the same disposable remote Agent.

1. Close one Emacs terminal buffer.
2. Confirm that the other client remains usable.
3. Select the remembered target in the manager.
4. Request Stop with `K`.
5. Check the host, zmx name, and all-client warning.
6. Cancel the confirmation.
7. Confirm that the Agent still runs.
8. Request Stop again for that same disposable target.
9. Confirm the exact target.
10. Observe the result from the other client.

Expected outcomes:

- Closing a buffer detaches only its client.
- Canceling sends zero kill requests.
- A confirmed successful Stop terminates the selected target for both clients.
- The manager removes the target only after verified success.
- Other local and remote targets remain usable.

If the Stop response is lost or verification fails, the manager must report an unconfirmed result. It must retain the row and avoid another kill request.

## Failure and Compatibility Checks

- Remove a remembered host from the configured list. Verify that its row remains and new remote actions require configuration restoration.
- Use an unreachable configured destination. Verify that its request fails without freezing local sessions or another host's terminal.
- Reattach a remembered target that no longer exists. Verify an error before terminal creation, a retained disconnected row, and no replacement.
- For a target that disappears after discovery or the reconnect check, verify that the `false` guard leaves no running session.
- Exercise valid session names containing spaces and shell punctuation through a disposable test session.
- Verify that local reattach uses the guarded command without changing ordinary local Agent creation.
- Verify that remote attachment works without a local zmx installation.
- Exercise rejected option, prefix, current-session, and path-like names without sending remote actions.
- vterm and Eat are out of scope for remote attachment (scheduled for deprecation). They must report the limitation explicitly.
- Confirm that remote Sessions do not receive local MCP state when local and remote zmx names collide.
- Confirm that remote title changes do not cause automatic SSH or local zmx writes.

## Required Regression Evidence

Keep small behavior-focused ERT cases for these uncertain paths:

- Disconnect, refresh, persistence reload, and explicit reattach preserve one target.
- An old process sentinel or buffer kill hook cannot remove a newer attachment.
- Host/name collisions cannot redirect selection, Stop, or local MCP association.
- Remote paths never invoke local project operations or local Agent PID inspection.
- Missing targets fail with the exit guard and never leave a shell or Agent behind.
- Stop cancellation and unconfirmed replies never claim success or retry a kill.
- Verified Stop removes the target for both sentinel-first and control-callback-first ordering, including a later refresh.
- A late Stop or client callback cannot erase a newer attachment or restore a stopped row.
- In-memory disconnected rows survive when persistence is disabled.

## Record the Result

Record the zmx build, terminal backend, elapsed attachment time, and pass/fail result for each primary workflow. All five workflows must complete through editor controls after setup.

Do not count Agent response-generation time toward the 60-second attachment target. Record failures without replacing them with mock or source-text checks.

## Recorded Implementation Result — 2026-09-05

Stock zmx only. The earlier patched checkout under `/Users/fuyu0425/tools/zmx` is no longer part of this feature. The installed local zmx is 0.7.1 and `ramhorn` runs 0.8.0. Both passed the isolated `attach NAME false` missing-target probe with `exit=1` and no session.

The final `./scripts/compile-and-test.sh` run completed successfully:

```text
Byte-compilation check passed.
Ran 655 tests, 646 results as expected, 0 unexpected, 9 skipped.
ERT duration: 20.362578 seconds.
Total command duration: 23.01 seconds.
```

The compiler reported warnings in existing test fixtures and installed dependencies. Native compilation was not requested. The script removed generated `.elc` and `.eln` files.

The focused remote and zmx run passed 70 tests, including the stock attach guard wrapper, zmx 0.8 discovery rows, the blank last-target short list, repeated persisted saves, both Stop callback orders, disconnected Stop, stale ownership, explicit reattach, and passive restoration.

The nine skipped tests were:

- `claude-code-ide-mcp-server-test-ws-send-fix`
- `claude-code-ide-test-concurrent-sessions`
- `claude-code-ide-test-flymake-diagnostics`
- `claude-code-ide-test-open-file-text-patterns`
- `claude-code-ide-test-run-existing-session`
- `claude-code-ide-test-run-with-cli`
- `claude-code-ide-test-stop-with-session`
- `claude-code-ide-test-toggle-window-functionality`
- `test-claude-code-ide-mcp-multi-session-deferred`

### Live Ramhorn Result

The user authorized non-destructive testing on `ramhorn` and prohibited killing its running Agent. A fresh batch Emacs loaded this package and the Ghostel backend and ran the real feature code:

- `claude-code-ide-zmx-discover-remote` returned the one running session in 0.10 seconds. It parsed the zmx 0.8.0 row, including `cwd=file://ramhorn/home/yufu/SAGA-sdk` as `:start_dir`.
- `claude-code-ide--attach-zmx-entry` produced a live `ghostel-mode` buffer in 4.2 seconds. A read-only `zmx list` during the attachment reported `clients=2`.
- Killing the buffer detached only. `zmx list` afterward reported `clients=1` and the same PID `411529`. The manager retained the remembered row.
- No Agent input, Stop, or kill ran.

### Live Lifecycle Result — 2026-09-06

The user provided the disposable target `cci-omp-repo-bsY2O4` on `ramhorn` (stock zmx 0.8.0). Two fresh batch Emacs runs with Ghostel and a temporary persist directory ran the real feature code. Remote requests were counted through advice on `claude-code-ide-zmx--call-remote`.

Run 1:

- Discovery in 0.11 s. Attach in 5.2 s. `zmx list` showed `clients=2` during attachment.
- Killing the buffer detached only: `clients=1`, same PID `991319`, remembered row retained with host `ramhorn`, live flag nil.
- Explicit reattach in 5.0 s reused the same Session ID.
- `claude-code-ide-manager-refresh-all` made zero remote requests. The whole run made one request: `list`.
- The manager state was saved to disk.

Run 2 (fresh Emacs):

- Load and refresh restored one disconnected row with host `ramhorn` and zero remote requests.
- Explicit reattach reused the remembered Session ID.
- A canceled Stop sent zero requests and kept the row.
- A confirmed Stop sent exactly `kill cci-omp-repo-bsY2O4` then `list --short`, removed the Session and row in 1.05 s, and left `cci-omp-saga-sdk-1lEr7U` untouched.

Run 3: an explicit reattach to the now-missing target exited through the `false` guard, kept the disconnected row, and left no session on the host.

Two defects surfaced only in these live runs and are fixed with regressions:

- Stock `zmx list --short` prints nothing for an empty list. The parser rejected blank output, so a Stop of the last target would have reported unconfirmed.
- `claude-code-ide-manager--save-state` re-registered the persist default to the current value on every call. `persist-save` deletes the file when the value equals the default, so any second unchanged save deleted the state.

Batch Ghostel does not render terminal output. The user then confirmed interactive input and output through `C-u M-x claude-code-ide-attach` in a live Emacs after the changed files were loaded and existing Session records were migrated to the new `host` slot.

### Live Acceptance Result

On 2026-09-06 the two-host walkthroughs ran on the user's live Emacs against `ramhorn` and `vps`, plus a second disposable Emacs for the second-computer step. vterm and Eat are out of scope.

| Criterion | Automated evidence | Live acceptance |
|-----------|--------------------|-----------------|
| SC-001 | Host-aware lookup and local compatibility pass | Passed: local, `[ramhorn] repo`, and `[vps] repo` selected in one manager without restarts |
| SC-002 | Host collision and exact Stop ownership regressions pass | Passed: identical `repo` names on two hosts; rename and Stop hit only the intended row |
| SC-003 | Disconnect, refresh, failed attachment, and same-ID reattach regressions pass | Passed: detach, passive refresh, same-ID reattach, missing target |
| SC-004 | Version 3 restoration and disabled-persistence regressions pass | Passed: fresh Emacs restored the row with zero requests |
| SC-005 | Stop cancellation sends no request | Passed: cancel sent zero requests; the second Emacs detached (clients 3 to 2) and the first client survived |
| SC-006 | Exact acknowledgment, lost verification, and both callback orders pass | Passed: one kill, one verification, row removed |
| SC-007 | Host labels and local-integration exclusion regressions pass | Passed: only editor commands were used |
| SC-008 | Unavailable-host and other-target isolation regressions pass | Passed: ramhorn row stayed usable while the vps connection was cut and its target stopped |
| SC-009 | Discovery 0.11 s, attach 5.2 s, reattach 5.0 s, Stop 1.05 s | Passed: interactive input and output confirmed |
| SC-010 | Workflows 1–5 passed live | Passed: workflow 2 on two hosts and the second-computer step of 4 |

All tasks are complete. The `vps` Agent ran without model credentials, so prompt input on `vps` was not exercised; input and output were confirmed on `ramhorn`.

Use a fresh disposable Emacs for live validation. Do not hot-load the changed record definitions over existing live Sessions.
