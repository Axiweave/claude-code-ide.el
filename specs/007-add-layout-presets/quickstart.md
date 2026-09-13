# Quickstart: Validate Predefined Manager Layouts

**Feature**: `007-add-layout-presets` | **Date**: 2026-09-12

Use this guide to validate the implemented preference and layout behavior.
See [the contract](contracts/elisp-surface.md) for expected behavior and [the data model](data-model.md) for ownership rules.

## Prerequisites

- Emacs 28.1 or later for the local package.
- Emacs 30.1 or later with the compatible RPC client for remote project companions.
- The implemented package loaded in Emacs, with an `emacsclient` server.
- Two disposable Agent Sessions in the same local directory.
- Ghostel and its native module for shell scenarios.
- Magit for the default Git scenario. Dired scenarios do not require Magit.
- An already approved disposable remote Session for remote validation.

Use Sessions with no valuable unfinished Agent work.
Do not add host approvals or install remote software just to run this guide.
Do not stop a production Agent to test shell survival.

## 1. Run the required repository gate

From the repository root, run:

```bash
./scripts/compile-and-test.sh
```

Expected: exit status zero, successful byte compilation, and no unexpected ERT results.
Skipped dependency-specific tests must remain distinct from passing tests.

At planning time, this command failed in ten existing Magit-dependent tests because their batch environment could not load Magit modules.
That is an execution gate error, not an accepted exemption for this feature.
Resolve the gate before claiming implementation acceptance.
Do not replace this command with a narrower test selection.

## 2. Run the focused behavior checks

The feature tests use the `claude-code-ide-test-manager-layout-preset-` prefix.
Run the focused selection:

```bash
CCI_LAYOUT_CHECK_LOAD_PATH="$(emacsclient --eval 'load-path')"
emacs -batch --eval "(setq load-path '$CCI_LAYOUT_CHECK_LOAD_PATH)" \
  -L . -l ert -l claude-code-ide-tests.el \
  --eval '(progn
    (unless (ert-select-tests "claude-code-ide-test-manager-layout-preset-" t)
      (error "No layout preset tests exist"))
    (ert-run-tests-batch-and-exit "claude-code-ide-test-manager-layout-preset-"))'
```

Expected: the selection contains the feature's behavioral checks and has no unexpected results.
A zero-test run does not count as proof.
This isolated batch borrows the live Emacs dependency load path without loading tests into the live process.
It does not replace the required repository gate or use that gate's dependency-path discovery.

Required behavior groups:

| Group | Observable result |
| --- | --- |
| Six arrangements | Correct content and orientation with unchanged Agent and sidebar |
| Old-side cutover | Old side value cannot change the selected preset's arrangement |
| Provider isolation | Dired and shell choices never invoke the custom Git provider |
| Shell identity | Same-Session reset reuses its process, same-directory Sessions remain independent |
| Saved layout recovery | Missing or exited shells never auto-start on return |
| Focus | Saved selected window returns, explicit manager-focus requests remain effective |
| Remote publication | Delayed results use the captured preset and cannot replace newer layouts |
| Failure behavior | Invalid values, unavailable support, startup errors, and split failures leave the Agent usable |
| Cleanup | Disconnect retains ownership, Session removal leaves the ordinary shell running |
| View ownership | Provider changes cannot destroy another Session's shared native view |
| Persistence | Reloaded metadata does not create or adopt a shell process by buffer name |

Use isolated dependency fixtures for unavailable-Ghostel and unavailable-Magit checks.
Do not uninstall packages from the live Emacs for these cases.

## 3. Reload changed source into Emacs

From the repository root, run these commands after the full gate passes:

```bash
emacsclient --eval "(load-file \"${PWD}/claude-code-ide-session.el\")"
emacsclient --eval "(load-file \"${PWD}/claude-code-ide-remote-project.el\")"
emacsclient --eval "(load-file \"${PWD}/claude-code-ide-manager.el\")"
```

Expected: each load returns t without a load error.
Reload any additional source file that the implementation changes.
Do not load `claude-code-ide-tests.el` into the user's live Emacs.
No Ghostel native-module change is planned, so this feature should not require a native-module restart.

## 4. Capture the validation Session and preferences

1. Select the first disposable Session through the manager.
2. Run the following command:

```bash
emacsclient --eval '(progn
  (unless claude-code-ide-manager--current-session-key
    (error "Select a disposable manager Session first"))
  (setq cci-layout-check-session claude-code-ide-manager--current-session-key
        cci-layout-check-original-preset claude-code-ide-manager-layout-preset
        cci-layout-check-original-provider claude-code-ide-manager-status-buffer-function))'
```

Expected: `cci-layout-check-session` identifies that exact Session, not its project directory.
These temporary variables are validation notes, not package configuration.

## 5. Check all six arrangements

For each row below, set the preset and reset the captured Session.
The following command demonstrates `magit-left`:

```bash
emacsclient --eval '(progn
  (setq claude-code-ide-manager-layout-preset (quote magit-left))
  (claude-code-ide-manager-reset-layout cci-layout-check-session))'
```

Repeat with each preset value:

| Value | Expected left | Expected right |
| --- | --- | --- |
| `magit-left` | Magit or configured Git companion | Same Agent |
| `magit-right` | Same Agent | Magit or configured Git companion |
| `shell-left` | Ordinary Ghostel shell | Same Agent |
| `shell-right` | Same Agent | Ordinary Ghostel shell |
| `dired-left` | Dired for Session directory | Same Agent |
| `dired-right` | Same Agent | Dired for Session directory |

Check the actual windows after each reset.
The sidebar remains in its existing position.
The Agent window receives focus for this direct reset call.
No additional Agent row appears for the shell.

Repeat the arrangement checks for available supported Agents with Ghostel.
The user excluded EAT and vterm from acceptance on 2026-09-12.
Feature 008 has since removed that backend code.
Record unavailable Agent combinations rather than claiming that they passed.

## 6. Prove provider and old-side isolation

1. Set a recognizable temporary Git provider:

```bash
emacsclient --eval '(setq claude-code-ide-manager-status-buffer-function
  (lambda (_directory) (get-buffer-create "*layout-provider-check*")))'
```

2. Apply `magit-left` and `magit-right`.
3. Confirm the named custom buffer appears on the selected side.
4. Apply `dired-left` and `dired-right`.
5. Confirm actual Dired appears for the Session directory, not the custom buffer.
6. Apply both shell presets.
7. Confirm the ordinary shell appears instead of the custom buffer.

Check old-side precedence with:

```bash
emacsclient --eval '(progn
  (setq claude-code-ide-manager-session-window-side (quote left)
        claude-code-ide-manager-layout-preset (quote magit-left))
  (claude-code-ide-manager-reset-layout cci-layout-check-session))'
```

Expected: Git remains left and the Agent remains right.
This deliberately sets the removed variable to simulate an old user configuration.
It must not affect the new layout.

Restore the provider before later scenarios:

```bash
emacsclient --eval '(setq claude-code-ide-manager-status-buffer-function
  cci-layout-check-original-provider)'
```

## 7. Prove live shell reuse and isolation

1. Apply `shell-left` to the first Session.
2. Enter these commands in its shell:

```sh
printf 'shell-pid=%s\n' "$$"
pwd
sleep 60
printf 'same-shell-finished\n'
```

3. While `sleep` runs, apply `shell-right` to the same Session.
4. Confirm the shell moves without a new prompt, lost output, or an extra shell.
5. Wait for `same-shell-finished` in that same buffer.
6. Select the second Session in the same directory.
7. Apply a shell preset to the second Session.
8. Print its shell PID and directory.
9. Change the second shell's directory.
10. Return to the first Session.

Expected: each Session has a distinct shell PID and buffer.
The second shell's directory change does not change the first shell's directory.
Returning to the first Session preserves its prior output and current directory.

## 8. Prove saved-layout and focus precedence

1. Apply a shell preset and select its shell window.
2. Resize the content windows manually.
3. Switch to another Session through the manager.
4. Set a different default preset without resetting the first Session.
5. Return to the first Session.

Expected: its saved arrangement, window sizes, selected shell window, and live shell return.
The changed default does not apply until explicit reset.

Repeat with the Dired window selected in a saved Dired layout.
For a manager action that requests continued manager focus, confirm the manager retains focus instead.

For an approved remote Session, repeat the saved selected-window check.
A delayed companion completion must not take focus after the user selects another window.

## 9. Prove exited and missing shell recovery

Use the first disposable Session while it has a shell preset.

1. Select the companion shell buffer.
2. Evaluate `M-: (setq-local ghostel-kill-buffer-on-exit nil)`.
3. Print a recognizable marker in the shell.
4. Enter `exit` in that shell.
5. Switch away from the Session.
6. Return to it.

Expected: the old output remains, no shell starts, and the system explains the explicit reset action.
Reset to a shell preset.
Expected: a new shell starts in the Session directory, not the old shell's later working directory.

Repeat with the new companion buffer:

1. Evaluate `M-: (setq-local ghostel-kill-buffer-on-exit t)` in that buffer.
2. Enter `exit` and confirm Ghostel removes the buffer.
3. Switch away and return.

Expected: the Agent stays usable, no shell starts, and reset guidance appears.
The missing shell must not cause default-layout fallback to start a replacement.

The isolated ERT checks must also cover an unrelated buffer that reuses the missing shell's name.
The manager must not adopt that buffer as the companion.

## 10. Prove shell survival after Session removal

1. Use a disposable Session with a live companion shell.
2. Run a short `sleep` command in the companion shell.
3. Stop or remove only that disposable Agent Session through its normal manager action.
4. Select the remaining ordinary shell buffer from Emacs's buffer list.
5. Confirm the command completes and the shell still accepts commands.

Expected: the Agent Session disappears or ends according to its normal behavior.
The companion remains an ordinary terminal with its output and current directory intact.
A new Session in the same directory must not claim it automatically.

For a remote Session, use an explicit temporary disconnection rather than confirmed removal.
After normal explicit reattachment with the same remembered Session ID, confirm its existing live companion remains associated.
A confirmed removal releases that association without killing the shell.

## 11. Validate approved remote layouts

Use an already approved disposable remote Session with project access enabled.
Do not change host approval as part of this procedure.

1. Apply each of the six presets.
2. Confirm the Agent remains usable while a companion prepares.
3. For Dired, inspect its remote directory and host.
4. For shell presets, run:

```sh
hostname
pwd
printf 'remote-shell-pid=%s\n' "$$"
```

Expected: the host and directory match the Session, including its selected Worktree.
No local shell or local Dired directory substitutes for the remote target.
The shell follows the installed RPC PTY policy and Ghostel's remote shell preferences.

If the default remote shell is not the desired one, inspect `ghostel-tramp-shells` and connection-local shell settings.
An explicit `rpc` shell preference is optional. This feature must not rewrite it.

To check delayed publication:

1. Request one preset on the disposable remote Session.
2. Before preparation finishes, explicitly reset to another preset.
3. Wait for both requests to settle.

Expected: only the latest applied request controls the visible companion and side.
A stale shell that already started may remain as an ordinary terminal, but it cannot replace the current companion.
Use deterministic ERT scheduling checks when the connection is too fast to reproduce this manually.

## 12. Validate failures without changing real approvals

Run the focused ERT groups for these controlled conditions:

- Unknown preset value.
- Missing Ghostel package or native support.
- Shell startup failure.
- Missing or inaccessible Session directory.
- Insufficient window width.
- Disabled remote project access.
- Enabled but unavailable remote access.
- Host approval or attachment changes before completion.
- Shared native view ownership during a provider switch.

Expected: each condition has a specific explanation and leaves the target Agent usable.
Only the Git provider failure uses the existing Dired fallback.
Do not change production host approvals or kill production connections to reproduce failure paths.

## 13. Restore validation preferences

Run:

```bash
emacsclient --eval '(setq claude-code-ide-manager-layout-preset
                         cci-layout-check-original-preset
                         claude-code-ide-manager-status-buffer-function
                         cci-layout-check-original-provider)'
```

This restores preferences only. It does not reset a user's saved layout.
Close disposable shell buffers manually after their commands finish.
Do not close unrelated Sessions or ordinary terminals.

## Acceptance record

### Initial acceptance gate

Validation completed on 2026-09-12 on macOS arm64 with Emacs 31.1.50.
The user excluded EAT and vterm from acceptance during validation.
Feature 008 has since removed that backend implementation.

- `./scripts/compile-and-test.sh` passed with **927 tests, 919 expected results, 0 unexpected results, and 8 skips**.
- The gate used a disposable HOME and existing installed dependency paths. It installed no packages.
- The focused integration run passed **26/26 checks**, including all **15 layout-preset checks**.
- Controlled ERT fixtures covered unavailable dependencies, failed admission, stale requests, shared views, and restoration failures.
- Changed Elisp was reloaded with `emacsclient` after the gate passed.
- The live remote view and writer tables use the provider-aware key test.

The eight gate skips remain skips, not native acceptance results.
They cover existing concurrent-session, Flymake, file-pattern, CLI launch, Session-stop, window-toggle, and deferred MCP checks.

### Local Ghostel evidence

The six-preset checks used a configured Git callback, real Dired, and real ordinary Ghostel shells.
Each check verified companion placement, selected Agent window, unchanged Agent process, and unchanged Session count.
Mirrored shell layouts preserved the exact shell buffer and process.

| Agent/backend | Six arrangements | Shell PID in both orientations |
| --- | --- | --- |
| OMP/Ghostel | Passed | 41362 |
| Codex/Ghostel | Passed | 47413 |
| Claude/Ghostel | Passed | 47468 |
| Pi/Ghostel | Passed while the Agent process was live | 49597 |
| OpenCode/Ghostel | Passed | 49636 |

Pi later exited with status 1. These results do not establish sustained Pi startup stability.
No other Agent/backend combination is claimed.

Two same-directory OMP Sessions had independent shell PIDs **38945** and **42957**.
Their initial directory was `/var/folders/vg/4l8mg2ss5m36qk342npvgw240000gq/T/cci-layout-native-hCEIyA`.
Mirroring preserved PID 38945.
Stopping the second Agent released ownership without killing its shell.
That shell completed its pending command with PID 42957 and the same directory.

Saved-layout checks restored the renamed shell, selected window, and saved width after the default changed.
A manually closed shell window stayed closed.
Ordinary return after shell exit attempted no replacement shell creation.

### Approved ramhorn evidence

The user authorized disposable checks on the already approved host `ramhorn`.
Two real OMP zmx Sessions used `/tmp/cci-layout-007.urGjQ2`.
All six presets passed with real remote Magit, Dired, and Ghostel companions.
The exact RPC directory was `/rpc:ramhorn:/tmp/cci-layout-007.urGjQ2/`.

- Delayed completion preserved sidebar focus and the live Agent process.
- Mirroring reused the exact shell process.
- Independent shells reported PIDs **3662071** and **3662535**, hostname `ramhorn`, and the exact remote directory.
- After normal detach, the second shell completed a delayed command with PID 3662535 and the same directory.
- Saved restoration preserved the selected shell window and width **66** despite a changed default.
- Temporary disconnection and explicit reattachment preserved the remembered Session ID and its shell.
- Confirmed removal released ownership. A new Session on the same zmx target received a new shell.
- With exit-buffer retention enabled, restoration preserved old output without restarting the shell.
- Explicit reset created a replacement while retaining the old output buffer.
- With exit-buffer deletion enabled, ordinary return kept the Agent usable and created no shell.
- Both shells remained live after verified Agent Stop.

Native screenshot evidence:
`/var/folders/vg/4l8mg2ss5m36qk342npvgw240000gq/T/omp-computer-157cdec2c9c84dd8.png`

Fast stale-request and admission-change cases used deterministic ERT fixtures instead of production approval changes.
Validation used existing RPC support and the existing SSH PTY policy.
It changed no host approvals, connection settings, or installed software.

### Completion and cleanup

The initial run passed the exercised Ghostel scenarios. The Phase 8 checks below cover the later convergence repairs.
EAT and vterm are excluded by user direction, not recorded as acceptance failures or claimed backend coverage.
The Pi stability limit above remains explicit.
Feature 008 has since removed that backend selection code.

Both disposable remote zmx targets stopped with verified results.
The remote directory and disposable local scripts, directories, and Emacs processes were removed.
No unrelated Sessions or user work were removed.
No commit was created.

### Phase 8 convergence validation

Validation completed on 2026-09-12 with the same macOS arm64 and Emacs 31.1.50 environment.

- The final `./scripts/compile-and-test.sh` run passed: **930 tests, 922 expected results, 0 unexpected results, and 8 skips**.
- All **18 layout-preset regressions** passed.
- Each of the three new regressions failed before its repair and passed afterward.
- Existing saved-shell and stale-result checks still passed.
- Changed manager and remote-project source was reloaded into the user's Emacs with `emacsclient` after the gate passed.

Native validation used an isolated Emacs with real local and remote OMP/Ghostel Sessions.
It loaded existing Magit, RPC, and msgpack dependencies without installing software.
The first isolated attempt lacked the msgpack load path. Adding the existing installed path resolved that environment error.

Remote validation used the approved host `ramhorn` and disposable directory `/tmp/cci-convergence.nCNRRs/`.
Preparation was deferred until after remote A → local B → remote A navigation.
The real RPC worker then displayed the captured Magit-left companion despite newer Dired-right and provider preferences.
The companion used `/rpc:ramhorn:/tmp/cci-convergence.nCNRRs/`, retained manager focus, and left the same Agent process live.

Further native checks restored the saved manager-window selection after another navigation round trip.
A temporary native restoration error then rebuilt the local Dired-right layout instead of retaining the remote Session's companion.
The local Agent kept its buffer, live process, and selected window.
The fault-injection advice was removed immediately after that check.

Native screenshots:

- Remote completion: `/var/folders/vg/4l8mg2ss5m36qk342npvgw240000gq/T/omp-computer-157cf05f7cc84dd9.png`.
- Local fallback: `/var/folders/vg/4l8mg2ss5m36qk342npvgw240000gq/T/omp-computer-157cf091c5484dda.png`.

The disposable zmx target `cci-converge-nCNRRs` stopped with `:verified t`.
A remote inventory check confirmed its absence and removal of the disposable directory.
The isolated Emacs and local validation directory were removed.
No production approvals changed. No commit was created.

### Phase 9 convergence validation

Validation completed on 2026-09-12 with macOS arm64, Emacs 31.1.50, and real local and remote OMP/Ghostel Sessions.
Native EAT/vterm acceptance remained outside the user-approved scope. Feature 008 later removed those integrations.

- The final `./scripts/compile-and-test.sh` run passed: **932 tests, 924 expected results, 0 unexpected results, and 8 skips**.
- All **20 layout-preset regressions** passed.
- Both new regressions failed on their reported behavior before the fixes.
- All **54 existing remote Project-view tests** passed.
- Existing callback, candidate-retention, saved-shell, and delayed-navigation checks remained successful.

Local validation used an isolated Git repository and the installed Magit package.
Both `magit-left` and `magit-right` preserved one Agent window and one Magit window under these display policies:

- `magit-display-buffer-same-window-except-diff-v1`
- `magit-display-buffer-fullframe-status-v1`

The checks preserved the same live Ghostel Agent, the requested orientation, and Agent or manager focus as requested.

Remote validation used the approved host `ramhorn` and disposable directory `/tmp/cci-phase9.DAAiri/`.
The installed RPC client used its existing server in never-deploy mode.
The checks used installed packages and remote software.

Real Magit and Dired preparation each completed for `original/` before publication paused.
The Session directory then changed to `other/`.
Neither stale result appeared immediately or after remote-to-local-to-remote navigation.
The same Agent remained live and selected.
Explicit reset displayed Dired at `/rpc:ramhorn:/tmp/cci-phase9.DAAiri/other/`.

The native run also exposed a previously ready view that could borrow a replacement request's metadata.
The final reuse check validates the registered provider and directory, not only the newer request.
The regression now covers that transition.
A repeated native navigation check displayed the captured Magit-left view for `original/`, despite newer Dired-right and provider preferences.
It used one worker and preserved manager focus.

Native screenshots from this run:

- Dired recovery: `/var/folders/vg/4l8mg2ss5m36qk342npvgw240000gq/T/omp-computer-157cf806da884ddc.png`.
- Captured Magit navigation: `/var/folders/vg/4l8mg2ss5m36qk342npvgw240000gq/T/omp-computer-157cfa1947c84ddd.png`.

The user's Emacs loaded the changed manager and remote-project source through `emacsclient` after the final gate passed.
The disposable zmx target `cci-phase9-DAAiri` stopped with `:verified t`.
Both supervised processes exited with code zero.
The cleanup commands removed the disposable local and remote directories.
No production approvals changed. No commit was created.

#### Final replacement scheduling checks

The final T031 checks covered two additional transitions on the same date:

1. A published Dired view's Session directory changes before ordinary navigation.
2. Native restoration fails while the Session still has a pending companion request.

Both extended regressions failed before repair and passed afterward.
The navigation regression confirmed a live companion buffer before checking its displayed window.
Capture now discards stale window snapshots so serialized state cannot restore the obsolete view.
Replacement scheduling starts the current request instead of treating a stale live buffer or obsolete pending attempt as sufficient.

Native validation used `ramhorn` and `/tmp/cci-phase9-final.VzO817/`.
Ordinary navigation replaced the `original/` view with Dired at `/rpc:ramhorn:/tmp/cci-phase9-final.VzO817/other/`, without an explicit reset.
A temporary `window-state-put` failure then exercised recovery while a request remained pending.
The old request became abandoned, and the rebuilt request displayed Dired in `original/`.
Both transitions preserved the same live, visible Ghostel Agent.
The check removed its temporary advice before completion.

Native screenshot: `/var/folders/vg/4l8mg2ss5m36qk342npvgw240000gq/T/omp-computer-157cfeedf3484dde.png`.

The final repeated gate passed: **932 tests, 924 expected results, 0 unexpected results, and 8 skips**.
The user's Emacs loaded the final manager and remote-project source through `emacsclient` after that gate.
The disposable zmx target `cci-phase9-final-VzO817` stopped with `:verified t`.
Both supervised processes exited with code zero.
Cleanup removed the final local and remote verification directories.
No production approvals changed. No commit was created.
