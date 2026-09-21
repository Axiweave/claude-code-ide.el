# Implementation Plan: Fix Remote File References

**Branch**: `main` | **Date**: 2026-09-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/009-fix-remote-references/spec.md`

The setup script returned `009-fix-remote-references` as its `BRANCH` feature identifier. The actual Git branch is `main` and remains unchanged.

## Summary

Make the transient `@` action send a path that the receiving remote Session can resolve. The reported example must become `@packages/core/lib/executor.ts#L316` when the Session directory is `/Users/yufu/v12x` on `v12mac`.

Extend the existing reference formatter with an explicit current-file opt-in for remote-aware conversion. Reuse the existing approved RPC destination parser and Session host/directory values. Compare identities before stripping qualification, then compute the path lexically. Preserve selection suffixes and the existing send action.

This phase delivers design only. It does not change Elisp, run implementation tests, reload code, or submit an Agent prompt.

## Technical Context

**Language/Version**: Emacs Lisp, Emacs 28.1 or later.

**Primary Dependencies**: Existing Emacs path operations, `cl-lib`, existing Session accessors, and `claude-code-ide-remote-worktree-target-for-file`. Load the existing remote-worktree module optionally for remote conversion. No new package dependency.

**Storage**: Existing in-memory Session host/directory metadata only. No schema or persistence change.

**Testing**: Existing ERT suite in `claude-code-ide-tests.el`, focused public-command regressions, and `./scripts/compile-and-test.sh` after implementation.

**Target Platform**: Supported Emacs hosts with existing local or RPC-accessible remote Agent Sessions. Ghostel remains the terminal runtime.

**Project Type**: Emacs package with interactive commands and shared Session interaction.

**Performance Goals**: One reference per invocation with no new filesystem query, connection attempt, or remote process. Lexical path work scales with path length. Existing parser matching scales with configured destination count.

**Constraints**: Session directories remain bare host metadata. Preserve local behavior, source context selection, other file-send contracts, optional dependencies, and host approval. Reject unsafe remote context before delivery.

**Scale/Scope**: One current-file command, its existing formatter, regression tests, and existing user documentation. No changes to manager state, MCP at-mention, Agent adapters, keybindings, or remote lifecycle.

## Constitution Check

Both reviews use constitution version 2.0.0.

| Gate | Before research | After design | Evidence and planned compliance |
| --- | --- | --- | --- |
| I. Shared Session core | Pass | Pass | Reuse the shared reference/send path. No Agent-specific branches or Agent configuration changes. |
| II. Batch-verifiable quality | Pass | Pass | Plan includes command-level ERT regressions and the complete compile/test gate. Live validation supplements batch coverage. |
| III. Optional dependencies | Pass | Pass | No new dependency. Optional module loading occurs only for remote conversion. Missing support raises an actionable error. |
| IV. Ghostel-only terminals | Pass | Pass | Terminal delivery remains unchanged. No alternate terminal, owned-process change, or terminal fallback. |
| V. Simplicity and compatibility | Pass | Pass | Reuse the formatter and exact destination parser. One private optional argument preserves a real caller distinction. |
| VI. Local/remote parity | Pass | Pass | Same action and selection syntax. Remote-only checks reflect separate host filesystems and editor connection prefixes. |
| ADR 0003 | Pass | Pass | Read host and bare directory from the Session. Use lexical operations without filesystem handlers. |
| Repository workflow | Pass | Pass | Keep `main`, create only requested design artifacts, and do not commit. |

These results approve the design, not the unimplemented behavior. No unjustified violation or unresolved clarification remains.

## Project Structure

### Documentation (this feature)

```text
specs/009-fix-remote-references/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── current-file-reference.md
└── checklists/
    └── requirements.md
```

`tasks.md` belongs to `/speckit.tasks` and is not created by this command.

### Source Code (repository root)

```text
claude-code-ide.el                   # Planned formatter and current-file caller change
claude-code-ide-tests.el             # Planned command-level regression coverage
claude-code-ide-transient.el         # Existing @ binding, unchanged
claude-code-ide-remote-worktree.el    # Existing exact RPC parser, reused unchanged
claude-code-ide-zmx.el               # Existing destination validation, reused unchanged
README.org                          # Existing user guidance, update relevant text if needed
scripts/compile-and-test.sh          # Required implementation gate, unchanged
```

**Structure Decision**: Keep the logic in the existing formatter. Do not add a path module, Session field, destination registry, or second RPC parser.

## Phase 0: Research Results

See [research.md](research.md) for decisions, alternatives, source evidence, and executed probes.

Resolved questions:

- The transient `@` action invokes `claude-code-ide-send-current-file`, not the MCP at-mention command.
- Two direct callers share `claude-code-ide--file-reference-path`. Only current-file behavior changes under this specification. Superseded by spec 015, which extends the conversion to the pickers.
- The existing RPC parser preserves exact configured destinations, including destination text such as `user@v12mac`.
- Target identity comes from the live Session object, not manager remembered-target state or terminal `default-directory`.
- Relative conversion uses bare paths and does not require a remote filesystem operation.
- Existing command tests provide a seam for the exact sent reference and rejection-before-send behavior.

Executed probes established source host/path decomposition, relative path calculation, outside-directory results, and standalone loading of the existing parser. They do not establish implementation correctness.

## Phase 1: Design

### Formatter Interface

Extend the private helper to:

```elisp
(claude-code-ide--file-reference-path file &optional target-buffer remote-aware)
```

`remote-aware` is non-nil only from `claude-code-ide-send-current-file`. The omitted/default argument keeps the existing file-picker behavior. The local/local branch keeps the existing target-directory and project fallback logic.

For remote-aware calls:

1. Resolve the existing target buffer and Session object.
2. Detect remote source or target context before computing a relative path.
3. Load the existing RPC parser module optionally when remote conversion needs it.
4. Decode the source with the existing approved RPC parser.
5. Require a known remote Session with the same exact destination and a usable bare absolute directory.
6. Reject local/remote mismatches, unsupported routes, unknown targets, or invalid metadata with `user-error`.
7. Compute the normalized relative path with filesystem handlers disabled and `/` as the lexical default directory.
8. Return the relative path inside the directory, or the host-local absolute path outside it.

For step 8, `..` and `../` prefixes indicate an outside-directory result. A directory such as `v12x-other` must not count as inside `v12x`.

Add the required cross-file `declare-function` for the reused parser. Do not move or rename the exported parser. Do not hard-load optional remote support for local references.

The formatter returns a path or signals an error. It does not send, mutate Session values, or alter the source buffer.

### Caller and Delivery

Update the current-file caller to enable remote-aware conversion. Keep `claude-code-ide--get-file-reference-context`, selection range calculation, `#L` formatting, and `claude-code-ide--send-reference-body` unchanged.

A visible prompt buffer still receives references through the existing delivery preference. It cannot replace a missing remote Target Session identity.

The separate `#` action, file-picker actions, home-file action, and project-send action retain their existing contracts. There is no change to automatic target selection or Agent prompt submission.

### Data and User Interface

- [data-model.md](data-model.md) defines existing value ownership and validation.
- [contracts/current-file-reference.md](contracts/current-file-reference.md) defines reference bodies, errors, compatibility, and acceptance cases.
- [quickstart.md](quickstart.md) defines runnable path probes, test commands, and live verification steps.

### Verification Design

Add a command-level regression for the reported RPC file and selected line 316. Use the real RPC parser with configured test destinations and capture the public command’s terminal output.

Cover distinct failure risks: same-host outside-directory output, sibling-prefix containment, exact destination mismatch, local/remote mismatch, and missing target/directory. Assert no prompt insertion or terminal send on errors. Do not pin error wording.

Retain existing selection, local relative/absolute, and source-context tests. Add only missing compatibility coverage for the non-opted-in formatter caller. Keep test buffers and Session registries isolated and restore them on failure.

Run focused ERT coverage, then the complete implementation gate once changes are integrated. After success, reload changed Elisp with `emacsclient` and inspect the actual transient action using the quickstart guide.

Update relevant existing command docstrings and user guidance after implementation verification. Do not add a new README, changelog, or architecture document for this small fix.

## Complexity Tracking

No constitution violations require an exception. The optional private argument exists only to preserve the specification’s explicit distinction between current-file and file-picker behavior.
