# Quickstart: Verify the Ghostel-Only Cutover

**Spec**: [spec.md](spec.md)
**Contract**: [contracts/elisp-surface.md](contracts/elisp-surface.md)

The dated checkpoints below record completed checks. Unrecorded native scenarios remain unverified.
Commands use repository-relative paths from the package root.
This guide is an explicit removal record under FR-013.

## 1. Prepare isolated verification

1. Use Emacs 28.1 or later.
2. Preserve unrelated working-tree changes.
3. Use disposable projects and Sessions for native checks.
4. Provide the package's existing required libraries through `EMACSLOADPATH` when automatic discovery cannot find them.
5. Exclude all terminal libraries from the batch environment.
6. Exclude optional providers from the optional-absence lane.
7. Use only existing approved hosts for remote checks.

Do not install packages, approve hosts, or stop existing Sessions to prepare these checks.
A native check needs an already available Ghostel library/module and the relevant Agent CLI.
Remote checks also need the existing approved-host and zmx prerequisites.
If a prerequisite is unavailable, record the blocked scenario rather than claim a pass.

## 2. Run the required batch gate

Run the complete suite, not only terminal-named tests:

```bash
./scripts/compile-and-test.sh
```

The gate must compile all package Elisp and pass the full ERT suite without a display or installed terminal package.
Tests must use the surviving Ghostel interface mocks.
Retired terminal mocks, providers, and discovery must be absent.
Do not require a fixed test count after obsolete tests disappear.

For an isolated dependency environment, use a disposable HOME:

```bash
CCI_CHECK_HOME=$(mktemp -d)
HOME="$CCI_CHECK_HOME" EMACSLOADPATH="${CCI_REQUIRED_LOAD_PATH}:" \
  ./scripts/compile-and-test.sh
CCI_CHECK_STATUS=$?
printf 'Gate exit: %s\nTemporary HOME: %s\n' "$CCI_CHECK_STATUS" "$CCI_CHECK_HOME"
```

Set `CCI_REQUIRED_LOAD_PATH` to colon-separated directories for required libraries before this command.
Do not include Ghostel, retired terminals, Magit, or other optional providers in that value.
Keep the trailing colon so Emacs retains its standard library path.
Review the exact temporary path before removing that directory after verification.

Core behavior and optional-absence tests must execute in this lane.
Only tests that exercise a real optional integration may report an explicit dependency-absence skip.
A blanket skip or a fake provider success does not satisfy the gate.

Before each batch lane, verify that no real terminal library is discoverable:

```bash
HOME="$CCI_CHECK_HOME" EMACSLOADPATH="${CCI_REQUIRED_LOAD_PATH}:" \
  emacs -Q --batch --eval '
(dolist (library (quote ("ghostel" "vterm" "eat")))
  (when (locate-library library)
    (error "Remove terminal library from the check load path: %s" library)))'
```

This check must run before loading the test file, which supplies terminal mocks.
The runner must no longer add `emacs-libvterm` or any other retired terminal discovery path.

Repeat the full gate with the installed optional integration paths supplied through `EMACSLOADPATH`.
Make sure the corresponding native Magit integration tests execute in that lane.
Report results and skips separately for both environments.
Do not add machine-specific paths or new runtime dependencies to the repository.

The existing CI matrix also runs native compilation where available:

```bash
./scripts/compile-and-test.sh --with-native-compile
```

A local run does not establish that the remote CI matrix passed.

## 3. Prove package loading without Ghostel

Run a fresh process without the test file, which provides Ghostel mocks:

```bash
emacs -Q --batch -L . --eval '
(progn
  (require (quote cl-lib))
  (when (locate-library "ghostel")
    (error "Use a load path without Ghostel"))
  (require (quote claude-code-ide))
  (unless (hash-table-p claude-code-ide--sessions)
    (error "Session registry is unavailable"))
  (when (claude-code-ide-session-for-buffer (current-buffer))
    (error "An unrelated buffer became a Session"))
  (condition-case err
      (progn
        (claude-code-ide-session--ensure-ghostel)
        (error "Missing Ghostel did not stop terminal use"))
    (user-error (princ (format "Expected unavailable support: %s\n"
                               (error-message-string err))))))'
```

Supply only existing required dependency paths when this Emacs cannot locate them.
Expected result: package loading and Session lookup work, followed by an actionable Ghostel-unavailable message.
There must be no installation prompt, process launch, or terminal fallback.
This check requires the new shared support helper from the implementation.

## 4. Verify failures and trust boundaries in ERT

Keep regressions at existing interfaces in `claude-code-ide-tests.el`.
Exercise each distinct failure boundary, not source text or incidental function forwarding.

| Case | Required observation |
| --- | --- |
| Ghostel library absent | Package and non-terminal operations work. Terminal use gives actionable `user-error`. |
| Library present, native support absent | Terminal use fails without download, compilation, prompt, or fallback. |
| Constructor checks installation preference | Auto-install remains disabled throughout both loading and constructor execution. Global preference remains unchanged. |
| Constructor signals error or returns no live process | No successful Session appears. Existing Sessions and processes remain unchanged. |
| Requested directory is invalid or inaccessible | Report the actual failure without a substitute directory. |
| Companion fails after partial creation | Clean only the request's dead partial buffer. Preserve a live shell. |
| Ordinary Ghostel buffer or stale callback | No Agent ownership, input, cleanup, or activity attribution transfers to an unrelated buffer. |
| Legacy preference assignments | A new Session still uses Ghostel. No removed preference reader or compatibility alias exists. |
| Old terminal buffer survives code reload | Package setup, input, and cleanup reject the non-Ghostel mode without reconfiguration, adoption, or process termination. New Sessions ignore old preferences. |
| Failure before or after registration | Missing native support starts no MCP or terminal process. Later failure removes only request-owned active state. A remote target may remain disconnected. |
| OMP graphical versus terminal Emacs | Preserve `PI_FORCE_IMAGE_PROTOCOL=kitty` versus `off`. Do not change Pi. |
| Ghostel output and resize | Both output paths update the correct Session. Resize/reflow behavior and observer lifetime remain correct. |
| Superseded companion request | No stale layout publication. Preserve the current Session and any live ordinary shell. |
| Remote access or project-view failure | Preserve host admission and terminal/view independence. No extra connection or local fallback. |

Keep mocks isolated so the full suite can run in any order.
Do not load a native Ghostel module into ERT to satisfy these cases.

## 5. Run the related parent tests

From the package root:

```bash
emacs -Q --batch -l ../../tests/pkg-claude-code-ide-test.el \
  -f ert-run-tests-batch-and-exit
```

Verify page navigation, End, Plan Review pass-through, copy-mode transitions, and hidden-buffer recenter protection.
Verify file-reference input through the surviving generic input helper.
Use actual Ghostel mode boundaries instead of the removed backend resolver in fixtures.
Keep the existing layout preference and generic popup settings unchanged.

## 6. Exercise every native Agent workflow

1. Start a disposable Emacs with Ghostel and the package loaded.
2. Use a disposable project with no sensitive files.
3. Select each existing Agent through the user's existing configuration.
4. Start a Session through its existing package entrypoint.
5. Record the Session ID, directory, host, buffer, and process identity.
6. Exercise continue and resume through each Agent's existing supported workflow.
7. Send harmless text and submit it.
8. Exercise interruption, scrolling, copy mode, and focus changes.
9. Resize the terminal while the Agent is idle and while it produces output.
10. Exercise text clipboard input and existing supported image paste with non-sensitive content.
11. Observe activity and notifications for the exact Session.

Repeat for Claude Code, Codex, OpenCode, Pi, and Oh My Pi.
Keep each Agent's existing continuation, resume, and image capability limits.
Record graphical and terminal Emacs results for OMP's existing image-protocol behavior.
There must be zero terminal-choice steps and no retired terminal package on the load path.
A mock pass cannot replace these native observations.

## 7. Exercise all six layouts

Repeat the following sequence for `magit-left`, `magit-right`, `shell-left`, `shell-right`, `dired-left`, and `dired-right`.

1. Set `claude-code-ide-manager-layout-preset` to the preset under test.
2. Open the disposable Session in the manager.
3. Reset its layout through the existing manager reset command.
4. Record companion placement, selected window, Agent process, and companion process where applicable.
5. Switch to another disposable Session.
6. Switch back and check saved-layout restoration.
7. Change the default preset without resetting the saved layout.
8. Verify that saved-layout precedence preserves the prior arrangement.
9. Reset explicitly and verify the requested new arrangement.
10. Verify that every live companion shell retains its process.

Also check manager-focus preservation and generic Agent popup side/width behavior.
Use the existing missing-buffer recovery after a restart or a closed disposable companion.
Verify that an exited companion does not appear live and that replacement requires the existing explicit action.
Keep same-directory sibling Sessions distinct.

## 8. Exercise persistent and approved remote lifecycle

1. Create or select a disposable local persistent Agent through the existing zmx workflow.
2. Attach with `M-x claude-code-ide-attach`.
3. Record persistent identity and attachment identity separately.
4. Detach through the existing workflow.
5. Verify that the persistent Agent still exists.
6. Reattach and verify the same persistent identity.
7. Repeat the approved remote attachment scenario from the remote guide on an existing approved host.
8. Verify reconnect without replacement Agent creation.
9. Disable optional remote project access through the existing setting.
10. Verify that permitted terminal attachment remains independent of project views.

Use deterministic ERT failure injection for unapproved hosts and unavailable remote services.
Do not contact an unapproved host merely to test refusal.
Before testing Stop, confirm the exact disposable Session target.
Use the existing Stop command and retain its confirmation behavior.
Verify that unrelated Agents, shells, and persistent Sessions survive.

See [remote guide](../../docs/remote.org) and [zmx guide](../../docs/zmx.org) for the existing supported lifecycle.
Do not follow any obsolete backend-selection instructions that implementation has not yet removed.

## 9. Review the complete removal inventory

Run this read-only tracked-file inventory from the package root:

```bash
git grep -n -i -E \
  'vterm|emacs-libvterm|(^|[^[:alnum:]_])eat([^[:alnum:]_]|$)|terminal-backend|backend-for-process|terminal-ensure-backend' \
  -- .
```

Also review explicitly maintained untracked feature files and the two named parent package configuration/test files.
Review hidden tracked files, automation, comments, examples, prior specs, plans, tasks, and checklists.
Do not treat older feature documents as exempt.
An ignore rule does not exclude an already tracked maintained file from this review.

Keep a separate excluded-material inventory for ignored `refs/`, `ref-docs/`, and `.omp/` contents.
The current checkout tracks no files under those three roots.
Classify broad-search matches there as reference material, external checkouts, or local tool state.
Do not edit those contents or include their matches in the maintained-package acceptance count.
External repositories remain excluded except for the two named parent consumer files.

Classify every remaining maintained-file match as an explicit removal record or an unrelated lexical match.
The accepted maintained-file inventory contains no active support, dependency, configuration example, or callable retired path.

Check the README manually from overview through troubleshooting.
Its existing fork-distinction list must state Ghostel-only support.
Keep the original repository attribution intact.
Do not relabel historical terminal test results as Ghostel passes.

### Maintained documentation result — 2026-09-12

T024–T033 are complete for maintained documentation.
The review covered product names, removed preference names, and broader terminal selection, dispatch, and capability statements.
Runtime and test removal remain separate acceptance checks.

| Remaining reference | Classification |
| --- | --- |
| README fork distinction and matching closed backlog item | Explicit removal records linked to feature 008 |
| Feature 003 removal notes and completed T041/T042 history | Explicit retirement history, not current configuration or callable API guidance |
| Feature 007 dated native exclusions | Historical acceptance scope with explicit feature 008 removal notes. Original Ghostel evidence remains unchanged |
| Feature 008 specification, plan, tasks, and contract inventory | Explicit deletion targets and removal records |
| Earlier checklist references to the former constitution principle | Historical review notes. They declare no active retired integration. Reviewer-owned markers remain unchanged |
| Generic provider, image-protocol, Git, and remote-file backend terms | Unrelated lexical matches. Those policies remain unchanged |
| Ignored `refs/`, `ref-docs/`, and `.omp/` | Excluded reference material, external code, or local tool state. No tracked files reside there |

README installation and command guidance now names Ghostel and explains native support, no automatic installation, and the restart boundary.
The existing fork list retains the original repository attribution.
Prior specs no longer require multiple terminal implementations, removed selection settings, or obsolete dispatch behavior.
The constitution, `AGENTS.md`, and feature 008 reviewer checklist retain their implementation-start hashes.

### Runtime inventory result — 2026-09-12

T023 found no active retired support in package Elisp, tests, automation, or the two named parent consumers.
The negative migration test alone assigns removed preference and cache names.
It proves that those assignments cannot change new terminal creation.
A fresh Emacs process found none of the thirteen named C5 interfaces in variable, function, or customization state.
The runner no longer discovers a retired terminal dependency. The existing terminal-free CI workflow remains unchanged.

## 10. Record evidence and restore the test environment

1. Record commands, dependency paths, Emacs version, exit codes, test results, and explicit skips.
2. Record native observations for each Agent, layout, and lifecycle scenario.
3. Record every retained reference and its removal-record or unrelated-text reason.
4. Restore test-only preferences and the user's original layout setting.
5. Remove only temporary files and directories created for these checks.
6. Close or stop only confirmed disposable Sessions through existing ownership-safe commands.

No implementation acceptance is complete until all specification scenarios have evidence or an explicitly reported external prerequisite.
Do not claim a native, remote, or optional-absence pass from a dependency-present batch run.

### Completed handoff — 2026-09-13

- Final source loaded through `emacsclient` into disposable Emacs instances.
- The verification did not reload the user's normal Emacs or change its layout preferences.
- Real Stop confirmations named the exact owned local target and the exact remote host and target.
- Fresh inventories confirmed removal of those targets and preservation of unrelated persistent identities.
- The owned OpenCode Session and replacement companion shell also closed.
- The recovery Emacs exited with code 0. Its test-only preferences did not persist.
- The empty remote directory `/tmp/cci008-HZnyhh` and the local recovery directory were removed.
- The compiler runner removed its generated outputs. The computer restart had removed the earlier temporary verification directory.
- The final clipboard check confirmed that all saved pasteboard representations remained unchanged.
- No commit, external package uninstall, or Git history rewrite occurred.

Use a fresh Emacs process for the clean cutover.
Do not convert an existing unsupported terminal buffer in place.
Preserve unrelated terminal buffers and processes.

T014 and T036 were completed later by the renewed Agent verification recorded below.

### Screenshot cleanup — 2026-09-13

The cleanup identified twelve screenshots from the recorded tool paths and the disposable Emacs window titles.
It removed those exact files without a wildcard deletion.
The follow-up check found none of the twelve identified files.
Ten four-byte `.png` files remain, but image decoding could not establish their titles or ownership.
The cleanup preserved those uncertain files.

## Implementation evidence

### Setup and foundation — 2026-09-12

- T001: The maintained inventory includes tracked package files, prior specs, and feature 008 artifacts.
- Ignored `refs/`, `ref-docs/`, and `.omp/` contain no tracked files and remain outside cleanup.
- Existing changes to the constitution, maintainer guide, backlog, and parent package configuration are preserved.
- T002: Existing ignore patterns cover Elisp outputs and universal temporary files. No additional technology-specific ignore file is needed.
- Dependency-present and optional-absence load paths use installed libraries through temporary verification environments.
- Graphical Emacs 31.1.50 has Ghostel native support. Executable lookup found all five Agent command paths and zmx.
- Version checks passed for Claude Code 2.1.257, Codex 0.154.0, OpenCode 1.18.30, OMP 18.1.18, and zmx 0.7.1.
- Pi failed with `TypeError: webidl.util.markAsUncloneable is not a function` in `undici` under Node 20.19.5.
- The same Pi failure occurs through the configured `/opt/local/bin/zsh -lc` terminal shell. T014 was blocked for Pi at that time. The renewed verification below later ran Pi on Node 25.9.0.
- These prerequisite checks do not prove native Agent workflows. The installed Pi package and Node configuration remain unchanged.
- T003: The new missing-native regression failed before implementation because local creation started MCP without native support.
- T004: The shared preflight now rejects that request before MCP startup.
- Focused ERT passed both the new regression and the existing companion startup-failure regression: two expected results, zero unexpected results.

Native Agent, layout, and remote acceptance remain unverified at this checkpoint.

### Parent consumer checkpoint — 2026-09-12

- T006: Parent tests now use actual Ghostel mode boundaries instead of the removed resolver.
- The focused mode-entry regression failed against the old parent implementation before T010.
- T010: Five parent callers now check Ghostel mode directly. Removed selection assignments and the dead workaround are gone.
- Existing layout preference and generic popup settings remain unchanged.
- The complete focused parent suite passed: 58 expected results, zero unexpected results.
- The parent-only test and implementation sequence ran independently while the package fixture writer retained exclusive ownership of its file.

### Runtime red checkpoint — 2026-09-12

- T005: Surviving input, launch, environment, resize, activity, and ownership fixtures now use Ghostel.
- Removed renderer and positive terminal-selection tests no longer define the intended behavior.
- Integration corrected one proposed test that incorrectly required takeover of an existing named buffer.
- T017: Regressions cover missing library/native support, an inaccessible directory, failed/missing/dead/foreign constructor results, inert preferences, initialization exit/replacement, and unsupported-buffer safety.
- The first focused run exposed five defects: existing-buffer takeover, partial-buffer leakage, false local startup success, destructive unsupported-buffer cleanup, and input into an unsupported mode.
- A second targeted run confirmed that retired preferences still affected construction and an invalid directory still reached MCP startup.
- The initialization regression also protects a replacement Session from rollback by the failed request.
- These were expected pre-fix failures. They did not establish implementation acceptance.

At this checkpoint, the disposable graphical Emacs had Ghostel native module 0.53.0.
Automatic installation and permission bypass were disabled. Native acceptance had not started.

### Runtime green checkpoint — 2026-09-12

- T005, T007–T009, T011–T013, and T018–T023 now have implementation and focused verification evidence.
- The startup safety set passed eight checks, including constructor failure, replacement ownership, inert preferences, and unsupported-buffer rejection.
- The constructor check exposed a missing special-variable declaration in the core file and a lexical binding in its test.
- No-initializer declarations now preserve dynamic installation suppression without changing Ghostel's global preference.
- The integrated workflow set passed 178 checks with zero unexpected results.
- Those checks cover startup, input, clipboard limits, cursor behavior, layout restoration, companions, persistence, and attachment failures.
- Both Ghostel output paths now have observable idle/working-state checks for process-buffer ownership, heartbeat exclusion, and unsupported-mode rejection.
- The resize lifecycle check exercises suppression from the first registered Session until the last Session leaves.
- A supplemental set passed all fifteen checks with optional providers available.
- Without Magit, five non-UI checks passed and ten native Magit checks reported explicit dependency skips.
- Package failure/cancellation checks use scoped provider mocks. The headless planner check still executes without Magit.
- A fresh process with no terminal libraries loaded the package and performed Session lookup without creating a process.
- Missing Ghostel produced `Install Ghostel before starting a terminal`. The optional installation preference remained uninitialized.
- The settled parent suite passed 58 checks with zero unexpected results.

These results do not replace the full compilation gates or native Agent, layout, and remote acceptance.

### Full quality gates — 2026-09-12

The scoped formatter completed on the five changed package Elisp files and the two named parent consumers.
The parent configuration reported its unavailable `outli-mode` file-local function. Formatting still completed.

Both environments ran `bash scripts/compile-and-test.sh --with-native-compile` from the package root with Emacs 31.1.50.
Each environment used `HOME=/tmp/cci-implement8.HZnyhh` and an explicit `EMACSLOADPATH`.
Neither load path included any terminal library.

| Environment | Byte compilation | Native compilation | ERT expected | ERT unexpected | Explicit skips |
|---|---|---|---:|---:|---:|
| Optional dependencies present | Exit 0 | Exit 0 | 884 | 0 | 2 |
| Optional dependencies absent | Exit 0 | Exit 0 | 873 | 0 | 13 |

Both runs collected 886 tests.
Each compiler run reported 69 byte-compilation warning lines and 104 native-compilation warning lines.
These are not warning-free results. No new warning suppression was added.
Warnings include test-local bindings and unresolved optional or cross-module symbols.

The shared dependency root was `/Users/fuyu0425/.emacs.d.spacemacs-32/elpa/31.1/develop/`.
Both environments included these directories, followed by the standard Emacs load path:

- `llama-20260601.1455`
- `transient-20260825.819`
- `with-editor-20260731.2234`
- `dash-20260221.84621`
- `persist-0.8`
- `avy-20241101.1357`
- `cond-let-20260817.452`

The dependency-present environment also included:

- `magit-20260822.1158`
- `magit-section-20260731.2248`
- `websocket-20260301.157`
- `web-server-20210708.2242`

The two shared skips were `claude-code-ide-test-flymake-diagnostics` and `claude-code-ide-test-open-file-text-patterns`.
The absence environment also skipped the real WebSocket check and ten explicitly guarded native Magit checks.
Those eleven checks executed in the dependency-present run.
The headless Worktrunk planner and package-owned failure/cancellation checks executed in both environments.

The first full run found ten fixture failures.
Integration corrected native-function signatures and remote fixtures that lacked Ghostel mode.
Window checks now observe real windows instead of incomplete native-function mocks.
The obsolete Codex keybinding-call assertion was removed rather than preserved as a wiring test.

The final parent ERT run passed 58 checks with zero unexpected results after formatting and both package gates.

### Native observations before the computer restart — 2026-09-12–13

The disposable graphical Emacs used final package source, Emacs 31.1.50, and Ghostel native module 0.53.0.
The package source loaded through `emacsclient`. The user's normal Emacs was not reloaded.
The disposable terminal Emacs also used final source and Ghostel, without a graphical display.

- OMP and OpenCode started in the empty disposable project and rendered the requested `CCI008_OK` response.
- OpenCode continue and resume restored that response through their existing entrypoints.
- OMP continue restored it in terminal Emacs. OMP resume showed its current-folder picker and restored the selected disposable conversation.
- Native construction observed `PI_FORCE_IMAGE_PROTOCOL=kitty` in graphical Emacs and `off` in terminal Emacs.
- Claude Code and Codex reached their workspace trust prompts. The user explicitly chose to leave both prompts unanswered.
- Pi remained blocked by the previously recorded installed-runtime failure. No installation or runtime change was attempted.
- OMP accepted text through the package clipboard command and rendered `CCI008_CLIP`.
- OMP also displayed the generated blue test image as an attached-image preview.
- Clipboard verification restored every saved pasteboard item and representation exactly, with a change-counter guard.
- OMP accepted one interruption and entered and exited Ghostel copy mode while its Agent process remained live.

All six native layout presets passed placement, selected-window, sibling-switch, saved-layout precedence, and explicit-reset checks.
Screenshots confirmed both sides for Magit, shell, and Dired companions.
The same live Agent process survived every layout check.
The two same-directory Sessions owned distinct companion shells.
Manager-focus preservation also passed.
The user approved exit of only the OMP companion shell.
After that exit, switching did not report a live shell or create a replacement.
An explicit reset created a live replacement and preserved the Agent.

The 90-column generic popup exceeded the narrow test frame's remaining minimum widths.
The direct Emacs `display-buffer-in-side-window` primitive reproduced the same error without terminal code.
Increasing the test frame width allowed the unchanged popup request and persistent startup to succeed.

Local persistent target `cci-omp-persistent-UehXxI` retained Agent PID `26338` after detach.
Its client count reached zero.
Reattachment changed the local attachment ID while preserving that persistent target.

The user approved remote test directory `ramhorn:/tmp/cci008-HZnyhh` and target `cci008-HZnyhh-omp`.
Read-only discovery had found two pre-existing remote Sessions. The test did not select either one.
The new remote OMP Agent rendered `CCI008_REMOTE_OK` through Ghostel.
Detach reduced its client count to zero and preserved Agent PID `4191941`.
Explicit reattachment preserved attachment ID `cci008-remote-HZnyhh` and the same persistent target.
Remote project views remained disabled throughout these terminal checks.

The computer restart removed the disposable local Emacs instances and `/tmp/cci-implement8.HZnyhh`.
The screenshots, scripts, and raw logs in that temporary directory are no longer available.
The results above come from the observed tool output before the restart, not from a new run.
The streaming-resize check had started, but its result was not collected before the local Emacs exited.
Native scrolling, complete missing-buffer recovery, and explicit persistent Stop still need final acceptance evidence.
The old local process IDs must not be reused for cleanup.
The remote disposable target requires a fresh identity check before cleanup.

### Native recovery observations — 2026-09-13

A new disposable graphical Emacs loaded the same final source through `emacsclient`.
It used Emacs 31.1.50 and Ghostel native module 0.53.0.
No permanent code changed after the full quality gates.

- An OMP sampler observed a partial rendered response and an active working state.
- It resized the frame and sent interruption input while preserving the exact live process.
- The recorded result was `(:partial-response t :working t :resized t :interrupted t :process-preserved t)`.
- This proves interruption input during partial rendering. It does not prove that generation stopped before the response's final number.
- OMP copy mode moved the window start from 1 to 69. Copy-mode exit restored input and preserved the process.
- A native focus change updated OpenCode's focus-suppression timestamp without marking the Session as working.
- OpenCode accepted text through the package clipboard command and rendered the requested numbered response.
- Native PageUp changed the visible output from lines 73–100 to lines 58–87.
- OpenCode entered and exited Ghostel copy mode while preserving its process.
- Two closely spaced Escape keys interrupted a later response after number 1005. The native display reported `interrupted`.
- Image-preview evidence remains OMP-only. The automated checks preserve the existing Agent image-capability limits.

The missing-buffer layout check closed the exact owned companion shell and removed its dead buffer.
Switching to the saved layout did not create a replacement or change the Agent process.
An explicit reset created a new live companion buffer and preserved the Agent.
This exercises section 7's closed-disposable-companion recovery case.

The generic popup appeared on the right at 90 columns.
With `claude-code-ide-focus-on-open` disabled, it preserved the selected origin window.
With that option enabled, it selected the popup.
The earlier six-preset, saved-layout, manager-focus, and companion-reuse evidence remains valid.

The recovery local target `cci-omp-project-NE9NGE` had Agent PID `57529`.
The real Stop prompt named that exact target and warned about all attached clients.
Confirmed Stop removed the target, attachment process, buffer, and Session registry entry.
Other local persistent identities, OpenCode, the remote attachment, and the companion shell survived that Stop.

Fresh remote discovery confirmed that `cci008-HZnyhh-omp` still had PID `4191941` after the computer restart.
The real Stop prompt named `ramhorn`, the exact target, and the effect on every attached client.
Confirmed Stop removed the remote target, attachment process, buffer, Session registry entry, and manager row.
The two pre-existing remote targets retained their names, PIDs, and creation identities.
OpenCode and the companion shell survived the remote Stop.
Remote project views stayed disabled.

Local detach and reattach evidence came from the pre-restart target.
The recovery target supplied the local confirmed-Stop evidence.
Local reattachment changed the attachment ID but preserved the persistent Agent.
Remote reattachment preserved both the persistent Agent and its attachment ID.
These checks used requested attachment connections. They did not introduce replacement Agents or unrequested project-view connections.

### Final maintained-file inventory — 2026-09-13

The independent inventory and the integration review found zero active retired support paths.
The scope includes package code, tests, hidden automation, maintained documents, feature artifacts, and both named parent consumers.
Ignored `refs/`, `ref-docs/`, and `.omp/` contain no tracked files and remain outside this cleanup.

Retained lexical matches occur in these seventeen maintained files:

| Files | Retained-reference reason |
| --- | --- |
| `README.org`, `TODOs.org` | Explicit removal distinction and completed removal backlog record. |
| `claude-code-ide-tests.el` | One negative migration regression proves that removed preferences are inert. It implements no retired terminal. |
| `.specify/memory/constitution.md` | The required governance amendment records the removal. |
| `specs/003-attach-remote-agents/{plan,quickstart,tasks}.md` | Explicit removal records distinguish prior validation from current support. |
| `specs/006-sidebar-detail-view/checklists/requirements.md` | A removal note identifies the earlier terminal-neutrality policy as superseded. Checklist markers remain unchanged. |
| `specs/007-add-layout-presets/{quickstart,tasks}.md` | Explicit removal records distinguish the earlier terminal coverage. |
| `specs/008-remove-legacy-backends/{data-model,plan,quickstart,research,spec,tasks}.md` | Documents for this removal. |
| `specs/008-remove-legacy-backends/contracts/elisp-surface.md` | The removal contract lists deleted interfaces. |

Generic provider, image-protocol, Git, and remote-file uses of “backend” are unrelated and remain unchanged.
The fresh C5 check found all thirteen deleted interfaces absent from variable, function, and customization state.
The constitution, maintainer guide, feature specification, and reviewer checklist retained their captured hashes.
The integration review also clarified historical records in features 003 and 006 without changing their checklist markers.

A fresh independent review included the subsequent feature 003 and 006 documentation changes.
Both parent consumers had zero retired-product or removed-interface matches:

- `/Users/fuyu0425/.spacemacs.d-30/lisp/pkgs/pkg-claude-code-ide.el`
- `/Users/fuyu0425/.spacemacs.d-30/tests/pkg-claude-code-ide-test.el`

### Actual persisted-layout restart — 2026-09-13

The nonpersistent local attempt discarded its layout at shutdown and did not establish restart acceptance.
The user then approved target `cci008-restart-omp` in `ramhorn:/tmp/cci008-restart`.
It ran `/home/yufu/.bun/bin/omp` with Agent PID `30523`.

Emacs PID `35331` attached through Ghostel and saved the remote layout with the production manager persistence function.
Persistence used an isolated directory under the disposable `user-emacs-directory`.
After Emacs exited, a separate process confirmed that the persisted file still contained the window state and old terminal buffer name.

Fresh Emacs PID `48268` loaded that state through the production manager load function.
The saved layout existed, but the old terminal buffer and live Session did not.
The manager row correctly reported a disconnected Session.
No companion existed.

Fresh discovery found the same remote PID with zero attached clients.
The existing reattach and Session-switch commands restored a fresh Ghostel terminal under attachment ID `cci008-restart-remote`.
The selected window showed the current Agent.
No companion replacement occurred, and remote project views remained disabled.
Native screenshots confirmed the layout before and after the actual editor restart.

The real Stop confirmation then removed only this approved target.
Fresh discovery confirmed target absence and unchanged identities for the other remote targets.
The empty remote directory and local restart directory were removed.
The final disposable Emacs exited with code 0, and the final clipboard comparison passed.

### Final acceptance matrix (T036) — 2026-09-13

This matrix covers all fifteen requirements, seven success criteria, fourteen acceptance scenarios, and eight edge cases.
`PASS` means completed evidence supports the outcome.
`PARTIAL` means completed evidence exists, but a named native check remains incomplete.
`BLOCKED` means an external prerequisite prevents the required complete scenario.

One external prerequisite remains after the renewed verification below:

- Pi starts on Node 25.9.0, but its OpenAI Codex OAuth refresh fails with `401 invalid_refresh_token`. The user chose to leave that login unchanged.

The verification did not change Pi, Node, or any login, did not bypass provider safety checks, and did not treat this gap as a native pass.

#### Functional requirements

| FR | Status | Evidence |
| --- | --- | --- |
| FR-001 | PASS | One shared Ghostel construction path remains. OMP, OpenCode, Pi, Claude Code, and Codex passed native launch, continue, and resume. |
| FR-002 | PASS | The final runtime and maintained-file inventories found no retired creation, recognition, input, display, hook, cleanup, alias, or workaround support. |
| FR-003 | PASS | The negative migration regression proves obsolete preferences are inert. The fresh C5 probe found the deleted interfaces absent. |
| FR-004 | PASS | Full ERT gates and native checks cover surviving operations for all five Agents. Image preview passed for OMP, Claude Code, and Codex. |
| FR-005 | PASS | Local and remote detach, reattach, and confirmed Stop retained their ownership rules. Fresh inventories proved unrelated targets survived. |
| FR-006 | PASS | Six presets, focus, companion reuse, reset, popup behavior, and same-process recovery passed. The retained remote layout also recovered across an actual editor restart. |
| FR-007 | PASS | Package loading and Session lookup passed without terminal libraries. Terminal use reported missing support without installation or substitution. |
| FR-008 | PASS | Eight startup safety checks passed, including invalid directories, constructor failures, replacement ownership, and unsupported-buffer rejection. |
| FR-009 | PASS | Remote admission and project-view independence regressions passed. Native attachment succeeded with remote project views disabled. |
| FR-010 | PASS | Both terminal-free quality gates passed. The present environment executed eleven optional integration checks that the absent environment skipped. |
| FR-011 | PASS | The final maintained-file inventory includes hidden automation, prior feature records, governance, backlog, and both parent consumers. No active support promise remains. |
| FR-012 | PASS | README requirements and the fork comparison identify Ghostel-only support. Installation, configuration, and troubleshooting agree. Original attribution remains intact. |
| FR-013 | PASS | Residual references belong to explicit removal records or the negative removal regression. None retain an operational compatibility path. |
| FR-014 | PASS | The required constitution amendment preceded implementation. The captured hash confirms preservation of that user-owned amendment. |
| FR-015 | PASS | The shared runtime adds no Agent-specific terminal policy. External packages, unrelated terminal workflows, and Git history remain outside the change. |

#### Success criteria

| SC | Status | Evidence |
| --- | --- | --- |
| SC-001 | PASS | All five Agents passed native launch, continue, and resume without terminal selection. Pi's model reply is blocked only by its expired OAuth login. |
| SC-002 | PASS | All six native presets passed placement, focus, restoration, and live companion reuse without restarting the Agent. |
| SC-003 | PASS | Missing-support and startup-failure checks preserved existing Sessions and reported the failure without installation or target substitution. |
| SC-004 | PASS | The combined maintained-file inventory found zero active retired support, dependencies, examples, or promises. |
| SC-005 | PASS | README requirements and the fork comparison state the same sole terminal requirement. The documentation inventory found no conflicting current instructions. |
| SC-006 | PASS | Local and approved remote lifecycle checks passed. Requested reattachment created no replacement Agent or unrequested project-view connection. Real Stop confirmations remained intact. |
| SC-007 | PASS | Both byte/native compilation gates exited 0 with zero unexpected ERT results. Terminal-free loading passed. The warning counts remain recorded above. |

#### User Story 1 acceptance scenarios

| Scenario | Status | Evidence |
| --- | --- | --- |
| US1.1 | PASS | All five Agents passed launch, continue, and resume through the package entry points. |
| US1.2 | PASS | Native text paste, interruption, scrolling, copy mode, and keyboard focus passed for Pi, Claude Code, and Codex. Image paste passed for Claude Code and Codex, the Agents the package forwards images to besides OMP. Streaming working state passed for Claude Code and Codex. Pi's reply is blocked by its OAuth login, not by the terminal. |
| US1.3 | PASS | Six native presets retained placement, selected windows, saved-layout precedence, and live companion reuse. |
| US1.4 | PASS | Persistent Agent identity survived detach and reattach. Local attachment IDs may change. Remote attachment IDs stayed stable. Confirmed Stop preserved exact ownership. |
| US1.5 | PASS | Remote boundary regressions and native disabled-project-view checks preserved independent terminal access without local substitution. |

#### User Story 2 acceptance scenarios

| Scenario | Status | Evidence |
| --- | --- | --- |
| US2.1 | PASS | Runtime, tests, dependency discovery, automation, and parent consumers contain no active retired support. |
| US2.2 | PASS | The migration regression proves that obsolete preferences neither select a retired terminal nor restore an alias. |
| US2.3 | PASS | Loading and Session lookup work without Ghostel. Terminal use reports `Install Ghostel before starting a terminal`. Native-absence regressions also pass. |
| US2.4 | PASS | Invalid-directory and startup-failure regressions report failure without successful Session registration, target substitution, or damage to existing Sessions. |
| US2.5 | PASS | Unsupported-buffer and stale-owner regressions prevent adoption, input, activity transfer, and cleanup of unrelated buffers. |

#### User Story 3 acceptance scenarios

| Scenario | Status | Evidence |
| --- | --- | --- |
| US3.1 | PASS | The README explicitly states the fork's Ghostel-only distinction and preserves original attribution. |
| US3.2 | PASS | Maintained requirements, installation guidance, examples, feature descriptions, and troubleshooting no longer recommend retired support. |
| US3.3 | PASS | Prior feature documents, backlog, comments, maintainer guidance, and governance were included. Historical references now identify the removal explicitly. |
| US3.4 | PASS | The required governance amendment was complete before implementation authorization and remains unchanged. |

#### Edge cases

| Edge | Status | Evidence |
| --- | --- | --- |
| Edge 1 | PASS | The negative migration regression proves old global and per-Agent preferences cannot revive retired support. |
| Edge 2 | PASS | Missing-library, missing-native, and startup-failure checks preserve loading and existing Sessions while reporting the requested operation's failure. |
| Edge 3 | PASS | A retained remote layout survived editor shutdown. Fresh Emacs reported the missing terminal as disconnected, then explicitly restored Ghostel without a companion replacement. |
| Edge 4 | PASS | Ownership regressions separate Agent Sessions from ordinary shells and unsupported buffers. Native Stop checks preserved unrelated persistent targets. |
| Edge 5 | PASS | Remote admission and failure regressions reject unapproved or unavailable targets without local fallback or automatic installation. |
| Edge 6 | PASS | Height-only reflow during Claude Code streaming kept width 85, preserved the process, and produced no false working state. Codex reported working state during streaming and honored escape after the resize. |
| Edge 7 | PASS | The final inventory includes prior feature documents, hidden automation, test helpers, and dependency scripts. |
| Edge 8 | PASS | The inventory distinguishes terminal support from unrelated lexical matches and preserves those unrelated meanings. |

#### Final status

44 of 44 outcomes are `PASS`.

T014 and T036 are complete. Section 1 names Ghostel and the Agent CLI as the native prerequisites, and both were available for every Agent.
Pi's expired OpenAI OAuth login is the only external gap. It blocked Pi's model reply, so Pi's streaming and working-state rows rest on Claude Code and Codex evidence. The login is outside the terminal cutover and was left unchanged.

### Renewed Agent verification — 2026-09-13

The requested retry in the configured shell used Node 20.19.5 and failed because `node:fs` did not export `globSync`.
The installed Pi 0.85.1 package requires Node 22.19.0 or newer.
The user supplied `/opt/homebrew/bin/node`, which reports version 25.9.0.
That runtime successfully ran Pi 0.85.1.
A disposable launcher pins Pi to that executable without changing global Node settings.

The user explicitly approved the new Claude Code and Codex workspace trust prompts.
Both native prompts were accepted for their respective disposable project directories under `cci008-agents-_d131n54`.
No global permission bypass was enabled by this verification.
Each Agent now starts from a neutral editor buffer, with its recorded CLI type checked against the requested Agent.
The renewed native checks supersede the earlier Pi and trust blockers.

#### Renewed native results — 2026-09-13

- Launch: Pi, Claude Code, and Codex started in `ghostel-mode` with the expected CLI type. Claude Code and Codex replied `CCI008_CLAUDE_OK` and `CCI008_CODEX_OK`. Pi rendered its UI and reported the OAuth refresh failure.
- Clipboard text: a disposable `CCI008_CLIP_DRAFT` pasted into all three Agents. Interrupt cleared every draft and preserved every process. The user clipboard was restored byte for byte.
- Clipboard image: a disposable PNG pasted as `[Image #1]` in Claude Code and Codex.
- Streaming and resize: Claude Code printed 1 to 120 while a height-only resize (41 to 37 rows) kept width 85 and the same process. A second run was interrupted with escape after partial output. Codex streamed prose with working state `t`, then honored escape after a height resize (34 to 37 rows) and showed `Conversation interrupted`.
- Scrolling and copy mode: all three Agents entered copy mode, scrolled the window start backward, survived an idle height resize, and returned to `semi-char` input with live processes.
- Focus: `C-x o` selected each Agent window without a false working state. Pointer clicks from the desktop automation tool did not reach the frame. That is a tool delivery limit, not a package behavior.
- Continue and resume: after a full editor restart, `claude-code-ide--start-session` with `continue` reopened each prior conversation. Stop then `resume` showed each Agent's session picker, and the package return command selected the prior session.
- Two Claude Code prompts were rejected by the provider's safeguard filter. That is an external model response and is unrelated to the terminal.
