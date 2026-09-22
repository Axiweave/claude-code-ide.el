# Implementation Plan: Remote Image Paste

**Branch**: `main` (unchanged) | **Date**: 2026-09-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/014-remote-image-paste/spec.md`

The setup script reported `014-remote-image-paste` as the feature identifier. Planning
creates feature artifacts and does not create a commit. The constitution requires work
on the current branch, so the branch stays `main` as it did for feature 013.

## Summary

Make an image on the local clipboard reach an Agent that runs on another host, using
the terminal paste-event clipboard standard (OSC 5522 with private mode 5522). The
local terminal serves the clipboard, so the Agent's host needs no clipboard and
receives no file.

Two repositories change, in this order:

1. **Ghostel** gains native paste-event support: bump the pinned ghostty dependency to
   a commit containing `ghostty_terminal_paste` and mode 5522, install the terminal
   clipboard-read callback, paste through the new API, and expose one capability
   predicate and one paste command to Elisp.
2. **claude-code-ide.el** routes a paste gesture in a remote Session of an
   OSC 5522-capable Agent to that command, and keeps today's `C-v` route for local
   Sessions and for Agents without the client side.

The multiplexer needs no change. Stock zmx already forwards the read request to the
local terminal and carries the leader client's answer back to the Agent.

## Technical Context

**Language/Version**: Emacs Lisp on Emacs 28.1 or later for both the package and the
Ghostel interface. Zig 0.16.0 for the Ghostel native module, as its build already
requires.

**Primary Dependencies**: Ghostel as the sole terminal runtime, its native module built
against libghostty-vt, stock zmx (0.7.1 and 0.8.0 verified by the package), OpenSSH,
and one Agent that implements the client side of OSC 5522 (`omp` today). The package
adds no dependency and no hard require.

**Storage**: None. No Session field, no persistence, no file. The image exists in
memory for the duration of one exchange.

**Testing**: ERT in `claude-code-ide-tests.el` for the route decision and the
explanations, gated by `./scripts/compile-and-test.sh`. Zig unit tests plus Elisp and
native tests in Ghostel (`make test-zig`, `make test-native`). One live end-to-end
walkthrough from [quickstart.md](quickstart.md).

**Target Platform**: Emacs on macOS or X11 with a graphical clipboard, attached to an
Agent on an approved POSIX remote host through SSH, zmx, and Ghostel.

**Project Type**: Emacs package plus a terminal-backend package for the same Emacs,
with an OS-level dependency in the terminal backend only.

**Performance Goals**: A 5 MB image completes the gesture within 10 seconds. The route
decision adds no measurable delay to a text paste. A local Session's paste path stays
as fast as today, because it keeps the current code path.

**Constraints**: No required dependency. The package loads, byte-compiles, and passes
its suite with no Ghostel module support present (Principle III). The image bytes are
never modified, never written to a file, and never replaced by a path (FR-005, FR-017).
The clipboard is read only for a gesture in the serving Session (FR-006, FR-007). Host
approval, authentication, session ownership, and start, attach, reattach, detach, and
Stop behavior do not change (FR-012).

**Scale/Scope**: One paste command in Ghostel, three native wiring points, one
capability predicate in the package, and one route decision. One Agent gains the
behavior. One terminal pin moves forward.

No technical context item remains unresolved. Two implementation-time checks are
recorded in [research.md](research.md) under "Open items": the new pin's exported
surface under Ghostel's build, and the availability of a byte-level image read from the
macOS GUI selection.

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
| ADR 0001 zmx-backed sessions | Pass | Pass | zmx stays the process owner. The feature relies on its existing forwarding and leadership rules and changes neither. |
| ADR 0003 session directory stays bare | Pass | Pass | No directory, path, or file enters any command or message. The transport carries MIME bytes only. |
| Repository workflow | Pass | Pass | Work on the current checkout. Planning creates artifacts and no commit. No issue tracker. |

Required remote difference, stated per Principle VI:

| Difference | Remote constraint |
|---|---|
| Transport | The Agent's host has no local clipboard, so the local terminal must serve the bytes. |
| No capability available | The installed terminal build, or the multiplexer's leadership state, can prevent delivery. The Session explains it instead of substituting an operation. |

No gate violation and no unresolved clarification remains.

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
src/GhostelTerm.zig          # Paste through ghostty_terminal_paste; clipboard-read option
src/handler.zig              # Clipboard read routing to the host, beside the OSC 52 arms
src/module.zig               # Exported capability query, if a native symbol is needed
src/version.zig              # Module version, raised with the capability
lisp/ghostel.el              # Capability predicate, paste command, clipboard reply helpers
lisp/ghostel-module-install.el # Minimum module version raised in step with the feature
test/ghostel-osc-test.el     # Read-request and reply coverage beside the OSC 52 tests
test/                        # Zig unit tests for packets, grants, chunking, rejections
Makefile                     # Existing test targets, unchanged
```

**Structure Decision**: Keep the protocol in the terminal library and the route
decision in the package's shared session layer. Add no Emacs-side protocol parser, no
adapter per Agent, and no new configuration option. The multiplexer is untouched.

## Phase 0: Research Results

See [research.md](research.md).

Resolved decisions:

- Use OSC 5522 with mode 5522 as the only transport; the terminal serves the
  clipboard.
- Offer the route to Agents that implement the client side. That is `omp` today.
- Bump Ghostel's ghostty pin to the merge commit of upstream PR `#13978`, because the
  current pin parses OSC 5522 and drops it.
- Give Ghostel the three host obligations: secure random for grants, the clipboard-read
  callback, and pasting through `ghostty_terminal_paste`.
- Treat zmx as passthrough. The read request reaches the local terminal, and the
  leader client's answer reaches the Agent. A non-leading client's answer is lost, and
  the Session explains that condition.
- Keep the local `C-v` route. Use the terminal route only for a remote Session of a
  capable Agent.
- Detect capability through one Ghostel predicate, never through version comparison.
- Verify at three seams plus one live walkthrough.

## Phase 1: Design

### Terminal capability, Ghostel native module

Move the `ghosts` dependency pin in `build.zig.zon` to ghostty commit
`e4240606752e5e4eb480b69104d75db0054f71c8` or a later commit on `main` containing the
same support. The bump is one line plus a verified build; no vendored file is edited by
hand.

Install the three host obligations:

1. **Secure random.** Provide the sys random-secure implementation the grant minting
   needs, or confirm and document the platform default the module already inherits.
2. **Clipboard read.** Install the terminal clipboard-read callback when a terminal is
   created. On a request, hand the MIME type and the granted flag to Elisp through the
   existing deferred-effect path, and reply from Elisp with base64 chunks.
3. **Paste.** Replace the paste encoding call with `ghostty_terminal_paste`, passing
   the clipboard's available MIME types and a MIME reader. The terminal layer then
   chooses between a paste event, bracketed paste, and a plain paste, and rejects an
   unsafe payload instead of writing it.

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

Answer a read request from a stored grant only. Read the clipboard at reply time.
Reply with a refusal when the grant is unknown or spent, when the MIME was not
advertised, or when the selection holds nothing usable. Never send a partial DATA
packet.

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

Keep `claude-code-ide-session--clipboard-image-p` as the image test. Do not add a
second clipboard probe.

Explanations use the three messages contracted in
[contracts/ghostel-package-interface.md](contracts/ghostel-package-interface.md),
delivered as an actionable `user-error` at the point of use. Produce no message on a
successful route and on the unchanged paths.

### Multiplexer

Change nothing. Record the verified rules in `docs/zmx.org`: application output reaches
the local terminal with OSC sequences intact, and the leader client's input reaches the
Agent. Add one sentence to `docs/remote.org` about the leadership condition and its
remedy, because it is the one remote-only failure a user can meet.

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
7. The three explanation messages name the condition and the action.
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

Live validation follows [quickstart.md](quickstart.md) steps 3 to 6: local parity, the
remote end-to-end paste, a large image, and the five failure conditions.

During implementation, run the focused ERT selector and the Ghostel Zig tests first,
then `./scripts/compile-and-test.sh`, then the live walkthrough.

## Post-Design Constitution Check

The design still passes every gate above.

- The protocol stays in the terminal library; the package holds one route decision.
- The package keeps working with no Ghostel module support, and explains the refusal.
- The multiplexer, host approval, authentication, and session lifecycles are untouched.
- The local paste path is byte-for-byte unchanged, so the working workflow cannot
  regress through this feature.
- Batch tests cover both repositories, and the live walkthrough proves the chain.

## Complexity Tracking

| Violation | Why needed | Simpler alternative rejected because |
|---|---|---|
| The feature spans two repositories (package plus Ghostel) and one OS-level dependency pin | The capability must exist in the terminal runtime, which is the only component that owns the local clipboard and the terminal protocol state (Principle IV) | Implementing OSC 5522 in Emacs or in the package would duplicate upstream work, including grant minting and chunking, and would parse bytes the native parser already owns |
| A development-version dependency pin moves forward in Ghostel | No released ghostty version contains `ghostty_terminal_paste` and mode 5522; Ghostel already pins a development version | Waiting for a release blocks the requested feature; re-implementing the protocol in Ghostel diverges from the library Ghostel tracks |
| One Agent gains the behavior; the others do not | Only `omp` implements the client side of the standard | Teaching other Agents the protocol is outside this package, and claiming support the code does not have would make the tests false |
