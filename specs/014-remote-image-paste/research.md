# Research: Remote Image Paste

Phase 0 findings for `specs/014-remote-image-paste`. Every decision below rests on a
source read during research; citations name the file and line where a claim was
verified.

## R1. The transport is OSC 5522 with private mode 5522

**Decision**: Use the kitty clipboard protocol (OSC 5522) with its paste-event private
mode (`CSI ? 5522 h`) as the only transport. The terminal answers the application's
clipboard read with local data, so the Agent's host needs no clipboard.

The exchange, confirmed against the client implementation in `oh-my-pi`:

```text
1. Application enables the mode:      ESC [ ? 5 5 2 2 h
2. User pastes the gesture locally.
3. Terminal, on paste, sends an event OSC 5522 packet naming available MIME types
   and a one-time password grant. No data is sent yet.
4. Application asks for one MIME:     ESC ] 5522 ; type=read:pw=...:name=<"Paste event">:mime=<mime> BEL
5. Terminal answers with data packets, base64, chunked.
6. Application attaches the data as an image.
```

Evidence: `packages/coding-agent/src/utils/enhanced-paste.ts` in the `oh-my-pi`
checkout (the mode enable writes `"\x1b[?5522h"`, the read request carries `pw=` and
`name=<base64 "Paste event">`, and DATA packets are decoded per MIME), and
`docs/keybindings.md:67` in the same checkout, which documents that OSC 5522 image
pastes attach as `[Image #N]` while `text/plain` paste events keep normal paste
behavior.

**Rationale**: The user's request names this standard. One existing Agent implements
the client side, so no Agent change is needed for that Agent. The protocol carries
MIME data, so an image works without a file and without a remote path.

**Alternatives considered**:

- A remote temporary file plus a pasted path. Rejected by spec FR-005, and it writes
  the user's clipboard image to another host's disk.
- An Emacs-to-CLI APC packet carrying base64 image data. Rejected because no Agent
  parses such a packet, and it would create a private protocol beside an existing
  standard.
- OSC 52. Rejected because it carries text only and its read path is denied by
  default in the pinned terminal.

## R2. Agent coverage: one Agent implements the client side, so coverage is explicit

**Decision**: The terminal-mediated path is offered to Agents that implement the
client side of OSC 5522. Today that is Oh My Pi (`omp`) only. Claude Code, Codex, and
Pi keep today's behavior with no change.

Evidence: a repository-wide search for `5522`, `Paste event`, and `enhanced paste`
found an implementation only in `/Users/fuyu0425/agents/oh-my-pi`
(`packages/coding-agent/src/utils/enhanced-paste.ts`). The same search over
`/Users/fuyu0425/agents/claude-code/src`, `/Users/fuyu0425/agents/codex/codex-rs`, and
`/Users/fuyu0425/agents/pi` found no client-side implementation. Codex detects a pasted
image *path* in text (`codex-rs/tui/src/bottom_pane/chat_composer.rs:1210`) and reads
no clipboard image at all.

**Rationale**: The spec's FR-001 is already conditional ("when both the terminal and the
Agent support image transfer"). Naming the supported set in one place keeps the route
choice honest and testable, and it prevents a false claim that every Agent gains the
behavior.

**Alternatives considered**:

- Teach other Agents the protocol. Rejected: outside this package, and unrequested.
- Claim broad Agent support. Rejected: unverifiable.

## R3. The terminal backend must be bumped, and native support does not exist at the pin

**Decision**: Ghostel must bump its pinned ghostty dependency to a commit containing
`ghostty_terminal_paste` and mode 5522. The pin candidate is ghostty commit
`e4240606752e5e4eb480b69104d75db0054f71c8` (2026-08-23), the merge of ghostty PR
`#13978`.

Evidence: Ghostel pins ghostty at `ab0b9da9e88fcb4b0533a1854e84628f663930af`
("1.3.2-dev", 2026-07-22) in `build.zig.zon`. At that pin, the OSC 5522 parser exists
(`src/terminal/osc/parsers/kitty_clipboard_protocol.zig`) but the command is discarded:
`src/terminal/stream.zig` routes `.kitty_clipboard_protocol` to a branch that logs
`unimplemented OSC callback` and does nothing. No `paste_event` and no
`ghostty_terminal_paste` symbol exists anywhere in the pinned `src` tree. PR `#13978`
("libghostty: centralize pasting to `ghostty_terminal_paste`, enable mode 5522") was
opened and merged after the pin, and it notes that it changes libghostty-vt only, not
the Ghostty GUI.

**Rationale**: Reading a protocol the terminal drops cannot work. The bump is the
smallest route to native support, and it is the only route that keeps the protocol
implementation in the terminal library instead of re-implementing it in Ghostel.

**Alternatives considered**:

- Implement OSC 5522 in Ghostel's own Zig handler beside the parser. Rejected: it
  duplicates upstream work, including grant minting and chunking, and would diverge
  from the library Ghostel tracks.
- Wait for a release tag. Rejected as a blocker: the artwork is merged on `main`, and
  Ghostel already pins a development version.

## R4. The host contract: three host obligations, all inside Ghostel

**Decision**: Ghostel owns the host side of the exchange. Three obligations follow from
the merged upstream API:

1. Supply a cryptographically secure random source for grant minting
   (`GHOSTTY_SYS_OPT_RANDOM_SECURE`, used by `io.randomSecure`), or rely on the
   platform default when the embedder does not override it.
2. Install the terminal clipboard-read callback
   (`GHOSTTY_TERMINAL_OPT_CLIPBOARD_READ`) and answer it with base64 MIME contents.
   The callback carries a `granted` flag, true when the request presented a valid
   event password.
3. Paste through `ghostty_terminal_paste` with the available MIME types, so the
   terminal can decide between a paste event (mode 5522), bracketed paste, and a plain
   paste, and so an unsafe payload is rejected instead of written.

Evidence: ghostty `main` `include/ghostty/vt/paste.h` (`ghostty_terminal_paste`,
`GhosttyPaste`, `GhosttyMimeReader`, the `rejected` result) and
`include/ghostty/vt/terminal.h` (`GHOSTTY_TERMINAL_OPT_CLIPBOARD_READ`,
`GhosttyTerminalClipboardReadFn`, reply function) plus `include/ghostty/vt/sys.h`
(`GHOSTTY_SYS_OPT_RANDOM_SECURE`); PR `#13978` body for the mode precedence, the grant
mechanism, and the note that this is a libghostty-vt-only change.

**Rationale**: These are exactly the seams the embedding host must fill, and each maps
to one existing Ghostel seam: sys options at module init, terminal options at terminal
creation, paste at the paste command.

**Alternatives considered**:

- Let Emacs answer the read without a native callback, by parsing PTY output in
  Elisp. Rejected: duplicate parsing, wrong layer, and it would race the native
  parser for the same bytes.

## R5. The multiplexer needs no change when the local client leads

**Status: blocked after implementation-time verification.**
Live forwarding works when the local client leads, but stock 0.7.1 lacks the required leadership query and mode replay.
The original no-zmx-change conclusion did not establish FR-009 or EC-08.
The evidence below described live forwarding only. See the implementation evidence for the corrected version-specific findings.

Evidence, read in the zmx 0.7.1 source:

- Application output is forwarded verbatim to every client. The PTY read loop feeds
  the internal terminal emulator *and* broadcasts the same bytes
  (`zmx-main-0.7.1.zig:2934-2952` and `:2988-3012`); only the OSC 133 prompt marker is
  rewritten. An OSC 5522 read request from a remote Agent therefore reaches the local
  terminal unchanged.
- The leader client's input reaches the PTY unfiltered:
  `if (self.leader_client_fd == client.socket_fd) { self.queuePtyInput(payload); return; }`
  (`zmx-main-0.7.1.zig:1040-1044`). The terminal's OSC 5522 answer is written to the
  PTY as input, so it reaches the Agent.
- A non-leader client's input is dropped unless `util.isUserInput` classifies it as
  user input (`zmx-main-0.7.1.zig:1046-1049`; the classifier in
  `zmx-util-0.7.1.zig:567-611` returns false for OSC sequences). A terminal answer from
  a non-leading client is therefore lost. This is the one failure the spec's FR-009
  covers with an explanation, not with a fix.
- Leadership follows the first attached client, and moves when any client sends user
  input (`zmx-main-0.7.1.zig:1112-1115`).
- `zmx send` queues input to the PTY without changing leadership
  (`zmx-main-0.7.1.zig:1050-1052`), which is a possible remedy path and is not used by
  this feature.

**Revised conclusion**: Forwarding both directions does not establish complete feature support.
The package cannot infer current leadership or restore unknown saved modes from that evidence.
A scope decision is required before implementation continues.

**Alternatives considered**:

- Extend the zmx IPC so any client's answer reaches the PTY. Rejected: it changes
  another project's leadership contract to serve one feature.
- Send the answer with `zmx send`. Rejected: the terminal writes to its own PTY, and
  routing around it would split ownership of the exchange.

## R6. Paste routing: remote Sessions use the terminal, local Sessions keep today's path

**Decision**: Keep today's local route. In
`claude-code-ide-session-paste-clipboard`, the image branch currently sends `C-v` when
the clipboard advertises an image and the CLI type is one of `claude`, `codex`, or
`omp` (`claude-code-ide-session.el:354-361`). Add the terminal-mediated route only for
a Session whose Agent cannot read the local clipboard, which means a remote Session
whose CLI implements the client side of OSC 5522.

**Rationale**: The local `C-v` route works today and needs no terminal support. It is
also the faster path, because the data never crosses the terminal boundary. Spec
FR-016 and the clarification session require this split.

**Alternatives considered**:

- Route every paste through `ghostty_terminal_paste`. Rejected: it changes local
  behavior that works, and it makes a text paste depend on a new terminal path.

## R7. Capability detection and honest refusals

**Decision**: The package asks Ghostel for a paste-event capability predicate before it
uses the new route. When the predicate is absent (older Ghostel), or the terminal
reports no support, or the local terminal client is not the input leader, the Session
explains the condition and the single action that restores delivery, and sends
nothing. This follows the package's existing optional-dependency rule: load through
`(require 'ghostel nil t)` and produce an actionable `user-error` at the point of use.

Evidence for the existing shape: `claude-code-ide-session-paste-clipboard` falls back
to `ghostel-yank` for text (`claude-code-ide-session.el:355-361`), and the package
already treats Ghostel as optional (`.specify/memory/constitution.md`, Principle III).

**Rationale**: One predicate keeps the package free of version arithmetic, and one
explanation keeps every failure visible, per spec FR-004 and FR-009.

**Alternatives considered**:

- Compare module version numbers in the package. Rejected: two version ladders, and
  the package would need to know Ghostel's internals.
- Try the route and catch the error. Rejected: a failed paste can still have written
  bytes to the Agent.

## R8. Verification design

**Decision**: Verify at three seams, with one live end-to-end walkthrough.

1. **Ghostel, Zig unit tests** (`make test-zig`): the paste-event packet shape (MIME
   list, grant password, terminators), the read reply (base64 chunking, MIME
   selection, the `granted` flag), the unsafe-payload rejection, and the fallback to
   bracketed paste when the mode is off.
2. **Ghostel, native and Elisp tests** (`make test-native`, `make test`): a fake
   application writes an OSC 5522 read request, and Ghostel answers it from a stub
   clipboard; the existing OSC 52 tests stay unchanged.
3. **Package ERT** (`claude-code-ide-tests.el`, then `./scripts/compile-and-test.sh`):
   the route decision (remote plus capable terminal plus capable CLI uses the terminal
   paste; every other combination keeps `C-v` or `ghostel-yank`), and the explanation
   for each refusal. Existing paste tests must pass unchanged.
4. **Live walkthrough** (`quickstart.md`): on the approved remote host used by feature
   013, start an `omp` Session through zmx over SSH, paste a screenshot, and confirm
   the Agent reports the image. Repeat on a local Session to confirm no change.

**Rationale**: The tests sit at the seams the design changes: protocol bytes, host
callback, route decision. The live walkthrough is the only check that proves the whole
chain, because three mocks in series prove nothing about the real one.

**Alternatives considered**:

- Mock the whole exchange in the package's ERT suite. Rejected: it would assert the
  package's own mock, not the protocol.
- Skip the Zig unit tests and rely on the live check. Rejected: failure modes such as
  chunk boundaries are hard to trigger by hand.

## Open items carried into implementation

- The candidate exports native paste and clipboard interfaces through the Zig module that Ghostel actually uses.
  Its dependency update failed to compile. T003 remains open.
- The secure random source uses the terminal's `std.Io.Threaded` path.
  No separate C sys-option override is required by the observed source path.
- The callback requires a synchronous reply. The planned deferred reply cannot retain its temporary context.
- The host must enforce the requested per-gesture clipboard policy in addition to the upstream grant check.
- Stock zmx 0.8.1 supports the observed replay and per-client metadata checks.
  Existing package attachments still need a tracked identity before the package can compare them with the leader.
- The macOS byte-read prerequisite passed through `gui-get-selection` with the `image/png` target.
  The native reader-thread handoff remains unresolved. See the latest checks below.

## Implementation evidence: 2026-09-26

### T001: Current environment and client

| Check | Observed result |
|---|---|
| `zig version` on the shell PATH | `0.15.2`. Ghostel's `build.zig:8-11` requires exactly `0.16.0`. |
| `emacs --version` and live `emacs-version` | `31.1.50` |
| `zmx --version` | `0.7.1` |
| Ghostel dependency | `build.zig.zon:9` still pins `ab0b9da9e88fcb4b0533a1854e84628f663930af`. |
| Live `ghostel--module-version` | `0.53.0` |
| Live paste-event interface | Neither `ghostel-paste-events-supported-p` nor `ghostel-paste-clipboard` exists. |
| Ghostel integration surface | `build.zig:41,95` imports the Zig `ghostty-vt` module directly, not the C terminal wrapper. |
| Source checkout state | Ghostel was clean. This package contained only the new, untracked feature task document. |

The existing OMP client enables mode 5522 and consumes an `OK`, `DATA`, `DONE` listing before requesting image bytes.
It requires another `DONE` after the image data before it invokes the image handler.
Its handler writes no completion acknowledgement to the terminal.
Sources: `enhanced-paste.ts:91-98,107-229` and `input-controller.ts:908-938` in `/Users/fuyu0425/agents/oh-my-pi/packages/coding-agent/src/`.

A disposable `bun --eval` probe imported the actual controller and supplied a one-pixel PNG through this normal exchange.
It observed no attachment before `DONE`, then exactly one image with unchanged base64 bytes.
It observed only the mode-enable output and MIME read request, with no completion acknowledgement.
No remote host, live Agent, clipboard, or repository file participated in this probe.

```json
{"modeEnabled":true,"requestWritten":true,"exactBytes":true,"attachmentCount":1,"clientCompletionAcknowledgement":false}
```

This proves the local client parser path, not the complete remote transfer.
T005 must resolve how the terminal reports delivery failures without an Agent acknowledgement.

### T003: Candidate build failed

The installed `/Users/fuyu0425/.asdf/installs/zig/0.16.0/zig` reports `0.16.0`.
The fetch succeeded:

```sh
/Users/fuyu0425/.asdf/installs/zig/0.16.0/zig fetch https://github.com/ghostty-org/ghostty/archive/e4240606752e5e4eb480b69104d75db0054f71c8.tar.gz
```

It returned `ghostty-1.3.2-dev-5UdBC6-kTwWZZ4DvFuVzRujGraQi2TTCc5CQyV-fzXB-`.
With that URL and hash, this command failed in the Ghostel checkout:

```sh
/Users/fuyu0425/.asdf/installs/zig/0.16.0/zig build -Doptimize=ReleaseFast -Dcpu=baseline
```

Observed result: 44 of 47 build steps succeeded. The native compilation reported four errors:

| Source | Error |
|---|---|
| `src/GhostelTerm.zig:418` | `Terminal.Options` no longer has `max_scrollback`. |
| `src/NativeProcess.zig:72` | The stream no longer has `initAlloc`. |
| `src/comint_filter.zig:267` | The stream no longer has `initAlloc`. |
| `src/kitty_graphics.zig:46` | The placement switch does not handle the new `relative` variant. |

The original dependency URL and hash were restored after this failed prerequisite.
No native module was installed into the live Emacs.
T003 remains unchecked. The implementation workflow stopped before T004 and the story phases.

The candidate requires these design corrections:

- Use the direct Zig `TerminalStream.Handler.paste`, `Paste`, and `clipboard.Read` interfaces.
- Reply synchronously with raw MIME bytes. Do not retain the callback context for a deferred Elisp effect.
- Let libghostty encode the protocol packets.
- Enforce the feature's clipboard policy before a host read.
- Treat successful PTY writes as transport progress, not Agent attachment acknowledgement.

Primary sources at the candidate commit:
[Zig exports](https://github.com/ghostty-org/ghostty/blob/e4240606752e5e4eb480b69104d75db0054f71c8/src/lib_vt.zig#L39-L101),
[paste handler](https://github.com/ghostty-org/ghostty/blob/e4240606752e5e4eb480b69104d75db0054f71c8/src/terminal/stream_terminal.zig#L294-L345),
and [synchronous clipboard callback](https://github.com/ghostty-org/ghostty/blob/e4240606752e5e4eb480b69104d75db0054f71c8/src/terminal/clipboard.zig#L55-L100).

### T005: Scope decision required

Read-only prerequisite research ran alongside T003. It found the following constraints:

| Condition | Evidence | Consequence |
|---|---|---|
| Stock zmx 0.7.1 has no leader identity query | Its IPC tags and Info record expose client count, not leader identity. Installed `zmx --help` also lists no such query. | The package cannot implement the required non-leader preflight for this version. |
| Stock zmx 0.7.1 cannot replay mode 5522 | Its pinned Ghostty mode table lacks this mode. Reattachment serializes known modes rather than replaying all old output. | Updating local Ghostel cannot restore the missing remote mode after restart. |
| Stock zmx 0.8.0 can replay mode 5522 | Its newer terminal stores and serializes the mode. | This removes the source-level replay blocker for that version, not all feature blockers. |
| Stock zmx 0.8.0 exposes leader environment metadata | `print-env` reads the leader's tracked environment. | A unique tracked attachment value could support a point-in-time comparison. This is an unimplemented design option, not an atomic ownership guarantee. |
| OMP has no attachment acknowledgement in this exchange | Source inspection and the T001 controller probe found only mode enable and MIME-read output. | The current design has no verified end-to-end completion or timeout observation. |

Version-specific primary sources:

- [0.7.1 IPC and Info](https://github.com/neurosnap/zmx/blob/v0.7.1/src/ipc.zig#L6-L75).
- [0.7.1 attachment replay](https://github.com/neurosnap/zmx/blob/v0.7.1/src/main.zig#L1075-L1108).
- [0.7.1 pinned mode table](https://github.com/ghostty-org/ghostty/blob/30e1f3bb8c3d2949e9ae4aefc1c2b76142569cfb/src/terminal/modes.zig#L251-L301).
- [0.8.0 leader environment query](https://github.com/neurosnap/zmx/blob/v0.8.0/src/loop.zig#L1293-L1305).
- [0.8.0 state serializer](https://github.com/neurosnap/zmx/blob/v0.8.0/src/util.zig#L769-L896).
- [0.8.0 pinned mode definition](https://github.com/ghostty-org/ghostty/blob/8af6897c0afc63037a8a3efee4162a380e3a4572/src/terminal/modes.zig#L332-L342).

No remote connection or runtime replay test ran. The 0.8.0 findings establish source behavior, not installed remote capability.
OMP and zmx remain unchanged. T005 remains unchecked because these blockers have no approved design resolution.

### Stock upgrade check: 0.8.1

The user permits stock zmx upgrades and prohibits zmx source changes.
The [latest official release](https://github.com/neurosnap/zmx/releases/tag/v0.8.1) was 0.8.1 when checked.
The [0.8.0-to-0.8.1 comparison](https://github.com/neurosnap/zmx/compare/v0.8.0...v0.8.1) retains the leader-environment interface and mode support.

The official macOS ARM archive was downloaded to a temporary directory.
Its SHA-256 matched the digest from the release API:

```text
1d86b1c9fba47fa707a6f0e976b20510b07c1c26d0ed010b9414b2a2c5e6beef
```

The binary reported version `0.8.1`. It was not installed globally.
A disposable local Session used a private `ZMX_DIR` and two PTY clients.
Its synthetic child enabled mode 5522 and echoed ordinary test input.
Each client advertised a distinct `CCI014_CLIENT` marker through stock `ZMX_TRACK_ENV`.

Observed results:

```text
PASS: stock zmx 0.8.1 replays mode 5522 to a later attachment.
PASS: print-env returns client-a, then client-b after deliberate fixture input.
PASS: repeated read-only queries preserve the current fixture leader.
Fixture cleanup exit: 0
```

The second attachment received the enabled mode through terminal replay.
`zmx print-env cci014-stock-probe CCI014_CLIENT` returned the leader marker without changing ownership.
Ordinary input from the second fixture client changed leadership under stock zmx rules.
The probe then observed its marker through the same read-only query.

These observations remove the 0.7.1-specific replay and identity-query blockers without modifying zmx source.
They do not prove ownership stability between a query and a later transfer.
They also do not prove remote image delivery, timeout handling, or Agent attachment.
No clipboard, remote host, or existing user Session participated.
Only the disposable Session was stopped.

Stock 0.8.1 is now the candidate feature baseline.
T005 remains open until the package's ownership-transition and failure behavior satisfy the unchanged requirements.
Only failures exposed by implemented, verified interfaces may be reported as observed failures.
The current Ghostel response callback does not yet provide reliable write-failure reporting.

The spec requires visible Agent acknowledgement, not a new wire acknowledgement.
The existing OMP parser's lack of a wire acknowledgement alone does not establish a need to modify OMP.

### Checks after the user's stock zmx upgrade

These checks inspected current Sessions without attaching, detaching, sending Agent input, or restarting their daemons.
Remote commands used the package's SSH options, including batch mode and strict host-key checking.
Only configured hosts with active package Sessions were queried.

| Host | Installed `zmx version` | Existing Sessions queried | Successful `print-env` replies |
|---|---|---:|---:|
| Local machine | 0.8.1 | 1 | 1 |
| `v12mac` | 0.8.1 | 3 | 3 |
| `ramhorn` | 0.8.0 | 2 | 2 |

All six existing daemons answered the stock environment query.
Their returned keys were the stock defaults. None included the fixture's `CCI014_CLIENT` marker.
No environment values were included in the check report.
This establishes query support, not the exact binary version of each persistent daemon.
It also does not establish mode replay for each existing Session.
Upgrading an installed binary does not replace a running per-Session daemon.

#### Existing-daemon adoption check

A separate local fixture used a fresh private `ZMX_DIR` and private state directory.
Its first attachment used stock tracking defaults.
Its second attachment added `CCI014_CLIENT` while retaining the first attachment's tracked keys.
Both clients used the installed stock zmx 0.8.1 binary.
The second command used `attach NAME false` to adopt the existing fixture.

```json
{
  "default_marker_absent": true,
  "adopted_client_marker_visible": true,
  "default_tracking_preserved": true,
  "agent_environment_unchanged": true,
  "mode_replayed": true
}
```

The new marker became visible after ordinary input deliberately made the second fixture client the leader.
The fixture's existing child still had no marker in its environment.
The daemon accepted the new tracked key without restarting that child.
Only the disposable Session was stopped. Its private files were removed.

The implementation must set the marker and tracking list on the actual attaching process.
Setting them on a later query does not update an existing attachment.
For remote Sessions, this means the remote zmx client, not merely the local SSH process.
The current package creation and adoption commands do not provide this identity.
Sources: `claude-code-ide-zmx.el:131-136,784-859`, `claude-code-ide.el:1900-2018`,
and stock [zmx client/daemon environment handling](https://github.com/neurosnap/zmx/blob/v0.8.1/src/loop.zig).
The [attach command](https://github.com/neurosnap/zmx/blob/v0.8.1/src/main.zig) reads `ZMX_TRACK_ENV` per client.
Its override replaces the default list, so package integration must preserve the effective existing entries.

### T004: macOS clipboard byte access passed

A disposable native helper put a generated 2-by-2 RGBA PNG on the local clipboard.
The helper kept the original clipboard representations in memory.
It invoked `~/bin/emacsclient --eval` to read only the synthetic image.
It then restored every original representation and verified exact equality.
The helper was diagnostic only. It adds no runtime dependency or image-file transfer.

Observed fixture:

```text
PNG bytes: 75
SHA-256: 7f2538a6e81af23e034f8ca2efc2cb5f1d7d709f502fa30bdccfebe774e4ecab
Emacs TARGETS: TARGETS, image/png, image/tiff
gui-get-selection CLIPBOARD image/png:
  type=string, multibyte=false, bytes=75, exact=true
Clipboard restoration: exact
```

Native pasteboard type `public.png` maps to Emacs target `image/png`.
Requesting `public.png` or `PNG` directly from Emacs returned an empty string in this check.
Requesting `image/tiff` returned a different representation, not the original PNG bytes.
Use the advertised Emacs MIME target and reject empty payloads.
Do not select a converted representation when exact PNG bytes are available.

This proves the GUI byte-read prerequisite for the installed Emacs.
It does not prove that Ghostel can safely make that read from its native reader thread.

### T003 and T005: remaining host implementation requirements

The previous candidate build was not repeated. The dependency pin and live module remain unchanged.
Read-only source inspection mapped the recorded errors to the candidate APIs:

| Current host usage | Candidate requirement |
|---|---|
| `Terminal.Options.max_scrollback` | Preserve the byte budget through `max_scrollback_bytes`. |
| `Stream.initAlloc` | Use the options-based initializer with the existing handler and allocator. |
| Kitty placement switch | Resolve relative placement chains, including pin and virtual roots. Do not discard the new variant. |
| Raw `image.data` slice | Handle complete/pending image data and the current render frame. |

The constructor migration also affects `GhostelTerm.zig:61`, beyond the two constructors named in the compiler output.
The candidate build remains unverified until this migration runs.
Candidate source: `src/terminal/Terminal.zig:266-277`, `src/terminal/stream.zig:496-545`,
and the Kitty graphics sources under the verified candidate cache recorded in T003.

All six inspected package Sessions use Ghostel's native PTY path.
Its reader thread invokes stream actions while it holds the terminal lock.
The candidate clipboard callback must finish synchronously, but Emacs selection access belongs on the Emacs main thread.
The existing event pipe has no synchronous reply path.
Keeping the candidate callback context for a deferred read would retain invalid temporary state.
Waiting for Emacs while holding the terminal lock can also deadlock terminal operations.
Sources: `../ghostel/src/NativeProcess.zig:46-53,89,166-190,264-280`,
`../ghostel/src/emacs.zig:324-345`, and candidate `src/terminal/clipboard.zig:55-100`.

The feature must retain its read-on-request requirement.
A gesture-time image snapshot would change that requirement and is not an approved shortcut.
[INFERENCE] A possible integration boundary is to queue the parsed clipboard operation before the synchronous upstream read starts.
The main thread would then invoke the original stream's handler with owned request data.
That approach still needs proof for lifetime, ordering, terminal reset, and process destruction.
It must not create a second grant owner or parse the protocol again in Elisp.
Source boundary: candidate `src/terminal/stream_terminal.zig:345-365,770-789`.

Failure reporting also requires implementation:

- Some native direct-write errors propagate, but interrupted writes can return without complete delivery.
- The Emacs-process path clears non-quit send errors.
- Terminal-response callbacks do not return transport errors to the paste operation.
- Native event-channel closure reports Session termination, not the outcome of one image transfer.

Sources: `../ghostel/src/GhostelTerm.zig:120-138`, `../ghostel/src/NativeProcess.zig:92-152`,
`../ghostel/src/PosixPtyProcess.zig:261-310`, and `../ghostel/lisp/ghostel.el:3851-3911`.

A separate disposable probe imported the actual OMP `EnhancedPasteController`.
It completed a normal image MIME listing, observed the read request, and supplied no reply.
After the feature's ten-second budget, it observed:

```json
{"elapsedMs":10504,"readRequests":1,"attachments":0,"statusMessages":[]}
```

The probe read no clipboard and contacted no Agent or remote host.
It establishes that this client controller does not report a missing-reply timeout by itself.
It does not establish that an OMP source change is necessary.
The approved host implementation still needs to demonstrate the required failure outcome.

T004 is complete. T003 and T005 remain open.
No zmx or OMP source changed. No native module was installed. No existing Session was restarted.

### T003: native API migration passed

The dependency now pins `e4240606752e5e4eb480b69104d75db0054f71c8`.
Ghostel now uses the options-based stream constructors and preserves its scrollback byte budget through `max_scrollback_bytes`.
Kitty placements resolve relative chains through pin and virtual roots.
Image conversion uses the selected animation frame and waits for pending image data.

Commands ran from `../ghostel`:

```sh
/Users/fuyu0425/.asdf/installs/zig/0.16.0/zig build -Doptimize=ReleaseFast -Dcpu=baseline
/Users/fuyu0425/.asdf/installs/zig/0.16.0/zig build test
```

Both commands exited with status 0.
The build wrote to `zig-out`, not the installed module path.
A fresh batch Emacs loaded that module and ran `ghostel-kitty-test.el`: 34 passed, 0 unexpected.
The new checks cover negative relative origins, virtual-root placement changes, and selected animation-frame bytes.

A separate smoke command started a real shell through each PTY path.
It sent `migration-smoke` through `ghostel-send-string` and observed the shell's color-coded response as terminal text:

```text
PTY=native OUTPUT="READYrnreceived:migration-smoke"
PTY=Emacs OUTPUT="READYrnreceived:migration-smoke"
```

The smoke command verified the native-process property for each path and removed only its own disposable buffers and processes.

Source inspection confirmed these direct Zig exports in the pinned dependency:

- `TerminalStream.Handler.paste`: `src/terminal/stream_terminal.zig:310`.
- `Paste`: `src/terminal/main.zig:64`.
- `clipboard.Read`: `src/terminal/clipboard.zig:61`.
- `sys.randomSecure`: `src/terminal/sys.zig:73`.

These exports provide the host API. They do not prove a clipboard exchange or Agent attachment.
T003 is complete. T005 remains open.
No native module was installed or loaded into the user's Emacs. No existing Session was restarted.

The broader regression gate used the Makefile's per-file process isolation.
Each of the 33 core test files ran separately with both `ghostel-test-run-elisp` and `ghostel-test-run-native`.
Every invocation loaded `zig-out` with automatic module installation disabled.

```text
66 invocations: all exited 0
1191 selected, 1183 expected results, 0 unexpected, 8 skipped
```

An earlier combined-process run reported three password-check failures.
Some line-mode tests set `ghostel-detect-password-prompts` globally, which affects later password checks in that combined run.
The isolated native shell checks passed all 34 applicable tests and skipped one.
No password code or tests changed.

### T005: host bridge and end-to-end failure boundary

Source inspection supports a host bridge before the parsed `.kitty_clipboard` action reaches the original upstream handler.
The bridge must copy the parser's borrowed request bytes and dispatch them on Emacs's main thread.
It must use the original input handler, because the native-process stream and terminal stream own separate grants.
The synchronous clipboard callback must finish before its stack-owned reply context expires.
This remains a proposed design, not verified implementation.

The bridge also needs exact terminal/process identity, generation checks, bounded request storage, and cancellation during reset and destruction.
The host must check the advertised MIME, standard clipboard location, active gesture, and deadline before reading image bytes.
The upstream grant table remains the only password owner.
The host must not store image bytes at gesture time or enable remembered grants.

The native reader's PTY callback assumes reader-thread lifetime protection.
The main-thread bridge cannot reuse that assumption.
It must capture the upstream-encoded response and send it through a fallible, deadline-aware writer outside the terminal lock.
Clipboard wake notifications must not block on the event pipe while holding that lock.
These are host implementation requirements, not reasons to change OMP.

Sources:

- `../ghostel/src/NativeProcess.zig:46-53,95-173,281-347`.
- `../ghostel/src/handler.zig:29-101`.
- Candidate `src/terminal/osc/parsers/kitty_clipboard_protocol.zig:18-36,130-153`.
- Candidate `src/terminal/stream_terminal.zig:848-977`.
- Candidate `src/terminal/clipboard.zig:55-100`.

The remaining contract blocker is narrower than the missing wire acknowledgement:

1. FR-010 requires an expired transfer to attach nothing.
2. OMP waits for `DONE` and has no receiver deadline in this controller.
3. A successful local write can leave a complete response queued in SSH or zmx.
4. A host timeout cannot withdraw those queued bytes.

[INFERENCE] Delayed delivery can therefore attach a complete image after the host reports a timeout.
A host-only deadline can stop unsent bytes and report uncertainty. It cannot guarantee remote non-attachment.
The recorded missing-reply probe confirms that the current controller does not expire its pending read itself.
This conclusion does not rely on an absent acknowledgement packet alone.

Source: OMP `packages/coding-agent/src/utils/enhanced-paste.ts:83-128,178-199`.

The wire contract also requires the terminal never to send a DATA packet it cannot complete.
The transport uses partial system writes, so a disconnect can interrupt a packet already in transit.
[INFERENCE] Neither a host callback nor a receiver change can make those stream writes atomic.
The contract must distinguish complete response preparation from complete packet delivery and complete image attachment.
Source: `../ghostel/src/PosixPtyProcess.zig:261-310`.

No malformed or adversarial exchange ran for these findings.
T005 remains open pending a requirement decision.
The choices are explicit host-only delivery uncertainty, or a separately approved receiver-side design and OMP scope extension.
Neither choice permits zmx source changes or a false attachment-success message.

### Approved receiver design scope and native wire proof

The user selected **Permit an OMP receiver design**.
The design may extend OMP with receiver expiry and transfer validation.
The wire contract must change before implementation. The no-partial-attachment requirement and prohibition on zmx source changes remain.
T005 stays open during this design work.

The candidate design adds a metadata MIME representation to the existing OSC 5522 exchange.
OMP requests that representation and its selected image in one authorized read with a fresh standard request `id`.
The host reads image bytes once at request time.
The metadata carries the image MIME, byte count, SHA-256, and remaining host time budget.
The receiver must validate these values before committing an attachment.
The upstream response already echoes the request `id`, so the metadata need not repeat it.

A disposable Zig program exercised the pinned upstream implementation directly.
It called `TerminalStream.Handler.paste`, obtained the normal grant, sent a paired read, and answered through `clipboard.Read.reply`.
It used synthetic byte streams, not clipboard contents or actual Agent images.

| Bytes | Packets | Terminator | Exact bytes and SHA-256 |
|---:|---:|---|---|
| 1 | 4 | BEL | Passed |
| 4095 | 4 | ST | Passed |
| 4096 | 4 | BEL | Passed |
| 4097 | 5 | ST | Passed |
| 5242880 | 1283 | BEL | Passed |

All 1300 packets echoed the request ID.
The native callback observed five authorized reads and zero gesture-time payload reads.
Each DATA packet contained at most 4096 decoded bytes.
OMP's existing `parseOsc5522Packet` parsed all 1300 packets and both MIME names unchanged.
This proves native framing compatibility, not a completed OMP verifier or attachment.

A separate fresh Emacs process sent every byte from 0 through 255 through native module string extraction and a disposable PTY.
The child returned all 256 bytes unchanged.
This verifies the binary input boundary without reading a clipboard or changing the live module.

The proposed receiver deadline uses its request-start time plus the host's remaining budget.
It must not use metadata arrival time, which would extend the deadline by network delay.
An arithmetic check covered 100059 schedules with seed `20260926` and arbitrary clock origins.
It accepted 2524 commits, all before the host deadline.
That check assumes both monotonic clocks measure the same elapsed duration.
Suspend behavior, timer stalls, asynchronous image preparation, and the final editor commit still need explicit contract decisions.

No OMP production source changed during these checks.

### Approved receiver outcome decisions and prerequisite

The user approved all three remaining behavior decisions:

- Report **delivery unconfirmed** when connection loss leaves attachment possible.
- Apply the deadline at the **receiver commit decision**, under the documented clock model.
- **Refuse while busy**, without replacing the active attempt.

The specification and wire contract now state these decisions.
The ten-second visible result remains a measured acceptance target.
The receiver must still reject incomplete or mixed image data.
Read-on-request timing remains unchanged.

The receiver design uses a provisional watchdog before metadata arrives.
Validated metadata can shorten that watchdog but cannot extend it.
Every awaited image-preparation step must finish before a one-shot synchronous editor commit gate.
Stop, disable, Session changes, and expired state must prevent later preparation results from committing.

T005R records the approved OMP receiver implementation prerequisite.
T005 remains open until focused checks and a real receiver-to-editor smoke run pass.
The original Ghostel and package story tasks remain gated.
The disposable native design-probe source, build output, and caches were removed after the recorded wire checks.

### T005R: Verified receiver and actual editor boundary

OMP now implements the approved paired-MIME receiver.
It validates canonical metadata, request identity, MIME order, byte count, and SHA-256 before preparing an image.
The watchdog remains active through preparation.
The final synchronous gate checks identity, cancellation, and expiry before editor mutation.
Busy gestures leave the active attempt unchanged.
Stop, Session changes, and late results cannot revive canceled work.

The first integrated run found two new test-fixture failures and two test type errors.
The fixture used a relative temporary directory as an absolute image source.
The corrected fixture uses an absolute temporary path and a valid synthetic PNG.
It also isolates clipboard access from the host clipboard.

Observed verification:

| Check | Result |
|---|---|
| Final focused receiver, editor, local-paste, and lifecycle checks | 240 passed across 12 files after the lifecycle correction. |
| CLI smoke before lifecycle correction | The receiver subscribed after early TUI startup. Mode 5522 never enabled. |
| Late-start-listener regression before correction | 2 passed, 1 failed. The late subscriber received zero notifications. |
| Receiver, editor, and lifecycle checks after correction | 115 passed across 3 files. |
| Coding-agent type check | `bun run --cwd packages/coding-agent check:types` passed. |
| TUI type check | `bun run --cwd packages/tui check:types` passed. |
| Focused lint | `oxlint` passed for all 12 changed source and test files. |
| Actual isolated CLI, first synthetic image | 1108 bytes. Visible image `#1` after 40 ms. |
| Actual isolated CLI, expired transfer | A one-millisecond budget expired before image delivery. It reserved no attachment number. |
| Actual isolated CLI, image after expiry | 5244372 bytes. Visible image `#2` after 709 ms. No image `#3`. |

The smoke used the actual source CLI, a local PTY, and a private temporary home and Agent directory.
The user approved skipping optional provider setup for this check.
No provider was selected, no credentials were supplied, and no model turn was submitted.
The helper matched OMP's generated request ID and requested MIME pair before each reply.
It stopped only its own disposable process and removed its temporary directory.
The disposable smoke helper was removed after the evidence was recorded.

This proves the receiver-to-editor path, including the measured large-image result on that local path.
It does not prove Ghostel clipboard service, SSH delivery, zmx integration, or Agent vision acknowledgement.
Those remain original story acceptance checks.

The formatting check found changes in three receiver-owned files and one unrelated model-profile test expression.
The three receiver-owned files were formatted.
The unrelated expression remains unchanged. No full formatting pass is claimed.

T005 is complete.
Stock zmx supplies the observed read-only leadership marker and mode replay.
The approved receiver now owns verified expiry and the final editor decision.
The host bridge design keeps native grant ownership and a synchronous clipboard callback on Emacs's main thread.
The original stories must still implement and verify that bridge and the package attachment marker.

### T012: actual remote mode replay passed

Two disposable OMP Agents ran on the approved `v12mac` host through stock zmx 0.8.1.
The candidate binary used private homes, workspaces, state, and socket directories.
It did not replace the installed OMP binary.
The first Emacs delivered three images to Session A and two to Session B.
A second fresh Emacs attached with `zmx attach NAME false`.
Ghostel reported mode 5522 and replayed the existing attachments before the probe sent any Agent input.
The second Emacs continued the alternating sequence to five images per Session.

The Agent PIDs stayed `38434` and `38659`.
Both working directories stayed unchanged.
The 5244372-byte PNG appeared after 1540 ms.
Each gesture read its payload once, and the other Session retained its attachment count.
All ten remote original-image hashes matched the local synthetic clipboard hashes.

No additional replay code is necessary in Ghostel.
The existing stream and stock zmx replay satisfy T012 without synthetic input, Agent restart, or zmx changes.
The package still needs its production attachment marker and leadership preflight.

OMP created its ordinary `local://pasted-image-*` attachment files after verified receipt.
`InputController.#normalizeAndInsertPastedImage` and `#persistPastedImage` own that storage, not the transport.
The original bytes matched even when OMP's existing image rules enlarged small editor previews.
The first probe incorrectly rejected those permitted Agent files.
The corrected probe restricted new files to that storage location and verified their hashes.
Other fixture corrections waited for complete replay rather than a startup banner that had scrolled offscreen.

No model turn ran. Agent vision acknowledgement remains unverified.
T015 subsequently verified local Claude/Codex/OMP image attachments through the actual system clipboard.
The quickstart records those results, mixed-representation remote delivery, and the preserved text variants.

## Approved zmx backpressure correction: 2026-09-27 UTC

Live acceptance confirmed that stock zmx 0.8.1 discarded input above its 256 KiB PTY queue limit.
The user then approved a source correction, regression checks, and private candidates.
This narrow approval supersedes the earlier prohibition on zmx source changes. Installation still needs separate approval.

The private `0.8.1-cci014-backpressure` candidate passed nine real CLI conservation cases.
It also delivered ten alternating images with two clients attached to each remote Session.
Both images above 5 MiB arrived unchanged in less than 1.8 seconds.
The original Ghostel source supplied the live proof. The discarded foreign-reply hypothesis required no retained Ghostel change.
See [the complete regression, digest, and cleanup record](quickstart.md#private-zmx-backpressure-correction-2026-09-27-utc).
