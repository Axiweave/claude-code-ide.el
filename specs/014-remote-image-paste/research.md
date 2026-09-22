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

**Decision**: Treat the zmx path as passthrough. The package must hold the local
terminal client as the input leader, and must explain the condition when it is not.
Ship no zmx change.

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

**Rationale**: The transport already carries both directions. A zmx change would be
unnecessary work in another repository, and the failure it would address has an
honest user-visible answer.

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

- Confirm that the new ghostty pin exports `ghostty_terminal_paste` and the
  clipboard-read option through the libghostty-vt `c/` surface that Ghostel's module
  builds against, and that the module still builds under Zig 0.16.0. UNVERIFIED until
  the bump is attempted.
- Confirm which grant/random-secure default applies when the embedder installs no
  override, and whether Ghostel must supply one. UNVERIFIED.
- Confirm that Ghostel's Emacs side can read image bytes from the GUI selection on
  macOS (a `public.png` or `image/png` target read) for the read reply. The target
  *detection* already exists in the package
  (`claude-code-ide-session--clipboard-image-p`, which reads `gui-get-selection`
  `TARGETS`), but a byte read is not yet exercised anywhere. UNVERIFIED.
