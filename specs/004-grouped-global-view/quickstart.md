# Quickstart: Validate Grouped Global View

**Status**: Implemented. Acceptance results appear in section 8.
**Contracts**: [manager view](contracts/manager-view.md), [remote metadata](contracts/remote-metadata.md).
**State rules**: [data model](data-model.md).

## Prerequisites

- Use Emacs 28.1 or later and the existing package dependencies.
- Use the user's existing Agent definitions and CLI paths.
- Install Git for local repository scenarios.
- Use an existing Emacs server for live manager checks.
- Use ghostel and an already approved configured host for remote attachment checks.
- Use existing remote Agent Sessions only. Do not create or stop remote Sessions for this guide.

Do not claim success from this guide before implementing the feature.
Remote authentication, host trust, Agent credentials, and repository contents remain user-controlled.

## 1. Run batch verification

From the checkout, run:

```bash
./scripts/compile-and-test.sh
```

Expected result: all Elisp files byte-compile and the full ERT suite passes.
Repeat batch verification with Emacs 28.1 first in `PATH` when validating the minimum supported version.
Record the actual Emacs version and test count rather than copying a historical count.

The new behavioral regressions should use the existing ERT file and reset-manager-state helpers.
Use the `claude-code-ide-test-manager-grouped-` and `claude-code-ide-test-remote-metadata-` prefixes for targeted runs.
Use the full script above for terminal verification. It supplies the dependency load paths that this checkout requires.
Do not replace it with `emacs -Q --batch -L .`, which omits dependencies such as `avy`.
For an optional focused run, use a configured isolated test Emacs with the same dependencies available.

1. Load `claude-code-ide-tests.el` with `M-x load-file`.
2. Run `M-x ert` with this quoted Lisp string as the selector:

```text
"claude-code-ide-test-\\(manager-grouped\\|remote-metadata\\)-"
```

Verify that this focused run reports a nonzero test count.
Do not use an empty selection as proof.

Required observable regression boundaries:

| Boundary | Expected result |
|---|---|
| Linked worktrees, bare-linked worktrees, independent clone, symlink | Correct shared or separate group identity |
| Duplicate project names and multiple Sessions per Worktree | Distinct headings and selectable rows |
| Grouped order and slots beyond ten rows | Display, numeric selection, n/p, and group jumps agree |
| Grouped move or E apply | Within-group changes preserve unrelated flat interleaving |
| Opposite flat and grouped name-sort orders | Sidebar moves visibly change the requested adjacent rows, preserve other groups' displayed order, and preserve occupied flat positions |
| Disconnected row and stale grouped E snapshot | Valid remembered rows apply. Changed membership rejects without pin/order mutation |
| Versions 1–3 persisted state | Sessions, selection, pins, order, and layouts survive migration with flat default |
| Remote metadata refresh on one host | All its known targets are eligible. No other host or discovery command is contacted |
| Malformed protocol, unsafe directory, unconfigured host | No unsafe dispatch or partial malformed-batch application |
| Missing Git, permission error, timeout, cancellation | Previous cache and terminal remain intact |
| Synchronous post-attach metadata dispatch failure | Registered Session, terminal, attach-all count, and normal reattach selection remain intact |
| Detach, reattach, Stop, or host removal before callback | Old results cannot update replacement owners or recreate removed rows |
| Startup, restore, G, toggle, and navigation | Zero metadata SSH requests |
| Grouped editor with new Sessions after open | Existing fallback-order and pin-clearing behavior remains consistent |

Use real local Git fixtures for identity and non-Git/error classification.
Use controlled transport simulations for network failures and lifecycle races. Do not damage SSH configuration or live remote repositories.

## 2. Prepare disposable local repositories

These commands create only an isolated temporary fixture:

```bash
export CCI_REPO=/Users/fuyu0425/.spacemacs.d-30/site-lisp/claude-code-ide.el
export CCI_GROUP_FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/cci-grouped-view.XXXXXX")
git init -b main "$CCI_GROUP_FIXTURE/project-a"
git -C "$CCI_GROUP_FIXTURE/project-a" \
  -c user.name=Fixture -c user.email=fixture@example.invalid \
  -c commit.gpgsign=false commit --allow-empty -m fixture
git -C "$CCI_GROUP_FIXTURE/project-a" worktree add -b topic "$CCI_GROUP_FIXTURE/project-a-topic"
git clone "$CCI_GROUP_FIXTURE/project-a" "$CCI_GROUP_FIXTURE/project-b"
printf 'Fixture: %s\n' "$CCI_GROUP_FIXTURE"
```


## 3. Reload changed Elisp and inspect the real manager

The implementation adds struct slots. Do not reload it over old-layout Session or manager item objects.
For the initial upgrade, use a fresh test Emacs with separate persisted test state.
Preserve the user's Sessions and persisted state before any restart.
Use the reload command below only after the test server has compatible runtime objects.

After batch verification, reload the implementation through the existing Emacs server:

```bash
emacsclient --eval '(progn
  (load-file "/Users/fuyu0425/.spacemacs.d-30/site-lisp/claude-code-ide.el/claude-code-ide-zmx.el")
  (load-file "/Users/fuyu0425/.spacemacs.d-30/site-lisp/claude-code-ide.el/claude-code-ide.el")
  (load-file "/Users/fuyu0425/.spacemacs.d-30/site-lisp/claude-code-ide.el/claude-code-ide-manager.el")
  (load-file "/Users/fuyu0425/.spacemacs.d-30/site-lisp/claude-code-ide.el/claude-code-ide-transient.el"))'
```
Open each fixture directory in Dired and use `M-x claude-code-ide-current-directory` to start a Session.
Use `M-x claude-code-ide-new-session` to create a second Session in one Worktree.
Do not change the user's Agent selection settings for this check.


1. Open the global sidebar with `M-x claude-code-ide-manager-focus-global`.
2. Record the active Session and selected row.
3. Press `v` to enable grouped view.
4. Inspect project headings, branch labels, duplicate rows, and numeric shortcuts.
5. Press `C-j` and `C-k` across group boundaries and both ends.
6. Press `n`, `p`, and numeric shortcuts to compare selection with displayed order.
7. Press `v` to return to flat view.
8. Open a repo-local sidebar and confirm its presentation remains unchanged.

Expected results:

- `project-a` and its linked Worktree share one group. The independent clone remains separate.
- Every Session appears once. Both Sessions in the same Worktree remain independently selectable.
- Headings are non-interactive and do not consume shortcuts or Avy targets.
- Toggle preserves selected and active identities without changing layouts or acknowledging Agent results.
- Group jumps retain sidebar focus and wrap across groups.
- Spacemacs/Evil receives the intended `v`, `C-j`, and `C-k` bindings.

Repeat local manager interactions with vterm, eat, and ghostel where installed.
For an unsupported existing remote backend, verify its explicit error instead of claiming remote support.

Capture an actual manager screenshot or accessibility view after the changes.
Batch assertions alone do not prove visual row alignment or key behavior in the user's configuration.

## 4. Validate grouped E and persistence

1. Enable grouped view and open `E`.
2. Move two Sessions within one group.
3. Attempt to move a Session across a fixed heading.
4. Apply the valid within-group order with `C-c C-c`.
5. Return to flat view and inspect unrelated project interleaving.
6. Open `E` again and cancel with `C-c C-k`.
7. Save state with manager persistence enabled.
8. Restart only an isolated test Emacs and reopen the global sidebar.

Expected results:

- Fixed headings remain intact. Invalid edits cannot change pins or order.
- Applying grouped order clears pins through the existing scope-wide behavior.
- Other groups retain their occupied positions in flat order.
- Cancel changes neither order nor pins.
- Restart restores view choice, remembered metadata, Session identities, and layouts without remote requests.

Use the race regressions for metadata changes while `E` is open and for Sessions that vanish before apply.
Use an existing remembered remote row to confirm grouped `E` accepts disconnected Sessions.
The pre-existing flat-editor disconnected-row limitation remains outside this feature.

## 5. Validate remote host scope and disconnected navigation

Use a host already present in `claude-code-ide-remote-hosts`, with existing remote Sessions in linked Worktrees.
Confirm approval for the exact host before a live SSH action.

1. Attach through the existing `C-u a`, `C-u A`, or explicit reattach command.
2. Verify terminal interaction becomes available without waiting for metadata.
3. Enable grouped view and inspect the Host section.
4. Run `M-x claude-code-ide-manager-refresh-remote-metadata`.
5. Select one configured host at the prompt.
6. Inspect metadata results for that host's connected and remembered Sessions.
7. Select a group whose first Session is already disconnected.
8. Press `C-j` or `C-k` to continue from that group.
9. Press `G`, toggle the view, and navigate ordinary rows.

Expected results:

- The explicit refresh targets all known manager Sessions on the chosen host only.
- No new Session discovery, reattach, or Agent command occurs.
- Linked Worktrees resolve into one project group after valid metadata arrives.
- A disconnected group jump changes selection but leaves the displayed terminal unchanged.
- Another group jump continues from the selected group, not the active terminal's group.
- Ordinary refresh, toggle, and navigation create no metadata SSH requests.

Use the controlled transport regressions to prove request counts and host restrictions.
Use the live surface only to prove actual labels, selection, layouts, and terminal behavior.
Do not send prompts to an Agent or Stop a remote target for this validation.

## 6. Measure cached preparation

Use a disposable batch script with 1,000 in-memory manager items across 100 groups.
Populate validated cached metadata and a mix of pin, manual-order, and fallback-sort cases.
Time 20 cached projection/render-preparation runs using Emacs `benchmark-run`.
Record the median and Emacs/runtime details.

Expected result: median below 100 ms on the development workstation, with zero external process starts during measured preparation.
Measure local metadata refresh separately because it legitimately invokes Git.
Do not hide metadata latency inside the cached-render measurement.

## 7. Finish validation

1. Record batch results, exercised backends, UI evidence, and remote host scope.
2. Record any acceptance scenario that the environment prevented.
3. Remove only disposable fixture Sessions and repositories created for this guide.
4. Remove throwaway scripts after preserving their results in the implementation report.
5. Update user documentation and the feature TODO only after the required acceptance checks pass.

Do not mark this feature implemented from the planning experiment or reviewer approval alone.

## 8. Implementation validation record

### US1 checkpoint

- Environment: isolated native Emacs 32.0.50 instance on macOS arm64.
- Fixture: a real Git repository, one linked Worktree, one independent clone, and four Session records with pipe-process buffers.
- No Agent started. No remote connection occurred.
- The main repository and linked Worktree shared one heading. The independent clone had a separate heading.
- Two Sessions in the main Worktree displayed `main · 1` and `main · 2`. The linked Worktree displayed `topic`.
- Actual sidebar `SPC`, `2`, `3`, and `4` selected all four Session buffers independently.
- Actual sidebar `v` toggled both ways. Native screenshots confirmed headings, labels, row selection, and the unchanged terminal pane.
- Instrumentation confirmed unchanged active/selected IDs and saved layouts, with zero process starts across both toggles.
- A fresh batch Emacs process restored the grouped view and all four Git metadata records from the isolated persistence directory.
- The targeted manager suite passed 48 tests. The current Git diagnostic-boundary regression also passed after its final parser adjustment.

### US2 checkpoint

- The targeted grouped-view, row-navigation, sidebar, and row-detail suite passed all 23 tests.
- Native keyboard input exercised sidebar `C-j` and `C-k`, forward/reverse wrapping, and continued navigation from a disconnected selection.
- The manager menu displayed both commands. Its `C-j` entry also selected the disconnected fixture.
- Screenshots confirmed that disconnected selection retained the active terminal and sidebar focus.
- The disconnected jump started zero processes. Connected local jumps refreshed local Git metadata.
- The UI check found that row details replaced the reattach message. Cached disconnected-row details now retain the reattach guidance.
- The isolated instance used the installed Evil package and kept the manager in Emacs state.
- The live Spacemacs 0.999.0 manager also reported Emacs state and the correct `C-j`/`C-k` commands.
- The Spacemacs check inspected bindings only. Keyboard checks used disposable Session fixtures, not the user's Agent Sessions.

### US3 checkpoint

- The order-editor and grouped-move selection passed all 24 regressions.
- Native `E` displayed fixed host/project headings and six remembered disconnected rows.
  `M-n` moved adjacent rows within one project and did not cross a project heading.
  The editor rejected heading deletion.
- Native `C-c C-c` applied the edited order and closed the editor.
  Returning to flat view showed the other project's occupied positions at 2, 4, and 6.
- A changed project identity caused native apply to reject the snapshot and keep the editor open.
  Pins and order remained unchanged. Native `C-c C-k` also preserved both.
- A fresh isolated Emacs restored the saved flat view, six metadata records, and the edited interleaving.
  The restored sidebar rendered with process-start guards active and zero registered Agent Sessions.

### US4 checkpoint

- Approved hosts: `ramhorn` and `vps`. User configuration now lists both hosts.
- Each host used the approved `/tmp/cci-grouped-global-view-01a07579` Git and non-Git fixtures.
- The real SSH adapter returned `git`, `git`, and `non-git` for main, linked topic, and plain directories on both hosts.
- Main and topic shared a canonical common directory on each host. Host-qualified group identities remained distinct.
- Native Ghostel reattachment used the existing ramhorn Agent without Agent input or Stop.
- This check exposed an SSH output wait problem in the synchronous reconnect guard.
  Accepting all process output fixed it. The final real reconnect check completed in 0.210 seconds.
- Native manager `? m` refreshed ramhorn, then vps. Each command made one request and changed only its chosen host.
- Both refreshes preserved Session IDs, order, pins, custom names, active/selected IDs, and layouts.
- Native `C-j`, `C-k`, `n`, `p`, `v`, `G`, and slot `6` made zero new SSH requests.
  Disconnected selection retained the ramhorn terminal and manager focus.
- A fresh batch Emacs restored seven real cached metadata records and the grouped view.
  Manager restore and render started zero processes after package dependencies loaded. No Agent Session reconnected.
- All 51 metadata regressions and all 102 grouped/remote integration regressions passed before final full verification.
- Controlled checks cover cancellation, timeout, overflow, malformed UTF-8, stale ownership, invalid siblings, startup failure, and original Git diagnostics.
- Native screenshot evidence includes `omp-computer-15750dfe1b7714e2.png` and `omp-computer-15750e108a3714e4.png` in the tool screenshot directory.

### Final integrated verification

- `scripts/format-and-clean.sh` formatted only the five affected Elisp files.
- The final `scripts/compile-and-test.sh` run passed byte compilation and ERT.
  It reported 728 tests: 719 expected results, zero unexpected results, and nine skips.
  ERT took 14.419 seconds. The full command took 20.22 seconds.
- Byte compilation emitted warnings in dependencies, test helpers, and a core docstring.
  This was not a warning-free build. Native compilation was not enabled.
- The performance correction required a second full verification run after the initial passing run.
  The final output is available in tool artifact `artifact://366`.

| Acceptance surface | Actual result |
|---|---|
| Local vterm | Native slot `1` displayed the real terminal and its `CHECK:cci-check-vterm` output |
| Local EAT | Native slot `2` displayed the linked Worktree terminal and its `CHECK:cci-check-eat` output |
| Local Ghostel | Native slot `3` displayed the independent clone terminal and its `CHECK:cci-check-ghostel` output |
| Remote Ghostel | Existing ramhorn Agent attached, grouped, refreshed, and detached without Agent input or Stop |
| Remote vterm/EAT | Existing explicit backend-rejection regressions passed. No unsupported remote terminal started |
| Native keyboard | View toggle, row slots, group navigation, grouped editor, and chosen-host menu refresh passed |
| Persistence | Fresh Emacs restored the grouped view and six real host-fixture metadata records after the final source change |
| Restore isolation | Final restore and render started zero processes and registered zero Agent Sessions |
| Emacs versions | Full suite and benchmark used Emacs 31.1.50. Native UI used Emacs 32.0.50 |

The local terminals ran disposable shell commands, not Agents.
The first EAT fixture used a compound command that the existing command parser did not accept.
An executable fixture script exercised EAT successfully. Loading the installed Evil dependency removed the isolated resize warning.
This validation did not run Emacs 28.1. No minimum-version runtime claim is made.
The fresh native instance avoided changing the user's existing Session structs.
Restart the user's Emacs before using the changed structs with existing Sessions.

### Performance result

- Workstation: Apple M2 Max, macOS Darwin 24.6.0, arm64.
- Runtime: standard Emacs 31.1.50 with the manager byte-compiled.
- Fixture: 1,000 items across 100 groups, split between local and cached remote identities.
  Pin, manual-order, and fallback-sort cases were mixed.
- Measurement: 20 `benchmark-run` samples of the complete cached render.
  This included projection, headings, labels, slots, row insertion, and cached help text.
- Final median: **15.9525 ms**. Minimum: 14.928 ms. Maximum: 73.348 ms.
  Process guards counted **zero** external process starts.
- Separate local metadata refresh: **49.875 ms** for 1,000 items sharing three actual directories.
  Git ran nine queries, once per required query per directory.
- Profiling found six repeated remembered-item scans per disconnected row.
  The shared buffer lookup now rejects non-path Session IDs before its legacy directory fallback.
- Additional Emacs 32 IGC full-render measurements varied more.
  Source loading measured 945.218 ms before the correction and 133.186 ms after it.
  Its byte-compiled full-render median was 164.3365 ms.
  The under-100-ms acceptance result above applies to the stated standard Emacs 31 runtime.

### Cleanup and completion

- Both approved hosts confirmed removal of `/tmp/cci-grouped-global-view-01a07579`.
- The isolated client detached from ramhorn. A subsequent `zmx list --short` still listed the same existing Agent.
- The local terminal fixtures ended. The isolated native Emacs service stopped.
- Implementation-owned repositories, persistence directories, protocol probes, compiled benchmark output, and throwaway scripts were removed.
- No eligible post-implementation extension hooks were configured.
- The feature task list and matching `TODOs.org` entry are complete. No commit was created.

### Convergence validation: T039–T041

- Request and response regressions failed before the control-character fix and passed afterward.
  DEL and C1 boundaries now reject invalid batches before dispatch or cache application.
  The shared directory check also rejects unsafe remembered rows and reattach requests.
- The parser regression first accepted `/repo/../other/.git`. It now rejects noncanonical fields across all three Git identity paths.
  Root paths remain valid. Request directories and non-Git trailing separators remain exact.
- A controlled timeout reports both affected directories and the host.
  The regression confirms that the terminal stays live, cached metadata stays unchanged, and a later refresh can start.
- The project formatter processed all three changed Elisp files.
  The final `./scripts/compile-and-test.sh` run completed with 723 expected results, zero unexpected results, and eight skips across 731 tests.
  Byte compilation passed with warnings. Native compilation was not requested.
- `emacsclient` reloaded the zmx and manager source files in the running Emacs.
  Live checks rejected DEL, both C1 boundaries, and a noncanonical Git path. The root path remained valid.
- All 41 tasks are checked. No pre-implementation or post-implementation extension hooks were configured.
  These convergence checks started no real SSH requests and created no commit.

### Convergence validation: T042

- The editor now emits each host heading before that host's first Project group, after the previous group's Session rows.
- The new mixed-host regression fails against the original renderer and passes against the corrected renderer.
  It covers unedited apply, within-group moves, scope pin clearing, local Sessions, and remembered remote Sessions.
  Existing editor regressions now use two hosts and still reject changed headings and cross-group edits without mutation.
- All five focused editor and movement tests pass.
  After formatting, `./scripts/compile-and-test.sh` reports 724 expected results, zero unexpected results, and eight skips across 732 tests.
  Byte compilation passed with warnings. Native compilation was not requested.
- An isolated native Emacs 32 frame displayed one local group and two remote host sections, with two Session rows per group.
  Screenshots confirmed correct heading placement. `C-c C-c` applied both an unedited buffer and a valid within-group move.
  Both applies cleared all six scope pins. Local fixture clients stayed live, and remote rows stayed disconnected.
- The isolated daemon stopped, and both implementation-owned temporary directories were removed.
  `emacsclient` reloaded the verified manager source in the user's running Emacs.
- All 42 tasks are checked. No Agent or real SSH request started during this check. No commit was created.
