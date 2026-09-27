# Quickstart: Remote Image Paste

Runnable checks for this feature, in the order that finds a fault cheapest. Steps 1
and 2 run without a terminal. Steps 3 to 6 need a live Emacs, Ghostel, and one
approved remote host.

Paths used below:

```text
package repo:  /Users/fuyu0425/.spacemacs.d-30/site-lisp/claude-code-ide.el
Ghostel repo:  /Users/fuyu0425/.spacemacs.d-30/site-lisp/ghostel
OMP repo:      /Users/fuyu0425/agents/oh-my-pi
```

## Prerequisites

1. Build Ghostel with the pinned direct Zig `TerminalStream.Handler.paste` and clipboard-read support.
2. Install OMP with the verified-transfer receiver profile on the remote host.
   Base OSC 5522 support alone is insufficient.
3. The remote host is already in `claude-code-ide-remote-hosts`, and stock `zmx` is
   installed there. This is the same host used for feature 013.
4. A screenshot or any image is on the clipboard.

## 1. Ghostel protocol checks

```sh
cd /Users/fuyu0425/.spacemacs.d-30/site-lisp/ghostel
make test-zig
make test-native
```

Expected: the Zig tests cover the paste-event packet (MIME list, grant, terminators),
the granted read reply (MIME selection, 4096-byte chunking, ordering), the refusal for
a missing or spent grant, the refusal for an unavailable MIME, and the bracketed-paste
fallback when the mode is off. All pass. The native and Elisp suites pass with the
existing OSC 52 tests unchanged.

## 2. Package batch checks

```sh
cd /Users/fuyu0425/.spacemacs.d-30/site-lisp/claude-code-ide.el
emacs -batch -l ert -l claude-code-ide-tests.el \
  --eval '(ert-run-tests-batch-and-exit "claude-code-ide-test-session-paste")'
./scripts/compile-and-test.sh
```

Expected: the route cases pass (local Session unchanged, remote and capable uses the
terminal paste, each refusal explains and sends nothing), the existing paste tests pass
unchanged, byte-compilation is clean, and the full suite passes.

## 3. Local parity check

In a live Emacs, with Ghostel loaded:

1. Start a local `omp` Session.
2. Copy a screenshot. Press `s-v` in the Session buffer.
3. Confirm the Agent reports an image attachment with the expected dimensions.

Expected: unchanged behavior. The package still sends `C-v` for a local Session, and
the Agent reads the local clipboard itself. Nothing in the terminal path is involved.

Repeat with `claude` and `codex` for one text paste and one image paste each. Expected:
unchanged behavior for both.

## 4. Remote end-to-end check

This is the check the feature exists for.

1. Start an Agent on the remote host: `C-u M-x claude-code-ide-attach`, select the
   approved host, select the `omp` Session, attach it.
2. Wait for the Agent prompt to appear in the Ghostel buffer.
3. Copy a screenshot on the local machine.
4. Press `s-v` in the remote Session buffer.
5. Wait up to 10 seconds.

Expected:

- The Agent reports an image attachment, exactly as a local Agent does.
- The attachment carries the image's true dimensions and usable contents.
- Compare the source image bytes with bytes at the Agent's MIME input boundary before its normal image processing.
- Matching dimensions alone does not prove byte preservation.
- The transport creates no image file, and the Session's working directory stays unchanged.
  Distinguish ordinary Agent attachment artifacts from transfer-created files.
- No cleanup step is required.

## 5. Large-image check

1. Copy a screenshot of at least 5 MB, for example a full retina capture.
2. Paste it into the remote Session.

Expected: the attachment arrives within 10 seconds and remains usable on the supported route.
This is a measured acceptance target, not a hard display deadline across system suspension.
The package adds no image-size cap. The Agent's existing attachment rules still apply.

## 6. Failure checks

Each failure on the new image route produces an explanation and leaves the Session usable.
Preflight refusals send nothing. Transfers that fail after transmission starts must produce no partial attachment.
The unsupported-CLI and text-only cases below preserve existing behavior instead.

| Condition | How to create it | Expected |
|---|---|---|
| Terminal lacks native support | Load an older Ghostel build | The Session says the installed build cannot deliver clipboard images, and names the alternative |
| Local client is not the input leader | Attach to the same remote Session from a second terminal, then paste in Emacs | The Session names the leadership condition and the action that restores delivery |
| CLI has no client-side implementation | Attach a `claude` Session on the remote host and paste an image | Behavior stays unchanged for that Agent. No new message appears. |
| Clipboard holds text only | Copy text and press the gesture | Normal text paste, exactly as today |
| Clipboard is empty | Clear the clipboard in the supported remote OMP case and press the gesture | An explanation, and no attachment |
| GUI selection is unavailable | Use a terminal-only Emacs for the supported remote OMP case | An explanation, and no attachment |
| Advertised image cannot be read | Make the selection unavailable before the granted read | An explanation, and no attachment |
| Connection fails after possible delivery | Interrupt only the controlled connection | Delivery unconfirmed when attachment remains possible. No retry or partial image attachment. |
| Receiver preparation exceeds its deadline | Delay the controlled receiver preparation | No editor commit and an expiry explanation. |
| A second gesture overlaps an active attempt | Paste again before the first attempt finishes | A busy explanation. The first attempt remains unchanged. |
| OMP lacks the verified profile | Use an OSC 5522-only receiver in the controlled fixture | A receiver-upgrade explanation and no image bytes. |

## Evidence to record

- The Zig and native test command output from step 1.
- The ERT selector output and the full gate result from step 2.
- The local Session transcript from step 3, showing the attachment and its dimensions.
- The remote Session transcript from step 4, showing the attachment, plus the remote
  directory listing before and after.
- The timing observed in step 5.
- The observed outcomes from step 6, including unchanged behavior where required.

## Prerequisite check record: 2026-09-26

These are prerequisite checks, not the completed live image-paste walkthrough.
Details and source references are in [research.md](research.md#checks-after-the-users-stock-zmx-upgrade).

| Check | Result |
|---|---|
| Installed stock zmx | Local and `v12mac`: 0.8.1. `ramhorn`: 0.8.0. |
| Existing daemon query support | All six inspected Sessions answered `print-env`. Exact daemon versions and their replay behavior were not inferred. |
| Existing attachment identity | None of the returned tracking lists contained the package fixture marker. Package integration remains necessary. |
| New attachment to an existing stock daemon | The disposable 0.8.1 check exposed the new leader marker without restarting the fixture Agent. |
| Mode replay | The disposable second attachment received mode 5522. |
| macOS GUI bytes | A 75-byte synthetic PNG returned as an unibyte string through `image/png`, with exact byte equality. |
| Clipboard restoration | Every original representation matched after restoration. |
| Missing-reply timeout before receiver extension | The original OMP controller reported no status after 10,504 ms. It attached no image. |
| Ghostel candidate build | Migrated pin `e424060...`. Zig 0.16.0 build and Zig checks passed in `zig-out`. |
| Ghostel regression checks | Per-file Elisp/native runs: 1191 selected, 1183 expected, 0 unexpected, 8 skipped. |
| Terminal smoke | Real shells through native and Emacs PTYs returned `received:migration-smoke`. |
| Native clipboard handoff | Proposed owned-action bridge only. Clipboard exchange implementation remains gated by T005. |
| End-to-end timeout before receiver extension | The original OMP had no receiver deadline. A host timeout cannot withdraw queued bytes. |

No existing Session was restarted or detached.
No image reached a remote host during these checks.
Those earlier checks changed no zmx or OMP source and installed no native module.

## Receiver prerequisite record: 2026-09-26

T005R now has receiver-to-editor evidence from the actual local OMP CLI.
The receiver checks identity, MIME, byte count, SHA-256, and expiry before its synchronous editor commit.
Local and legacy paste routes remain separate from this verified profile.

- Final focused regression gate: 240 passed across 12 files after the lifecycle correction.
- After the CLI exposed a late-start subscription bug, the receiver, editor, and lifecycle gate passed all 115 checks.
- Coding-agent and TUI type checks passed.
- The actual local CLI displayed image `#1` from 1108 synthetic bytes after 40 ms.
- A one-millisecond expired transfer reserved no image number.
- The next image contained 5244372 bytes and displayed as `#2` after 709 ms. No image `#3` appeared.
- The check supplied no credentials, selected no provider, and submitted no model turn.
- The helper stopped only its own process and removed its private temporary home.

The user approved skipping optional setup in that disposable process.
This proves the receiver path, not remote delivery or Agent vision acknowledgement.
The original end-to-end acceptance checks remain open.
See [the detailed receiver evidence](research.md#t005r-verified-receiver-and-actual-editor-boundary).

## US1 package test baseline

T007 added route invariants with real Session records and mocked public Ghostel operations.
The focused ERT selector `claude-code-ide-test-session-paste-clipboard` ran 11 checks before production route changes.
Eight existing-route checks passed.
Three remote OMP checks failed because the current route still sends raw `C-v`.
These are the expected failing-before checks for terminal image routing, missing capability, and provider refusal.
The native provider and production package route remain incomplete.

The first batch command omitted the installed `with-editor` dependency and stopped before ERT.
The corrected command used dependency paths from live Emacs's `locate-library`, without loading or changing the live configuration.

## US1 host correction record

The candidate Ghostel provider built with Zig 0.16.0. Its Zig checks passed.
The existing mouse and paste file passed all 85 checks.
The OSC file passed 60 checks and failed three new real-PTY cases.
The actual local Ghostel-to-OMP smoke also failed. It does not establish host-to-editor delivery.

The failures exposed different references to an attempt plist after code added missing properties.
That broke attempt identity and timer cleanup.
Source review also found process-replacement, image-alias, and blocked event-pipe boundaries that need corrections.
The correction slices must finish before another integrated gate.

The candidate module remains in `../ghostel/zig-out`.
These checks installed no module, changed no existing Session, and sent no image to a remote host.

## Integrated local provider record

The corrected provider passed all 69 OSC checks, including generated five-MiB transfers through both PTY paths.
Zig build and Zig checks passed. The intentional closed-pipe check emitted a warning.
The Windows cross-build passed. No Windows runtime check ran.

The actual local OMP CLI displayed these synthetic images:

| PTY | Image bytes | Visible after | Payload reads |
|---|---:|---:|---:|
| Emacs | 1108 | 68 ms | 1 |
| Emacs | 5244372 | 3767 ms | 1 |
| Native | 1108 | 36 ms | 1 |
| Native | 5244372 | 709 ms | 1 |

The Emacs writer first expired after queuing about 438 KB in ten seconds.
[Emacs waits 20 ms after write backpressure](https://github.com/emacs-mirror/emacs/blob/emacs-30/src/process.c#L6843-L6855).
Smaller writes with a short drain opportunity removed that repeated wait without changing the transfer deadline.

A controlled pause of the receiver's input forced real backpressure.
The host retired the blocked writes after 10004 ms and 10013 ms. Both processes stayed alive.
The receiver rejected the expired transfer without an attachment.
The next fresh gesture produced image `#3` through each PTY path.

That recovery check exposed an incomplete OSC packet that consumed the next paste header.
The TUI parser now discards the interrupted packet and preserves the new escape sequence.
The parser and bracketed-paste files passed 96 checks after the correction.

The smoke used private temporary homes and synthetic clipboard callbacks.
It selected no provider, supplied no credentials, submitted no model turn, and changed no existing Session.
This proves local provider-to-editor delivery and recovery, not remote delivery or Agent vision acknowledgement.

### Package route and interactive cancellation

The package route passed all 11 focused clipboard cases.
A fresh interactive Emacs then called `claude-code-ide-session-paste-clipboard` with real Session records and the candidate Ghostel module.
Its synthetic host metadata selected the remote route, but both disposable Agents ran locally.

| PTY | Small image | 5244372-byte image | Blocked-write expiry | C-g cancellation |
|---|---:|---:|---:|---:|
| Emacs | 68 ms | 3944 ms | 10048 ms | 252 ms |
| Native | 35 ms | 699 ms | 10012 ms | 251 ms |

Both C-g checks used an actual SIGINT while the receiver paused input.
Each check caught `quit`, retired the attempt, and preserved the Agent process.
Neither interrupted transfer became an attachment.
A fresh gesture after expiry produced image `#3`.
A fresh gesture after cancellation produced image `#4`.
The driver reported `INTERACTIVE_EMACS_EXIT=0` and the complete `CCI014_HOST_RECEIVER_SMOKE` result.

The first interactive launch failed because the user launcher added an unsupported `--with-profile` option.
The successful driver used the installed Emacs executable directly.
It disabled optional native Lisp compilation in the disposable process after compiler failures obscured an earlier run.
These fixture changes did not change the user's launcher, live Emacs, or feature code.

## Remote delivery and reattachment record

The user approved two disposable Sessions on `v12mac`, synthetic PNGs, and a private candidate OMP binary.
The probe used stock zmx 0.8.1, the candidate Ghostel module, and two fresh Emacs processes.
It called the actual package paste command.
It skipped optional setup and submitted no model turn.

| Gesture | Session | Attachment | Original bytes | Visible after |
|---:|---|---:|---:|---:|
| 1 | A | 1 | 1172 | 52 ms |
| 2 | B | 1 | 1684 | 52 ms |
| 3 | A | 2 | 1236 | 34 ms |
| 4 | B | 2 | 1748 | 59 ms |
| 5 | A | 3 | 1300 | 33 ms |
| 6 | B | 3 | 1812 | 77 ms |
| 7 | A | 4 | 1364 | 37 ms |
| 8 | B | 4 | 1876 | 54 ms |
| 9 | A | 5 | 5244372 | 1540 ms |
| 10 | B | 5 | 1940 | 48 ms |

Emacs PID 1435 performed gestures 1–5. Emacs PID 15761 performed gestures 6–10.
The second Emacs used `zmx attach NAME false`.
Ghostel recovered mode 5522 and the prior attachments before the probe sent any Agent input.
The Agent PIDs, working directories, and creation times stayed unchanged.
Each gesture read one payload and preserved the other Session's attachment count.

Remote SHA-256 checks matched all ten original clipboard payloads.
The large image retained its 1280-by-1024 dimensions.
Its SHA-256 was `8ff6dae06eb3498142c94ede569b25a5d557aa6ba06bf8723808c73c4455c009`.
OMP's existing image rules enlarged small editor previews, but its stored original bytes still matched.

The file comparison found only ordinary OMP `local://pasted-image-*` attachment files.
`InputController.#persistPastedImage` creates these files after verified receipt.
The probe found no new file outside that Agent storage in the private workspace, home, state, cache, and temporary directories.
The first probe incorrectly treated permitted Agent storage as a transport failure.
Direct hash checks validated its five completed transfers.
The corrected second probe checked the storage location and all five hashes, then exited successfully.

The package ordering check also passed.
It alternated ten gestures across two host/directory identities and replaced both attachment buffers midway.
A clipboard callback changed the current buffer during every gesture.
All twelve focused package clipboard checks passed.

This record does not establish Agent vision acknowledgement, actual local Claude/Codex parity, or production leadership preflight.

### T014 focused gate

The integrated gate passed after the package ordering test:

- Package clipboard selector: 12 passed, zero unexpected.
- Ghostel `ghostel-osc-test.el`: 69 passed, zero unexpected.
- Ghostel `ghostel-mouse-paste-test.el`: 85 passed, zero unexpected.
- Zig checks: exit zero and `GHOSTEL_ZIG_CHECKS_PASS`.

The native closed-event-pipe case emitted its expected `EventWriteFailed` warning.
The Zig runner still completed successfully.
The Ghostel commands ran each topic in a separate Emacs, as the Makefile does.
They selected `zig-out` rather than installing or loading the candidate in the user's live Emacs.

```sh
# Package root, with the existing dependency directories on load-path:
emacs --batch -Q -L . \
  -L /Users/fuyu0425/.emacs.d.spacemacs-32/elpa/31.1/develop/with-editor-20260731.2234 \
  -L /Users/fuyu0425/.emacs.d.spacemacs-32/elpa/31.1/develop/transient-20260825.819 \
  -L /Users/fuyu0425/.emacs.d.spacemacs-32/elpa/31.1/develop/cond-let-20260817.452 \
  -L /Users/fuyu0425/.emacs.d.spacemacs-32/elpa/31.1/develop/llama-20260601.1455 \
  -L /Users/fuyu0425/.emacs.d.spacemacs-32/elpa/31.1/develop/avy-20241101.1357 \
  -L /Users/fuyu0425/.emacs.d.spacemacs-32/elpa/31.1/develop/persist-0.8 \
  -L /Users/fuyu0425/.emacs.d.spacemacs-32/elpa/31.1/develop/websocket-20260301.157 \
  --eval '(setq load-prefer-newer t)' -l ert -l claude-code-ide-tests.el \
  --eval '(ert-run-tests-batch-and-exit "claude-code-ide-test-session-paste-clipboard")'

# Ghostel root, once for each named topic:
emacs --batch -Q -L lisp -L test \
  --eval '(setq ghostel-module-directory (expand-file-name "zig-out") ghostel-module-auto-install nil load-prefer-newer t)' \
  -l ert -l test/ghostel-test-helpers.el -l test/ghostel-osc-test.el \
  -f ert-run-tests-batch-and-exit
emacs --batch -Q -L lisp -L test \
  --eval '(setq ghostel-module-directory (expand-file-name "zig-out") ghostel-module-auto-install nil load-prefer-newer t)' \
  -l ert -l test/ghostel-test-helpers.el -l test/ghostel-mouse-paste-test.el \
  -f ert-run-tests-batch-and-exit
/Users/fuyu0425/.asdf/installs/zig/0.16.0/zig build test
```

### T015 local parity and clipboard evidence

The disposable local terminals ran Claude 2.1.257, Codex 0.154.0, and the OMP 18.3.2 candidate.
The package retained its existing local `C-v` route.
Each CLI showed an unsent image attachment from the actual system clipboard:

| CLI | First attachment |
| --- | --- |
| Claude | 51 ms |
| Codex | 22 ms |
| OMP | 120 ms |

The generated PNG had red and blue halves, 1280 × 1024 pixels, and 26111 bytes.
Its SHA-256 was `b2d338250b5dec8047aab74df24a302e92f317e3565f766e629ed38f888b4bfa`.
The clipboard helper saved every original pasteboard representation in memory.
After each check, it restored the original clipboard and verified exact equality.
The user approved Claude's trust prompt for the disposable directory only.
The Claude fixture disabled built-in tools. No fixture submitted a model turn.

A second clipboard check offered PNG, TIFF, and plain text together.
Local OMP showed image attachment #2 after 101 ms.
Remote OMP showed image attachment #6 after 177 ms.
The remote route used the actual GUI selection API, SSH, stock zmx, and the candidate receiver.
The GUI returned `[TARGETS image/png STRING image/tiff]`.
The receiver requested one image payload. The provider read that payload exactly once.
The receiver's original-image file matched the PNG byte count and SHA-256 above.
The candidate native module ran only in the disposable Emacs, not the user's live Emacs.

The remote fixture had no model. Its unchanged text route preserved:

- Unicode text: `CCI014_PLAIN_α漢字`.
- A 20-line paste as a text attachment with the `+20 lines` footer.
- A 20000-character paste as a separate text attachment with the character-count footer.
- Raw text: `CCI014_RAW`.

The text checks used a synthetic kill ring and disabled the interprogram paste function.
They did not read the restored private clipboard.
The remote editor retained its six image attachments throughout these checks.
The ten-gesture matrix above proves the separate-client and reattachment cases.
Agent acknowledgement remains unverified because no model turn ran.

### T016 authorization boundaries

The native checks cover missing, unknown, spent, expired, and cross-terminal grants.
They also cover unadvertised MIME types, the primary selection, reset, and mode disable.
New cases send requests without any paste gesture, with mode 5522 both enabled and disabled.
Those requests produce no image data and never call the payload reader.

The Elisp check sends child output through both actual PTY backends without a paste gesture.
It observes zero GUI selection reads and a live process after each request.
The focused `ghostel-test-clipboard` selector passed all 11 tests with zero unexpected results.
The Zig test command completed with the existing closed-event-pipe warning.
No production authorization change was necessary for these cases.

### T017 and T018 identity and lifetime checks

The ten-gesture package test now gives each attachment a distinct live process.
After reattachment, each Session retains its replacement process and buffer.
All four processes stay live until fixture cleanup.
The host, directory, zmx name, destination order, and no-substitute checks also pass.
The package clipboard selector passed all 12 tests with zero unexpected results.

The existing provider retires grants through libghostty's grant store.
Completion, refusal, expiry, reset, process replacement, and buffer destruction invalidate the attempt.
The Elisp provider retains the attempt until its native writer stops.
The focused checks cover callback destruction, replaced identities, failed admission, and interrupted writes.
The interactive record above also proves recovery after deadline expiry and `C-g`.
T016 exposed no additional lifetime gap. T018 therefore adds no second authorization store or cleanup path.

### T019 controlled remote file check

A further synthetic 32 × 32 PNG produced unsent image attachment #7 in disposable Session A.
The provider read its 4196 bytes once.
The SHA-256 was `6b0998f60ed8af8aa1b2f4301956771c4dfc4c24882d4581371a156e3233642d`.

Before and after snapshots covered both workspaces and the private temporary directory.
All 12 existing regular files retained their paths, sizes, and modification times.
Exactly one new file appeared:

```text
/tmp/cci014-remote.hZBRyXU5/tmp/omp-local/01a0dd64-c345-73b2-811d-9fdc2b6f9b28/pasted-image-401a7f96483661e0.png
```

This is OMP's ordinary post-receipt attachment storage, which the spec excludes.
Its SHA-256 matched the generated clipboard bytes.
No transport file appeared in either workspace or elsewhere in the private fixture.
The editor retained its existing text and showed no cleanup prompt.
The clipboard attempt retired, and the attachment process stayed live.

`lsof -a -p38434,38659 -d cwd -Fn` showed unchanged working directories for both Agents.
The zmx records also retained both names, PIDs, creation times, commands, and client counts.
Session A had one client. Session B remained detached with zero clients.

### T020 clipboard isolation and lifecycle preservation

The T016 real-PTY check observed zero GUI selection reads without a gesture.
The native grant checks observed zero payload reads for another terminal's grant.
The real alternating matrix kept each payload in its intended remote Session.

The existing approval and lifecycle selector passed all 22 tests with zero unexpected results.
It covered the host allowlist, isolated control deadlines, login environment, attachment, reattachment, detach, and confirmed or declined Stop.
It also covered late Stop results, exact-target verification, and unconfirmed outcomes.
Those tests used their existing isolated fixtures.
No check changed host permissions, authentication settings, or an unrelated Session.
The actual remote probes retained strict host-key checks and noninteractive SSH authentication.

### T021 refusal regressions before implementation

The package clipboard selector ran 14 tests.
Twelve passed. Two new regressions failed at the intended missing behavior:

- An empty clipboard still called text yank.
- A different input owner still admitted an image.

The new cases also cover an unavailable selection, an empty target vector, a metadata-only vector, and an unmarked attachment.
They require no substitute, no ownership-changing command, and an actionable explanation.
T023 and T024 must make these cases pass before the final gate.

### T022 provider failure checks

The provider refused nil, empty, unavailable, and non-byte image data without an image DATA response.
Each refusal retired its attempt and preserved ordinary terminal input.
The clipboard selector passed all 12 tests with zero unexpected results.
Existing cases cover clipboard replacement, process replacement, callback destruction, and interrupted writes.
The interactive deadline and `C-g` evidence remains above.

The new text check refused unsafe input without a write.
It then accepted ordinary newlines through bracketed paste in the same terminal.
The mouse/paste topic passed all 86 tests with zero unexpected results.
Its two `set-transient-map` deleted-buffer warnings also appeared in the earlier 85-test baseline.

### T023 production attachment marker and ownership check

The production constructor created two marked attachments to the private `cci014-a` fixture on `v12mac`.
Stock zmx 0.8.1 tracked `CLAUDE_CODE_IDE_CLIENT` and retained the default `DISPLAY` tracking.
The package used only the read-only `print-env` control request during each preflight.
The fixture used ordinary unsent text to establish each owner before the measurements.
Those fixture writes were not production probes. Later checks selected the existing owner without typing.

- Image 8: 8292 bytes, one authorized payload read, 185 ms.
- Non-leading client: actionable refusal, zero payload reads, unchanged input owner.
- Image 9 after ordinary input restored ownership: 8292 bytes, one read, 166 ms.
- Both remote Agent PIDs, creation times, commands, and working directories stayed unchanged.
- No model turn ran. These are unsent editor attachments, not Agent acknowledgements.

The command checks execute shell argument boundaries instead of comparing constructed command strings.
They cover literal arguments, empty arguments, inherited tracking, explicit empty tracking, login profiles, and host isolation.
The marker stays on the local attachment process, not in persisted Session data.
An old unmarked attachment must reattach before this route can verify ownership.
The check is point-in-time evidence. It is not an atomic input-owner lock.

### T024 clipboard refusal explanations

The package clipboard selector passed all 16 tests with zero unexpected results.
The supported remote route now refuses empty, metadata-only, unavailable, and absent-GUI selections before any control query or terminal input.
It does not substitute the kill ring for missing clipboard data.
The provider retains separate explanations for missing native support, disabled Agent paste events, and empty or unreadable image bytes.
The same selector verifies unchanged local image, unsupported CLI, and valid text routes.

<a id="refusal-matrix"></a>

### T025–T026 real refusal and recovery matrix

The final package Lisp ran in the owned Emacs daemon against the marked private `v12mac` attachment.
The matrix selected the current owner through `print-env`. It sent no ownership probe input.
Each refusal preserved the owner, live attachment process, and remote file list.
Each refusal cleared the package reservation and Ghostel attempt.

| Condition | Payload reads | Observed outcome |
|---|---:|---|
| Missing public capability function | 0 | Install native support or use a local Session |
| Old native support | 0 | Same actionable refusal |
| Empty or metadata-only selection | 0 | Copy usable image or text |
| Absent GUI or selection error | 0 | Use a graphical clipboard |
| Unreadable image bytes | 1 | Empty/unreadable explanation, no attachment |
| Unreachable control connection | 0 | SSH status 255 and connection/support remedy |
| Quit during the ownership query | 0 | Quit caught, only the owned query process stopped |
| Granted read delayed beyond expiry | 1 | Host delivery unconfirmed, receiver reported expiry, no attachment |

The unreachable fixture disabled SSH connection sharing and used a failing private `ProxyCommand`.
Its first attempt reused an existing SSH connection, so it did not establish unreachable-host evidence.
The corrected fixture failed before authentication and left the existing terminal connection intact.
The quit check completed in 285 ms. The delayed clipboard callback returned after 10610 ms.
That deliberate blocking callback is not a successful-transfer latency result.

The first recovery displayed image 10 but reused an existing content-addressed Agent file.
Its fixture incorrectly required a new file and failed. Agent storage uses `Bun.hash(bytes)` in the ordinary local image URL.
A distinct recovery image then passed the complete package preflight, native transport, receiver, and editor path:

- Image 11: 5248468 bytes, one authorized payload read, visible after 1254 ms.
- Stored original SHA-256: `4badb347737210a700e4009700c1c89fdc98d5bb24e5bb3da900655db50c85d2`.
- The hash matched the synthetic clipboard bytes exactly.
- The original unsent text and earlier attachments remained present.
- No model turn ran.

The existing disconnect and writer cleanup already met T025. No duplicate failure state or retry was added.
The earlier two-PTY backpressure, real `C-g`, and process-loss checks remain part of this evidence.
Command return still means admission only. Ambiguous delivery requires the user to inspect the Agent.

### Withdrawn guidance trial

The user removed SC-007 and its related tasks, T027 and T038.
No unfamiliar-participant trial or 60-second guidance requirement remains.
This removal does not claim a completed usability trial.

## T028 final integrated gates

| Gate | Observed result |
|---|---|
| Package byte compilation and complete ERT suite | 961 passed, 14 skipped, zero unexpected |
| Ghostel `test-all`, including candidate build, Zig, Elisp, and native topics | 1196 ERT checks passed, 8 skipped, zero remaining unexpected |
| OMP receiver, editor, clipboard, lifecycle, and parser regression selection | 381 passed across 14 files, 1833 assertions |
| Coding-agent and TUI type checks | Both passed |
| OMP scoped lint and format checks | Both passed on 11 source and test files |

The package gate ran without adding Ghostel to its dependency load path.
The optional-dependency skips and byte-compiler warnings remain visible in the output.
The Ghostel skips concern optional shell integration and display-dependent behavior.
The Zig closed-event-pipe check emitted its expected warning.

The first complete Ghostel run exposed a child-process fixture problem.
The child ignored the parent's candidate module directory and found the installed 0.53.0 module.
It exited before the VT warning assertion because the Lisp required 0.54.0.
The fixture now passes the selected module directory and disables automatic installation in the child.
The corrected child check and all remaining native topics passed.
The aggregate count excludes repeated debug-topic checks.
No installed native module changed.

Commands, from the corresponding repository roots:

```sh
./scripts/compile-and-test.sh

/usr/bin/env PATH=/Users/fuyu0425/.asdf/installs/zig/0.16.0:/Users/fuyu0425/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  make -k -j4 test-all EMACS=/Users/fuyu0425/bin/emacs \
  "EMACSFLAGS=--eval '(setq ghostel-module-directory \"/Users/fuyu0425/.spacemacs.d-30/site-lisp/ghostel/zig-out\" ghostel-module-auto-install nil)'" \
  MODULE=zig-out/ghostel-module.dylib \
  'ZIG_BUILD_FLAGS=--prefix zig-out -Doptimize=ReleaseFast -Dcpu=baseline'

bun test \
  packages/coding-agent/test/utils/enhanced-paste.test.ts \
  packages/coding-agent/test/input-controller-enhanced-paste.test.ts \
  packages/tui/test/start-listener.test.ts \
  packages/coding-agent/test/utils/clipboard.test.ts \
  packages/coding-agent/test/image-paste-source-path.test.ts \
  packages/coding-agent/test/input-controller-large-paste.test.ts \
  packages/coding-agent/test/input-controller-smart-paste.test.ts \
  packages/coding-agent/test/input-controller-followup-paste-expansion.test.ts \
  packages/coding-agent/test/interactive-mode-editor-component.test.ts \
  packages/coding-agent/test/hook-editor.test.ts \
  packages/coding-agent/test/utils/image-resize.test.ts \
  packages/tui/test/terminal-capabilities.test.ts \
  packages/tui/test/stdin-buffer.test.ts \
  packages/tui/test/bracketed-paste.test.ts
bun run --cwd packages/coding-agent check:types
bun run --cwd packages/tui check:types
```

The scoped style commands were `bunx --no-install oxlint` and `bunx --no-install oxfmt --check`.
Both used these files:

```text
packages/coding-agent/src/utils/enhanced-paste.ts
packages/coding-agent/src/modes/controllers/input-controller.ts
packages/coding-agent/src/modes/interactive-mode.ts
packages/tui/src/tui.ts
packages/tui/src/index.ts
packages/tui/src/stdin-buffer.ts
packages/tui/src/prompt/custom-editor.ts
packages/coding-agent/test/utils/enhanced-paste.test.ts
packages/coding-agent/test/input-controller-enhanced-paste.test.ts
packages/tui/test/start-listener.test.ts
packages/tui/test/stdin-buffer.test.ts
```

## T032 acceptance record

The implementation and automated gates are complete.
The later [approved T039 cleanup](#t039-approved-trust-cleanup) closed the remaining task.
The [authorized live acceptance](#authorized-live-acceptance-2026-09-27-utc) completed three Agent vision turns.
The [private zmx correction](#private-zmx-backpressure-correction-2026-09-27-utc) closed T015 with ten first-gesture successes and exact bytes.

### Functional requirements

| Requirement | Status and observed evidence |
|---|---|
| FR-001 | Editor delivery observed through the [real remote path](#remote-delivery-and-reattachment-record). |
| FR-002 | Passed [local and clipboard parity](#t015-local-parity-and-clipboard-evidence) and the final route selector. |
| FR-003 | Ordinary editor attachments and order observed in the [alternating remote gestures](#remote-delivery-and-reattachment-record). |
| FR-004 | Passed [refusal and recovery checks](#refusal-matrix). Return values never claim acknowledgement. |
| FR-005 | Passed the [workspace, temporary-file, and working-directory check](#t019-controlled-remote-file-check). Only ordinary Agent storage changed. |
| FR-006 | Passed [zero-gesture clipboard isolation](#t020-clipboard-isolation-and-lifecycle-preservation). |
| FR-007 | Passed [grant authorization boundaries](#t016-authorization-boundaries). |
| FR-008 | Passed [real local-GUI-to-remote delivery](#t015-local-parity-and-clipboard-evidence). |
| FR-009 | Passed the [read-only ownership preflight](#t023-production-attachment-marker-and-ownership-check). The query is not an atomic ownership lock. |
| FR-010 | Passed the [receiver commit checks](#receiver-prerequisite-record-2026-09-26), [interactive cancellation](#package-route-and-interactive-cancellation), and [remote expiry check](#refusal-matrix). |
| FR-011 | Passed local/remote OMP acknowledgement and pixel parity in the [authorized live acceptance](#authorized-live-acceptance-2026-09-27-utc). Prior Claude/Codex clipboard evidence remains unchanged. |
| FR-012 | Passed [approval and lifecycle preservation checks](#t020-clipboard-isolation-and-lifecycle-preservation). |
| FR-013 | Passed [package loading, byte compilation, and the complete optional-native gate](#t028-final-integrated-gates). No required dependency was added. |
| FR-014 | Passed [actual text variants](#t015-local-parity-and-clipboard-evidence), [text safety checks](#t022-provider-failure-checks), and the complete package gate. |
| FR-015 | Passed. Three [authorized Agent vision turns](#authorized-live-acceptance-2026-09-27-utc) reported the correct image counts, colors, bar counts, and dimensions. |
| FR-016 | Passed [actual local Claude, Codex, and OMP direct-clipboard checks](#t015-local-parity-and-clipboard-evidence). |
| FR-017 | Passed original-image hash comparisons in the [alternating gestures](#remote-delivery-and-reattachment-record) and [final large-image recovery](#refusal-matrix). |

### Edge cases

| Requirement | Status and observed evidence |
|---|---|
| EC-01 | Passed [PNG, TIFF, and text metadata with a single selected original-image read](#t015-local-parity-and-clipboard-evidence). |
| EC-02 | Passed [5248468-byte recovery in 1254 ms](#refusal-matrix), with an exact original-byte hash. |
| EC-03 | Passed [replacement, unreadable-data, and coherent-read checks](#t022-provider-failure-checks). |
| EC-04 | Passed with private candidates. Separate-client reattachment preserved identity and mode. Both clients stayed attached during the [corrected large-image sequence](#private-zmx-backpressure-correction-2026-09-27-utc). |
| EC-05 | Passed [missing and old native capability refusals](#refusal-matrix) and preserved existing routes. |
| EC-06 | Passed [absent-GUI and unavailable-selection refusals](#refusal-matrix). |
| EC-07 | Passed [Unicode, multiline, large, bracketed, and raw text checks](#t015-local-parity-and-clipboard-evidence). |
| EC-08 | Passed [reattachment identity checks](#t017-and-t018-identity-and-lifetime-checks) and the real second-Emacs check. |
| EC-09 | Passed [ordered distinct gestures](#remote-delivery-and-reattachment-record), reentrant preflight refusal, and provider/receiver busy refusal. |

### Success criteria

| Requirement | Status and observed evidence |
|---|---|
| SC-001 | Passed. Session B received five first-gesture images and acknowledged all five in the [authorized live acceptance](#authorized-live-acceptance-2026-09-27-utc). |
| SC-002 | Passed with private candidates. Two 5245667-byte images arrived unchanged in 1667 ms and 1727 ms with concurrent clients. See the [correction record](#private-zmx-backpressure-correction-2026-09-27-utc). |
| SC-003 | Passed the supported-route [failure matrix](#refusal-matrix). Unsupported CLIs retained their existing behavior. |
| SC-004 | Passed the [complete package gate](#t028-final-integrated-gates), including text, CLI, and keybinding regressions. |
| SC-005 | Passed with private candidates. Ten alternating first-gesture images reached their intended Sessions with matching digests. See the [complete sequence](#ten-alternating-first-gesture-successes). |
| SC-006 | Passed [zero gestures and zero payload reads](#t020-clipboard-isolation-and-lifecycle-preservation). |

### Cleanup and user-session boundary

The original Emacs server remained live with PID 58238.
The verification Emacs and private Codex app server stopped.
Stock zmx confirmed both private remote targets stopped and listed no remaining target in the private namespace.
The private remote root and local parity directory were removed.
Temporary verification scripts, the private candidate OMP binary, and the candidate Ghostel module files were removed.
Normal build caches and research notes remain.
The clipboard probes restored the original clipboard after their controlled checks.
No candidate native module was installed or loaded in the user's Emacs.
No existing user Session was stopped, detached, or restarted.
No commit or push ran.

## Phase 7 implementation checks

The user selected code fixes before the blocked live acceptance checks.
Model turns and user-owned trust settings remained unchanged during this check.

### T033: original paste destination

The three pre-`DONE` destination regressions failed before the fix and passed after it.
The receiver now captures the destination before its verified read request.
The existing transient-Session cleanup and editor replacement paths cancel pending receipt.
Real `InteractiveMode` checks cover editor and viewed-Session switches away and back.
The editor-boundary file passed all 25 tests with 308 assertions.

An independent `bun --eval` receiver smoke sent a complete verified response after a destination change.
It observed zero attachments and an explicit destination-change explanation.
This was a local API check, not a model turn or remote acceptance result.

### T034: disconnect after local writes

The new public-path regression failed before the fix because the Session gave no unconfirmed-delivery explanation.
It passed after the fix through both PTY writers.
Ghostel now retires grants after writing and keeps a separate ten-second process watch.
The watch retains no payload or authorization and does not block another gesture.
Buffer destruction and mode changes cancel the watch.
This corrects the earlier T025 claim that existing writer cleanup covered every disconnect boundary.

A separate fresh Emacs smoke used the real native clipboard exchange and disposable Python receivers.
Both PTY paths reported retired grants and delivery unconfirmed after the owned process disconnected.
No user Session, real clipboard, remote host, installed module, or model turn participated.

### T036: verified image decodability

Before the fix, three nonempty invalid images became attachments despite matching transfer hashes.
The empty-image case already refused the transfer.
The verified route now uses the existing full-decode validator before preparation.
Local and legacy routes retain their existing behavior.
The editor-boundary file passed 30 tests with 358 assertions, including expiry during awaited decode validation.

A separate adapter smoke observed the invalid-image explanation and zero invalid attachments.
The next valid PNG produced exactly one `1x1` image chip with unchanged bytes.
The smoke used a private temporary Agent directory and removed it afterward.

The validated adapter also accepted a generated 5244372-byte PNG in 102 ms.
It displayed `1280x1024` dimensions and preserved every original byte.
The generator used seed `20260926`.
The original SHA-256 was `6290a48a0b6e714511aa57d0c31182d0b98f760ed6d1a54101b3c37337539dd6`.
This measures the local adapter only, not the SSH or GUI clipboard path.

### T037: retained public failure outcomes

Three new native ERT checks passed through both PTY writers in 41.36 seconds.
They exercise real admission expiry, process loss before receipt, and process loss after local write completion.
They verify retired grants, semantic explanations, zero unauthorized payload reads, and usable terminal input after expiry.
They also verify that the post-write observation ends after ten seconds.
The existing mouse-paste cases remain unchanged because these failures belong to the native OSC exchange.

### T040: distinct clipboard conditions

The refusal regression now distinguishes empty data from unavailable GUI access and checks the corresponding remedy.
It does not compare complete message text.
A fresh batch Emacs smoke confirmed the distinct current explanations for empty, unavailable, and absent-GUI selections.
No production message changed.

The initial targeted command lacked installed dependency paths and could not load `with-editor`, then `avy`.
The standard package gate resolved those paths and passed byte compilation and all 961 applicable tests.
It reported 14 optional skips and zero unexpected results.

### Final Phase 7 gates

| Gate | Observed result |
|---|---|
| `./scripts/compile-and-test.sh` | Byte compilation passed. 961 tests passed, 14 skipped, zero unexpected. |
| Ghostel `make -k -j4 test-all` with the isolated `zig-out` module | Zig checks passed. 1199 ERT checks passed, 8 skipped, across 66 isolated test invocations. |
| OMP receiver, editor, clipboard, parser, lifecycle, and Session-focus selection | 421 tests passed across 15 files, with 2030 assertions. |
| Coding-agent and TUI type checks | Both passed. |
| Scoped `oxlint` and `oxfmt --check` | Passed for the four changed TypeScript source and test files. |

The Ghostel command used the same isolated module arguments as the T028 command above.
The OMP selection added `packages/coding-agent/test/session-focus-controller.test.ts` to the T028 selection.
The package gate reported existing compiler warnings. The Zig gate reported the expected closed-event-pipe warning.
Neither gate reported unexpected test results.

T033, T034, T036, T037, and T040 are complete.
T015/T035 still require authorized Agent acknowledgement checks.
T039 remained deferred during these checks. No user-owned trust configuration changed.
No live native module reload, installed module replacement, remote transfer, model turn, commit, or push ran.
The smoke checks removed their private Agent directories. Normal ignored build outputs remain.

## Authorized live acceptance: 2026-09-27 UTC

The user approved normal OMP startup and exactly three turns with `openai-codex/gpt-6-luna`.
The scope included synthetic images only, one local Session, and two disposable Sessions on `v12mac`.
An invocation overlay disabled advisors. Existing trust settings remained unchanged.
Each Session transcript contains one user message and one completed assistant text reply.
No tool call or tool result occurred. No additional model turn is authorized.

The private OMP candidate was version `18.3.2`, with 221967504 bytes.
Its local and remote SHA-256 was `3f83afce89a3393e1eb1cddf1802d6961ca73d6c2bb4d98d5ac2f541eec869e2`.
Two fresh graphical Emacs processes loaded the candidate Ghostel `0.54.0` module.
Their PIDs were `78406` and `99478`. The user's main Emacs retained its loaded module.
The remote host used stock zmx `0.8.1`.

### Session identities and exact-byte evidence

| Label | Package Session ID | zmx target | Remote directory |
|---|---|---|---|
| A | `claude-remote-v12mac-J5Rfrq` | `cci-omp-a-J5Rfrq` | `/tmp/cci014-acceptance.OVHlJB8X/A` |
| B | `claude-remote-v12mac-ow0Gln` | `cci-omp-b-ow0Gln` | `/tmp/cci014-acceptance.OVHlJB8X/B` |

Gestures 1–5 used Emacs PID `78406`. Gestures 6–10 used Emacs PID `99478`.
The second Emacs attached to the same targets without restarting either Agent.
It observed mode 5522 and the existing image chips before it sent input.
Each successful gesture preserved the other Session's stored-image count.
The following received digests describe ordinary OMP original-image artifacts after verified receipt.

| Gesture | Session | Attachment | Bytes | Visible after, ms | Expected SHA-256 | Received SHA-256 |
|---:|---|---:|---:|---:|---|---|
| 1 | A | 1 | 4318 | 285 | `a9a0e6ddc13c8b9091f8263d9effe7b274d2f3651f262af09083f7b8ff547e99` | `a9a0e6ddc13c8b9091f8263d9effe7b274d2f3651f262af09083f7b8ff547e99` |
| 2 | B | 1 | 4320 | 157 | `40b6c342830a57369068933e873961f280e1db096dbe9e3c11bb7215259db083` | `40b6c342830a57369068933e873961f280e1db096dbe9e3c11bb7215259db083` |
| 3 | A | 2 | 4518 | 163 | `26422c86f4a414714fef1a0d44b469224d8714b2e0398b75441d9d1c2467f0c8` | `26422c86f4a414714fef1a0d44b469224d8714b2e0398b75441d9d1c2467f0c8` |
| 4 | B | 2 | 4519 | 164 | `04550762052efca2d801a4850099652cae0358cf46b33904fab3d9b57e9430d1` | `04550762052efca2d801a4850099652cae0358cf46b33904fab3d9b57e9430d1` |
| 5 | A | 3 | 5261 | 165 | `2831d605484afaefe6d7d53dbeb08a4c7b858d26f247f142c93df0c0f68ed41c` | `2831d605484afaefe6d7d53dbeb08a4c7b858d26f247f142c93df0c0f68ed41c` |
| 6 | B | 3 | 5263 | 179 | `f8d93099a8e62a53f8665d7064941dda0aaa11724586cfbaa88ed0eb0661f735` | `f8d93099a8e62a53f8665d7064941dda0aaa11724586cfbaa88ed0eb0661f735` |
| 7 | A | 4 | 6084 | 191 | `565c1368fd143adb3cc64e5be5cdb08d5bab452b685e20fdd05285b2f0946261` | `565c1368fd143adb3cc64e5be5cdb08d5bab452b685e20fdd05285b2f0946261` |
| 8 | B | 4 | 6086 | 187 | `f36779909a9b36c52d6235da5d9f23002959963cc5f30cbac29bba6663a44108` | `f36779909a9b36c52d6235da5d9f23002959963cc5f30cbac29bba6663a44108` |
| 9 | A | 5 | 5244372 | 1448 | `d5c31a8e2de418c770f7010161f83d4decfa874ab997fdaf89d302655fc3af23` | `d5c31a8e2de418c770f7010161f83d4decfa874ab997fdaf89d302655fc3af23` |
| 10 | B | 5 | 6806 | 165 | `5d91c4d3fce72275acef394100ab2617803420bbada8cfe9b94a9651542e7bdb` | `5d91c4d3fce72275acef394100ab2617803420bbada8cfe9b94a9651542e7bdb` |

Gesture 9's time describes manual recovery after detaching the first client, not its failed first attempt.
This sequence therefore does not prove ten first-attempt successes with concurrent attachments.
Session B did receive all five images on their first gestures.

### Agent vision acknowledgement

The approved prompt was:

```text
Inspect the attached images without using tools. Report the image count. For each image in order, describe the left and right colors, count the white bars, and report dimensions if available. Do not infer unavailable dimensions.
```

Before submission, the observer checked this complete wording in every editor after removing image-chip markers and display wrapping.
OMP inserted its normal image markers and dimension annotations in the submitted messages.
The Session transcripts and actual terminal surfaces showed these completed replies:

| Target | Image count | Reported colors | Reported white bars, in order | Reported dimensions |
|---|---:|---|---|---|
| Local OMP | 1 | Red / blue | 1 | 640 × 480 |
| Remote A | 5 | Red / blue | 1, 2, 3, 4, 5 | First four: 640 × 480. Fifth: 1280 × 1024. |
| Remote B | 5 | Green / yellow-orange | 1, 2, 3, 4, 5 | All: 640 × 480. |

The local direct-clipboard route reencoded the 4318-byte PNG into a 7104-byte PNG.
Pillow decoded both images to identical RGBA pixels and identical `640×480` dimensions.
The local stored PNG's SHA-256 was `a74592267a71da458a5082246598eee7b0f3b57facd4a02e723b3de6ed9997a2`.
The remote verified route preserved the original PNG bytes instead.
The prior local Claude/Codex image and text checks remain valid. No Claude/Codex model turn ran in this pass.

### Concurrent-attachment failure

With both Emacs attachments connected to A, the 5244372-byte image failed with `Image paste contained invalid base64 data`.
The Agent retained four image chips and attached no partial fifth image.
Detaching only the first attachment let the unchanged image attach in 1448 ms.
The remote Agent and the second attachment remained unchanged.
The first hypothesis blamed a same-ID refusal from the other attachment.
A private Ghostel guard did not fix the failure. The original Ghostel source and tests were restored.

The owned zmx daemon log confirmed the transport failure:

```text
[1790472337] [warning] (default): pty input dropped 1022 bytes (buffer full, shell not reading)
[1790472514] [warning] (default): pty input dropped 1022 bytes (buffer full, shell not reading)
```

The log belongs to `cci-omp-a-J5Rfrq` on `v12mac`.
[Stock zmx 0.8.1](https://github.com/neurosnap/zmx/blob/v0.8.1/src/loop.zig) discards new input above its 256 KiB PTY queue limit.
The decoder correctly rejected the resulting incomplete image stream.
Detaching one client changed timing. It did not correct the queue behavior.

The user approved a zmx backpressure correction, its regression checks, and private local and remote candidates.
This approval supersedes the earlier prohibition on zmx source changes for this correction only.
Installation needs separate approval. No further model turns are authorized.

An earlier harness attempt restored the clipboard before the asynchronous remote read completed.
The remote Session correctly refused that attempt and attached nothing.
The corrected observer held the clipboard until the attachment appeared or the ten-second wait ended.
Every clipboard-helper run restored all original representations and verified equality.

### Historical guidance observation

The observer displayed the real non-leading-client guidance and measured 60.004 seconds without receiving a paste gesture.
The user then clarified that no person attempted the trial and that they would not interact with another Emacs window.
This was not a participant usability test and establishes no guidance failure or usability success.
The user later removed the trial requirement. No Session guidance changed.
T039 remained deferred at the user's request during this check. No trust setting changed.

## Private zmx backpressure correction: 2026-09-27 UTC

The user approved this correction after the stock-daemon log confirmed dropped input.
The zmx checkout is `/Users/fuyu0425/agents/zmx`, based on v0.8.1 commit `8bab1f0173b07e79835ea372d749af3dbf0d0842`.
No installed executable changed.

### Correction and regression

The daemon retains complete input messages until it can admit them to the PTY queue.
The client stops reading stdin when its socket queue reaches the admission watermark.
Partial writes remove only the written prefix. Sender EOF does not discard pending complete messages.
Other control clients and PTY output continue while input waits.
Allocation and PTY write errors no longer silently discard accepted input.
The existing IPC format, leadership rules, clipboard grants, and receiver validation remain unchanged.

The 256 KiB value is an admission watermark, not an absolute message-size limit.
One complete message can exceed it, including a Run or Write expansion.
A generated device-reply batch can also exceed it.
The existing IPC format still buffers each complete control message.

The permanent regression uses seed `0x5a4d5808` and a private socket namespace.
It holds a raw PTY reader, sends deterministic bytes, checks a control reply, and then releases the reader.
It compares every received byte with the expected sequence.
The unmodified baseline lost all 5242898 bytes in the first large Send case.
The smallest boundary check passed at 262144 total bytes and failed at 262145 total bytes, with zero bytes received.
The corrected executable passed all nine Send and attach cases, including empty input, one byte, boundary sizes, large input, and EOF.

Observed commands:

```sh
/Users/fuyu0425/.asdf/installs/zig/0.16.0/zig build test -Doptimize=ReleaseSafe --summary all
/Users/fuyu0425/.asdf/installs/zig/0.16.0/zig build -Doptimize=ReleaseSafe -Dversion=0.8.1-cci014-backpressure --summary failures
/opt/local/bin/python3 test/backpressure.py zig-out/bin/zmx
/Users/fuyu0425/.asdf/installs/zig/0.16.0/zig fmt --check src/loop.zig src/ipc.zig src/util.zig
```

The unit run passed 95 of 95 checks.
The first executable build exposed a missing `usize` result annotation in the new socket-write branch.
After that correction, the executable build, all nine CLI cases, and the format check passed.
The BATS entry uses the same Python regression. BATS itself was unavailable locally and did not run.
The unchanged package, Ghostel, and OMP gates were not repeated.

### Private candidate and live route

The Darwin ARM64 candidate reports `0.8.1-cci014-backpressure`.
Its size is 2651408 bytes.
Its local and remote SHA-256 values both equal:

```text
25fce840b70107aefa6df241e1b997ca52604a5c933e512c1aea29e017a3d1cb
```

The remote copy ran only from `/tmp/cci014-acceptance.OVHlJB8X/backpressure-bin/zmx` on `v12mac`.
Both attachment commands and control requests used the private `backpressure-sockets` namespace under that root.
Runtime file mappings confirmed the candidate executable.

Two fresh Emacs processes, PIDs `34822` and `34823`, loaded the original Ghostel 0.54.0 candidate from `ghostel/zig-out`.
Runtime file mappings confirmed that neither process used the discarded speculative module.
These checks did not load a module into the user's main Emacs.

| Target | Package Session ID | zmx name | Remote working directory |
|---|---|---|---|
| A | `claude-remote-v12mac-WCpXtQ` | `cci-omp-bp-a-WCpXtQ` | `/tmp/cci014-acceptance.OVHlJB8X/bp-A` |
| B | `claude-remote-v12mac-ytkn18` | `cci-omp-bp-b-ytkn18` | `/tmp/cci014-acceptance.OVHlJB8X/bp-B` |

The production constructor created each Session and attached the second Emacs to its existing target.
Read-only owner queries selected the serving attachment. No probe input claimed ownership.
Each Session retained two attached clients before and after the full sequence.
The actual terminal surfaces showed five unsent image chips in all four attachment buffers.

### Ten alternating first-gesture successes

Each row records one call to the actual package paste command.
The clipboard held only the corresponding synthetic PNG until the image chip appeared.
Both fifth images contain 1280 × 1024 RGBA pixels and exceed 5 MiB.
OMP stored the received image through its ordinary attachment path. Only the clipboard and terminal connection supplied image bytes.

| Gesture | Target | Attachment | Bytes | Elapsed ms | Expected and received SHA-256, equal |
|---:|---|---:|---:|---:|---|
| 1 | A | 1 | 2350 | 275 | `5c446575c245ae2b5744944eacba16be794d40ff186daff2a82b00e8dac53dcc` |
| 2 | B | 1 | 2352 | 205 | `10e0fb3f002fb402ada5a657762a07ec760df166f8f251b3222c191308742d17` |
| 3 | A | 2 | 2354 | 174 | `8af7a834091a1b9a7af4c40af556ab1ac7f228b92f17ae812110ae7163b3c837` |
| 4 | B | 2 | 2358 | 171 | `07c4841c995743b03d47d4545bf89943c4c0985a6aa964401dcd21cac237c1f0` |
| 5 | A | 3 | 2359 | 171 | `fe224d1e2135ce7ad4c6892f4d065827a69843b344b32b3ddd9261420aeaad76` |
| 6 | B | 3 | 2360 | 176 | `c6f70d16ba9956ffb10fba86182d256656a10299e72ddc7562a2cb748d736468` |
| 7 | A | 4 | 2360 | 177 | `41695552508d5d60fdb2b9c6cfe1563b08e169b6677d7516764d4e4dfc3aa2f0` |
| 8 | B | 4 | 2362 | 178 | `568bfc366ae46e020e51069c7d5a00782844b6a1111232ce4fdd6cf81436ee0e` |
| 9 | A | 5 | 5245667 | 1667 | `1a4c2b036351d891061b3280b1b8c846c295623860a49d671e5f85b1670e59ed` |
| 10 | B | 5 | 5245667 | 1727 | `fc38bcd617093daf3a3b6cb0246d0ac778b5794101bdc3c5fa9a5798124c03c9` |

All ten images arrived on the first gesture. Each remote stored PNG matched its expected byte count and SHA-256.
The clipboard helper restored every original representation and verified equality.
No additional model turn ran. The two earlier remote transcripts still contained exactly two user and two assistant messages, with no tool calls.
The new unsent-image checks created no submitted-message transcript.
The three earlier authorized vision turns remain the model-acknowledgement evidence.

This record closes T015 and T041 for private candidates.
T039 remained deferred during this check, with trust settings unchanged.
Installation still needs separate approval.

### Cleanup and remaining gates

The four owned remote test Sessions returned explicit kill acknowledgements.
The private zmx namespace then listed no Sessions.
Both fresh Emacs processes exited with code 0. The two speculative-module Emacs processes had already exited with code 0.
The cleanup removed the owned local and remote acceptance directories, temporary OMP build, and Python cache.
Those removals also removed the speculative native modules and private remote binaries.
The zmx source, permanent regression, changelog, and local `zig-out/bin/zmx` candidate remain in `/Users/fuyu0425/agents/zmx`.

These checks stopped no unrelated Session. They changed neither trust settings nor the shared Agent blob store.
The original daemon logs remain as ordinary runtime records.
No installation, commit, push, or additional model turn ran.
The project workflow registers no post-implementation command.
T039 remained deferred during this cleanup.

## Phase 8 implementation checks

### T042: verified image format agreement

The new one-pixel BMP case failed before the correction.
The editor accepted the BMP bytes with an `image/png` label and created an ordinary image artifact.
At this stage, the shared validator rejected unrecognized bytes when the declared MIME named a supported image format.
The existing InputController validation call remained unchanged. Full decoding still checked recognized formats.
T044 later restricted this unknown-format policy to verified receipt, as recorded under Phase 9.

The editor-boundary file passed 31 tests with 372 assertions after the correction.
The refusal cases cover empty, truncated, non-image, and decodable wrong-format data.
They assert an unchanged draft, no pending image, no pasted-image artifact, and successful recovery with the original PNG bytes.

A separate `bun --eval` API smoke used the actual shared validator and image normalizer.
It observed the mismatch explanation, accepted the correctly labeled BMP, and accepted its normalized `1x1` PNG.
The input bytes remained unchanged. No model request or real clipboard read occurred.

### T043: partial reply expiry through both PTY writers

The retained `ghostel-test-clipboard-partial-reply-expiry-and-recovery` check passed in 22.65 seconds.
It uses the existing public paste command and real Emacs and native PTY writers.
Its independent Python receiver stops reading after the first image DATA packet and resumes after the host deadline.
The receiver rejects the incomplete byte count and digest without reporting a completed image.
The check also requires a useful explanation, retired authorization, and a live process.
A fresh paste then delivers a complete PNG with the expected byte count and SHA-256.
The existing completed-write disconnect checks remain unchanged. No Ghostel production code changed.

These checks use disposable local processes and a synthetic clipboard provider.
They are not new remote acceptance checks or model acknowledgements.
T039 remained deferred during Phase 8 without inspecting trust settings.
No installation, user Session restart, real clipboard change, remote transfer, model turn, commit, or push ran.

### Integrated Phase 8 gates

| Gate | Observed result |
|---|---|
| `./scripts/compile-and-test.sh` | Byte compilation passed. 961 tests passed, 14 skipped, zero unexpected. |
| Ghostel isolated `make -k -j4 test-all` | Native build and Zig checks passed. 1200 ERT checks passed, 8 skipped, across 66 invocations. |
| OMP focused selection | 441 tests passed across 18 files, with 2098 assertions. |
| Coding-agent and TUI type checks | Both passed. |
| Scoped `oxlint` and `oxfmt --check` | Passed for `image-loading.ts` and `input-controller-enhanced-paste.test.ts`. |

Ghostel used the isolated `zig-out` module arguments recorded under T028.
The fresh `TEST_STAMPS_DIR=.build/tests-phase8-20260927-0236` forced all 66 test invocations without replacing the installed module.
The OMP selection added four files to the T028 command:

- `packages/coding-agent/test/session-focus-controller.test.ts`
- `packages/coding-agent/test/image-input.test.ts`
- `packages/coding-agent/test/image-input-normalization.test.ts`
- `packages/coding-agent/test/provider-image-integrity.test.ts`

The package compiler reported existing warnings. The Zig check reported the expected closed-event-pipe warning.
Both commands exited successfully. All reported test results were expected.
The build left ordinary ignored outputs. The test fixtures removed their private Agent directories, buffers, and processes.

At the end of Phase 8, the plan still had older no-zmx-change statements.
The explicit approved exception governed the backpressure correction.
Phase 9 reconciled those statements without changing zmx source.

## T039 approved trust cleanup

The user approved T039 after removing the participant-trial requirement.
The cleanup confirmed and removed this exact entry from `~/.claude.json`:

```text
projects["/private/var/folders/vg/4l8mg2ss5m36qk342npvgw240000gq/T/cci014-local-parity-_x0pe4jh/claude"]
```

The entry existed and had `hasTrustDialogAccepted` set to `true` before removal.
The edited file parsed as valid JSON, and the target entry was absent.
A comparison against the immediate pre-edit snapshot confirmed that every other configuration value remained unchanged.
A byte comparison confirmed that only the target entry and its required JSON separator changed.
The cleanup used an in-memory snapshot, not an older configuration backup.

T039 is complete. No installation, model turn, remote action, or user Session restart occurred.

## Phase 9 implementation checks

### T044: verified-only format restriction

The shared validator now requires a recognized container only when the caller enables `requireKnownFormat`.
The verified InputController path enables that argument before ordinary preparation or editor mutation.
Ordinary attachment and provider-context callers retain their decode-based policy when the header parser cannot identify the format.
Both modes still validate base64, reject recognized-format disagreement, and fully decode accepted image data.
The change adds no second parser, byte copy, or user configuration.

The new ordinary attachment regression failed before the correction and passed afterward.
It generates three fixed BMP color variants and requires byte preservation through `loadImageAttachmentInput`.
It also rejects empty, single-byte, truncated, and non-image inputs.
The receiver regression still refuses the same BMP container with a PNG label.
It preserves the draft and pending attachments, creates no image artifact on refusal, and accepts the next valid PNG unchanged.

The initial receiver-only run passed 31 tests with 372 assertions.
The post-correction ordinary attachment and receiver run passed 36 tests with 399 assertions:

```sh
bun test packages/coding-agent/test/image-input.test.ts \
  packages/coding-agent/test/input-controller-enhanced-paste.test.ts
```

A separate in-memory `bun --eval` smoke exercised the actual attachment API and shared validator without test mocks.
The 58-byte BMP input decoded into a 70-byte PNG with the standard PNG signature.
The earlier mismatch result applied to the BMP input, not that PNG output.
After the correction, the ordinary attachment API preserved both inputs unchanged.
Verified validation rejected the BMP labeled as PNG and accepted the actual PNG.
Ordinary validation also rejected the actual PNG when labeled as JPEG.
No provider call, transfer file, or real clipboard access occurred.

### T045: zmx scope reconciliation

The plan now describes the approved backpressure exception in Structure Decision, Multiplexer, and Post-Design Constitution Check.
Its zmx governance row also records the exception.
T005's existing-interface checks and T041's private-candidate evidence remain the basis for the scope.
IPC, leadership, host approval, authentication, and attachment lifecycle limits remain unchanged.
Installation still requires separate approval. No zmx source changed in this phase.

### Integrated Phase 9 gates

| Gate | Observed result |
|---|---|
| `./scripts/compile-and-test.sh` | Byte compilation passed. 961 tests passed, 14 skipped, zero unexpected. |
| OMP Phase 8 selection, including the new ordinary attachment regression | 442 tests passed across 18 files, with 2111 assertions. |
| `bun run --cwd packages/coding-agent check:types` | Passed. |
| `bun run --cwd packages/tui check:types` | Passed. |
| Scoped `oxlint` and `oxfmt --check` | Passed for all four changed TypeScript source and test files. |
| Checklist and task status | Requirements checklist: 16 checked, zero unchecked. Tasks: 44 checked, zero unchecked. |

The package compiler reported existing warnings. The gate exited successfully and removed its compiled outputs.
The OMP test fixtures removed their temporary directories. The API smoke created no files.
Existing project ignore rules cover the relevant outputs. No ignore-file change was necessary.
Ghostel and zmx source did not change, so this phase did not repeat their suites or live acceptance.
Their earlier evidence remains in the Phase 8 and private-candidate records.
No installation, user Session restart, real clipboard change, remote transfer, model turn, trust change, commit, or push occurred.
