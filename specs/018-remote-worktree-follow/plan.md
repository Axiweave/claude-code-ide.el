# Implementation Plan: Remote Worktree Follow

**Feature**: `018-remote-worktree-follow` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/018-remote-worktree-follow/spec.md`

## Summary

A remote Agent that moves to another worktree must move its Session row too.
The OSC 7 report already reaches `claude-code-ide-session-relocate`. That
function drops it because the path is remote. The plan:

1. Make `relocate` accept a TRAMP report for a remote Session and store the
   bare localname (research R2).
2. Rewrite the Session metadata so a git row keeps its group with no branch
   (R3).
3. Rebuild items, save state, and queue one remote metadata probe for the
   new directory (R4, R5).
4. Remove three live-directory checks so a move does not rebuild the project
   view (R6, FR-011).

## Technical Context

**Language/Version**: Emacs Lisp, Emacs 28.1+

**Primary Dependencies**: None new. Ghostel (optional) gives the OSC 7 hook.
TRAMP parses the report.

**Storage**: The existing `persist` manager state. No new key.

**Testing**: ERT in `claude-code-ide-tests.el`, run by `./scripts/compile-and-test.sh`

**Target Platform**: Emacs on macOS and Linux. Remote hosts are POSIX hosts
reached by SSH and zmx.

**Project Type**: Emacs package (single project)

**Performance Goals**: The row shows the new branch within 5 s (SC-001). That
is one queued SSH probe.

**Constraints**: No synchronous remote call in the OSC 7 hook. No local file
predicate on a remote path (ADR 0003). No new remote command.

**Scale/Scope**: About 40 changed lines in 3 source files, plus tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Result | Evidence |
|---|---|---|
| I. Shared Session Core | Pass | The change is in the shared Session and manager layers. No Agent adapter changes |
| II. Batch-Verifiable Gate | Pass | New logic gets ERT tests with the existing `with-remote-metadata` fixture. No display, no Ghostel needed |
| III. Optional Dependencies | Pass | No new `require`. The hook path runs only when Ghostel loads |
| IV. Ghostel-Only Terminal | Pass | Uses the Ghostel directory hook |
| V. Simplicity | Pass | No new dependency, option, or struct slot. Deletes three checks |
| VI. Local/Remote Parity | Pass | Research R6: a local move also keeps the old view until a rebuild or `R`. Required difference: a remote move queues an SSH probe, because remote metadata has no synchronous source |

Post-design re-check: Pass. Phase 1 added no violation.

## Project Structure

### Documentation (this feature)

```text
specs/018-remote-worktree-follow/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── elisp-surface.md
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit.tasks
```

### Source Code (repository root)

```text
claude-code-ide.el                  # relocate: remote branch, metadata rewrite
claude-code-ide-manager.el          # --note-remote-move; drop dir check in
                                    #   --remote-layout-request-current-p
claude-code-ide-remote-project.el   # drop dir check in --resume-layout-request
                                    #   and --surviving-view
claude-code-ide-tests.el            # new remote relocate tests; rewrite 2 tests
docs/remote.org                     # "Views After Directory Changes" section
```

**Structure Decision**: Single Emacs package. All files are at the repository
root. No new file.

## Design Notes

- **Order inside `relocate` for a remote Session**: validate, store the
  directory, rewrite the metadata, call `claude-code-ide-manager-refresh-all`
  (loads state and redraws), then call `--note-remote-move`. The refresh
  must come first, because `--note-remote-move` passes `state-loaded-p` t.
- **Errors**: Ghostel demotes hook errors. A `user-error` from host
  validation in the enqueue appears in `*Messages*` and leaves the stored
  move in place.
- **MCP path**: unchanged. It never names a remote Session.
- **Docs**: `docs/remote.org` gets two sentences: a remote Session follows
  the Agent directory report, and views keep the old worktree until `R`.

## Complexity Tracking

No violations.
