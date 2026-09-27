# Implementation Plan: Remote Image Paste

**Branch**: `main` (unchanged) | **Date**: 2026-09-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/014-remote-image-paste/spec.md`

The setup script reported `014-remote-image-paste` as the feature identifier. Planning
creates feature artifacts and does not create a commit. The constitution requires work
on the current branch, so the branch stays `main` as it did for feature 013.

## Foundation gate: verified on 2026-09-26

T001, T002, T003, and T004 are complete. The GUI clipboard returned the synthetic PNG bytes unchanged through the `image/png` target.
The native API migration passed its build, Zig checks, 34 graphics checks, and smoke checks through both PTY paths.
The build used `zig-out`. The installed and live native modules remain unchanged.
See [the migration evidence](research.md#t003-native-api-migration-passed).

The original scope allowed stock zmx upgrades but prohibited source changes.
Live acceptance later confirmed input loss in stock zmx 0.8.1.
The user approved a zmx backpressure fix, regression checks, and private candidates.
Installation needs separate approval. No further model turns are authorized.
A disposable local check verified mode 5522 replay and read-only leader identification through a tracked client marker.
See [the stock upgrade check](research.md#stock-upgrade-check-081).

The installed local zmx is 0.8.1. Existing local and remote Session daemons answered `print-env`, but their attachments lack a package marker.
A disposable adoption check verified that a new attachment can add a marker without restarting the Agent.
T005 identified the host bridge design and the limits of host-only timeout reporting.
A host cannot withdraw queued response bytes.
The approved OMP receiver now validates transfer integrity and enforces the receiver commit deadline.
The wire contract records unconfirmed delivery and busy refusal.
T005R passed focused checks, both package type checks, and an actual local CLI receiver-to-editor smoke run.
See [the failure boundary](research.md#t005-host-bridge-and-end-to-end-failure-boundary)
and [the native wire proof](research.md#approved-receiver-design-scope-and-native-wire-proof).

## Summary

Make an image on the local clipboard reach an Agent that runs on another host, using
the terminal paste-event clipboard standard (OSC 5522 with private mode 5522). The
local terminal serves the clipboard, so the Agent's host needs no clipboard and
receives no file.

Four repositories are now in scope:

1. **Ghostel** gains native paste-event support through its direct Zig `ghostty-vt` module.
   The dependency update also needs API migration, not just a pin change.
   Ghostel must expose one capability predicate and one paste command to Elisp.
2. **OMP** gains receiver expiry and transfer validation under the revised wire contract.
   The receiver must validate the complete image before its final editor commit.
   Existing local and legacy terminal routes must keep their behavior.
   Verified receipt requires a recognized container whose format matches the declared MIME type.
   Only that route enables the shared validator's `requireKnownFormat` argument.
   Ordinary attachments and provider context retain full decoding when the header parser cannot identify the format.
   Both validation modes retain strict base64 validation and rejection of recognized-format disagreement.
3. **claude-code-ide.el** routes a paste gesture in a remote Session of an
   OSC 5522-capable Agent to that command, and keeps today's `C-v` route for local
   Sessions and for Agents without the client side.
4. **zmx** gains lossless input backpressure without changing its IPC format or leadership rules.
   Its private candidate must preserve queued input when the PTY reader stalls.

The approved zmx exception covers input backpressure and its regression checks only.
The package retains the existing zmx interfaces and attachment lifecycle.

## Technical Context

**Language/Version**: Emacs Lisp on Emacs 28.1 or later for both the package and the
Ghostel interface. Zig 0.16.0 for the Ghostel native module, as its build already
requires.

**Primary Dependencies**: Ghostel, libghostty-vt, zmx, OpenSSH, and an OSC 5522-capable Agent (`omp` today).
The existing package supports zmx 0.7.1 and 0.8.0 for other operations.
Stock zmx 0.8.1 supplies the required replay and owner-query interfaces, but does not reliably preserve large input.
The remote image route also needs the approved backpressure correction. Unrelated operations keep their current compatibility.

**Storage**: No transfer persistence or Session field. Image transport remains in memory.
OMP may use its ordinary attachment storage after verified receipt.

**Testing**: ERT in `claude-code-ide-tests.el` for the route decision and the
explanations, gated by `./scripts/compile-and-test.sh`. Zig unit tests plus Elisp and
native tests in Ghostel (`make test-zig`, `make test-native`). One live end-to-end
walkthrough from [quickstart.md](quickstart.md).
The approved receiver prerequisite also needs Bun receiver tests, editor-boundary checks, and an actual local TUI smoke run.

**Target Platform**: Emacs on macOS or X11 with a graphical clipboard, attached to an
Agent on an approved POSIX remote host through SSH, zmx, and Ghostel.

**Project Type**: Emacs package plus a terminal-backend package for the same Emacs,
with an OS-level dependency in the terminal backend only.

**Performance Goals**: A 5 MB image completes the gesture within 10 seconds. The route
decision adds no measurable delay to a text paste. A local Session's paste path stays
as fast as today, because it keeps the current code path.

**Constraints**: No required dependency. The package loads, byte-compiles, and passes
its suite with no Ghostel module support present (Principle III).
The transport never modifies image bytes, creates an image file, or substitutes a path (FR-005, FR-017).
The clipboard is read only for a gesture in the serving Session (FR-006, FR-007). Host
approval, authentication, session ownership, and start, attach, reattach, detach, and
Stop behavior do not change (FR-012).

**Scale/Scope**: One Ghostel capability predicate and paste command, native clipboard handoff, shared package routing, and verified OMP receipt.
The receiver adds integrity checks, commit-time expiry, and cancellation through existing Session and TUI ownership points.

The native API migration and GUI byte access passed.
The clipboard handoff, package attachment identity, and integrated receiver path still need implementation evidence.

## Constitution Check

*GATE: Passed before Phase 0 research and after Phase 1 design.*

| Gate | Before research | After design | Evidence and planned compliance |
|---|---|---|---|
| I. Shared session core, thin Agent adapters | Pass | Pass | One route decision lives in the shared session layer. The set of Agents with a client-side implementation is one data list in that layer, not a per-Agent code path. No Agent adapter gains paste logic. |
| II. Batch-verifiable quality gate | Pass | Pass | ERT covers the route decision and every refusal; the full `./scripts/compile-and-test.sh` gate stays required. Ghostel's Zig and native suites cover the protocol bytes. No test needs a display or a remote host. |
| III. Optional dependencies stay optional | Pass | Pass | Ghostel stays optional, reaches through `(require 'ghostel nil t)`, and is probed at the point of use. A missing or older module produces an actionable `user-error` and sends nothing. The package loads, byte-compiles, and passes with no module support. |
| IV. Ghostel-only terminal support | Pass | Pass | All terminal interaction goes through the Session buffer and its owned process. The new capability lives in Ghostel, the sole terminal runtime. No alternative terminal, no terminal choice, no fallback renderer. |
| V. Simplicity and compatibility | Pass | Pass | One capability predicate and one paste entry point. No version arithmetic in the package, no new dependency, no configuration option. The Ghostel paste commands keep their current code paths. |
| VI. Local and remote workflow parity | Pass | Pass | The same gesture produces the same attachment on both. The one difference, the transport, is required by the remote constraint that the Agent cannot read the local clipboard, and it is named in the spec. Local behavior is unchanged. Every refusal is explicit. |
| ADR 0001 zmx-backed sessions | Pass | Pass | zmx stays the process owner. T041 corrects input backpressure under the approved exception. IPC, leadership rules, and attachment lifecycle remain unchanged. |
| ADR 0003 session directory stays bare | Pass | Pass | No directory, path, or file enters any command or message. The transport carries MIME bytes only. |
| Repository workflow | Pass | Pass | Work on the current checkout. Planning creates artifacts and no commit. No issue tracker. |

Required remote difference, stated per Principle VI:

| Difference | Remote constraint |
|---|---|
| Transport | The Agent's host has no local clipboard, so the local terminal must serve the bytes. |
| No capability available | The installed terminal build, or the multiplexer's leadership state, can prevent delivery. The Session explains it instead of substituting an operation. |

The approved receiver decisions and T005R verification close the foundation gate. Original story implementation can now start.

## Project Structure

### Documentation (this feature)

```text
specs/014-remote-image-paste/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── osc-5522-exchange.md
│   └── ghostel-package-interface.md
└── checklists/
    └── requirements.md
```

`tasks.md` belongs to `/speckit.tasks` and is not created by this command.

### Source code, package repository

```text
claude-code-ide-session.el   # Route decision, capability probe call, explanation messages
claude-code-ide-tests.el     # ERT: route decision, refusals, unchanged paste behavior
README.org                   # User-visible capability note for remote Sessions
docs/remote.org              # Remote workflow: what works, what is refused, and the remedy
docs/zmx.org                 # One note on the leadership condition, unchanged elsewhere
AGENTS.md                    # Only if the change makes its guidance stale
scripts/compile-and-test.sh  # Required implementation gate, unchanged
```

### Source code, Ghostel repository

```text
build.zig.zon                # ghostty pin moves to the commit containing mode 5522 support
src/GhostelTerm.zig          # Direct Zig paste and clipboard-read effects
src/handler.zig              # Clipboard read routing to the host, beside the OSC 52 arms
src/module.zig               # Exported capability query, if a native symbol is needed
src/version.zig              # Module version, raised with the capability
lisp/ghostel.el              # Capability predicate, paste command, clipboard reply helpers
lisp/ghostel-module-install.el # Minimum module version raised in step with the feature
test/ghostel-osc-test.el     # Read-request and reply coverage beside the OSC 52 tests
test/                        # Zig unit tests for packets, grants, chunking, rejections
Makefile                     # Existing test targets, unchanged
```

### Source code, OMP repository

```text
packages/coding-agent/src/utils/enhanced-paste.ts
packages/coding-agent/src/modes/controllers/input-controller.ts
packages/coding-agent/src/modes/interactive-mode.ts
packages/tui/src/tui.ts
packages/coding-agent/test/   # Receiver and actual editor-boundary checks
packages/tui/test/            # Terminal lifecycle behavior where required
```

**Structure Decision**: Keep the protocol in the terminal library and the route
decision in the package's shared session layer. Add no Emacs-side protocol parser, no
adapter per Agent, and no new configuration option.
The only multiplexer change is the approved input-backpressure correction and its regression checks.

## Phase 0: Research Results

See [research.md](research.md).

Resolved decisions:

- Use OSC 5522 with mode 5522 as the only transport; the terminal serves the
  clipboard.
- Offer the route to Agents that implement the client side. That is `omp` today.
- Bump Ghostel's ghostty pin to the merge commit of upstream PR `#13978`, because the
  current pin parses OSC 5522 and drops it.
- Give Ghostel secure randomness, a synchronous clipboard-read callback, and the direct Zig handler's paste operation.
- Retain the verified zmx replay and tracked-environment interfaces. Correct input backpressure under the approved scope exception.
- Keep the local `C-v` route. Use the terminal route only for a remote Session of a
  capable Agent.
- Detect capability through one Ghostel predicate, never through version comparison.
- Verify native framing, receiver commit, package routing, and the live walkthrough.

## Phase 1: Design

### Terminal capability, Ghostel native module

The candidate ghostty pin is `e4240606752e5e4eb480b69104d75db0054f71c8`.
T003 migrated the scrollback, stream-constructor, relative-placement, and image-data APIs.
The candidate passed its build and targeted checks with Zig 0.16.0.
The upstream sources remain unchanged.

Install the three host obligations:

1. **Secure random.** Use the existing terminal's `std.Io.Threaded` secure random path unless execution identifies a missing requirement.
2. **Clipboard read.** Use the direct Zig `clipboard.Read` callback and reply synchronously with raw MIME bytes.
   The candidate invalidates the callback context when it returns. The original deferred-reply design is not valid.
   Resolve the Emacs-thread handoff before implementing this callback.
   All inspected package Sessions use the native reader thread, so a main-thread-only callback is not sufficient.
   Preserve read-on-request timing. Do not replace it with a gesture-time snapshot.
3. **Paste.** Use `TerminalStream.Handler.paste` with MIME/data pairs through the existing native handler.
   Keep protocol framing in libghostty. Preserve the old paste commands and their code paths.

Keep the OSC 52 arms in `src/handler.zig` unchanged.

### Ghostel Elisp interface

Add the two entry points of
[contracts/ghostel-package-interface.md](contracts/ghostel-package-interface.md):

- `ghostel-paste-events-supported-p`: reports whether the loaded module can perform
  the exchange for a given terminal. Never signals.
- `ghostel-paste-clipboard`: performs one terminal paste with the local clipboard,
  including image MIME data when the clipboard has an image.

Keep `ghostel-yank`, `ghostel-paste`, `ghostel-paste-string`, and their keybindings on
their current code paths. The new command is additive.

Answer a read request only through the original upstream handler's grant.
Read the clipboard at request time and refuse unknown, spent, expired, or out-of-policy requests.
Prepare a complete encoded reply before transport writes.
Transport interruption can split a packet. The verified receiver must prevent partial image attachment.

Raise `src/version.zig`, `ghostel-module-install.el`, and the package metadata version
together, so the capability predicate and the minimum module version move in step.

### Package route decision

Extend `claude-code-ide-session-paste-clipboard` in `claude-code-ide-session.el`. Keep
its current shape: one command, decided before any byte is sent.

```text
gesture
  -> image on the clipboard?
       no  -> ghostel-yank                      (unchanged)
       yes -> Session local?
                yes -> send C-v                 (unchanged)
                no  -> CLI implements the client side?
                         no  -> keep the CLI's current behavior, no new message
                         yes -> terminal supports paste events?
                                  yes -> ghostel-paste-clipboard
                                  no  -> explain the condition, send nothing
```

Add the client-side Agent set as one private list in the shared session layer, beside
the existing image-capable list, with a comment naming OSC 5522. Do not add a field per
Agent definition: the capability describes the Agent's protocol support, and one list
keeps the shared layer as the single decision point (Principle I).

Keep `claude-code-ide-session--clipboard-image-p` as the package image predicate.
Ghostel owns MIME advertisement and the authorized byte read.

Explanations follow [contracts/ghostel-package-interface.md](contracts/ghostel-package-interface.md).
Use an actionable `user-error` at the point of refusal.
Successful routes and unchanged legacy routes produce no new package message.

### Multiplexer

T005 verified read-only leadership observation and mode replay through existing zmx interfaces.
T041 completed the approved input-backpressure correction after stock zmx dropped accepted bytes.
The private candidate preserves queued input, FIFO order, responsive control requests, and EOF handling.
Its regression checks and private local/remote acceptance passed. See [the recorded evidence](quickstart.md#private-zmx-backpressure-correction-2026-09-27-utc).
The exception changes neither IPC nor leadership rules, host approval, authentication, or the attachment lifecycle.
Installation requires separate approval. The exception authorizes no further model turns or unrelated zmx changes.

### Data and interface

- [data-model.md](data-model.md) defines the route rules, clipboard content, grant,
  capability report, exchange states, and invariants.
- [contracts/osc-5522-exchange.md](contracts/osc-5522-exchange.md) defines the wire
  exchange and the passthrough requirements.
- [contracts/ghostel-package-interface.md](contracts/ghostel-package-interface.md)
  defines the provider and consumer obligations and the compatibility matrix.
- [quickstart.md](quickstart.md) defines the batch checks and the live walkthrough.

### Verification design

Package ERT cases, all at observable seams:

1. A local Session with an image on the clipboard sends `C-v` and calls no terminal
   paste.
2. A local Session with text uses the text paste.
3. A remote Session of a capable Agent with a capable terminal calls the terminal paste
   once, and sends no `C-v`.
4. A remote Session of a capable Agent with no terminal capability explains and sends
   nothing.
5. A remote Session of a non-capable Agent keeps that Agent's current behavior and
   produces no new message.
6. A clipboard with no image keeps every existing path.
7. Each refusal or unconfirmed-delivery explanation names the observed condition and a useful next action.
8. Existing paste tests pass unchanged.

Test the routing decision and its user-visible outcome. Do not assert message wording
character by character, and do not test the protocol in the package suite; the protocol
belongs to Ghostel's tests.

Ghostel test design:

- Zig: event packet shape, MIME list, grant presence, terminator handling, granted
  versus ungranted reads, MIME selection, 4096-byte chunking and ordering, refusal on a
  spent grant, refusal on an unadvertised MIME, rejection of an unsafe text payload,
  and the bracketed-paste fallback when the mode is off.
- Native and Elisp: a fake application writes an OSC 5522 read request and receives the
  reply; the existing OSC 52 tests stay unchanged.

OMP receiver checks:

- Verify request identity, strict framing, metadata, exact byte count, and SHA-256 before image preparation.
- Verify initial timeout, shortened timeout, and commit-time expiry when timer callbacks run late.
- Hold actual image preparation across expiry and cancellation. Observe no pending editor mutation.
- Refuse overlapping gestures without replacing the active attempt.
- Preserve local image paths, text destinations, source links, and bracketed-paste ordering.
- Exercise stop, restart, Session changes, and stale callbacks without reviving an old transfer.


Live validation follows [quickstart.md](quickstart.md) steps 3 to 6: local parity, the
remote end-to-end paste, a large image, and the five failure conditions.

During implementation, run the focused ERT selector and the Ghostel Zig tests first,
then `./scripts/compile-and-test.sh`, then the live walkthrough.

## Post-Design Constitution Check

Implementation checks resolved the original leadership, reattachment, and input-loss blockers through T005 and the approved T041 exception.
The [acceptance record](quickstart.md) contains the observed gate results and private-candidate evidence.

- The protocol stays in the terminal library. The package holds one route decision.
- The package keeps working with no Ghostel module support, and explains the refusal.
- The multiplexer includes only the approved input-backpressure correction. IPC and leadership rules remain unchanged.
- Host approval, authentication, and Session lifecycles remain unchanged. Installation requires separate approval.
- The local paste path is byte-for-byte unchanged, so the working workflow cannot
  regress through this feature.
- Batch tests cover both repositories, and the live walkthrough proves the chain.

## Complexity Tracking

| Violation | Why needed | Simpler alternative rejected because |
|---|---|---|
| The feature spans two repositories (package plus Ghostel) and one OS-level dependency pin | The capability must exist in the terminal runtime, which is the only component that owns the local clipboard and the terminal protocol state (Principle IV) | Implementing OSC 5522 in Emacs or in the package would duplicate upstream work, including grant minting and chunking, and would parse bytes the native parser already owns |
| A development-version dependency pin moves forward in Ghostel | No released ghostty version contains `ghostty_terminal_paste` and mode 5522; Ghostel already pins a development version | Waiting for a release blocks the requested feature; re-implementing the protocol in Ghostel diverges from the library Ghostel tracks |
| One Agent gains the behavior; the others do not | Only `omp` implements the client side of the standard | Teaching other Agents the protocol is outside this package, and claiming support the code does not have would make the tests false |
