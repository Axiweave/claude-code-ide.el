# Implementation Plan: Grouped Global View

**Git branch**: `main` | **Date**: 2026-09-06 | **Spec**: [spec.md](spec.md)
**Feature ID**: `004-grouped-global-view`
**Input**: `specs/004-grouped-global-view/spec.md`
**Status**: Phase 1 design complete. Independent reviewer approved progression to `/speckit.tasks` on 2026-09-06.

The setup script reports the active feature ID as `BRANCH`. The actual Git checkout remains on `main`, as repository rules require.
This plan does not create a branch, worktree, implementation, or commit.

## Summary

Add a persistent flat/grouped presentation switch to the existing global manager scope.
Keep one row per Session and derive groups from canonical Git common-directory identity plus host.
Use one scope/view-aware ordering path for rendering, quick slots, navigation, movement, and the order editor.
Keep local and remote repository metadata on existing Session and manager item records.
Obtain remote metadata only after explicit attachment or through one prompted host-refresh action.

The existing manager, zmx control runner, and Session lifecycle provide the required seams.
No new runtime dependency, Session scope, terminal backend, or project-wide action is needed.

## Technical Context

**Language/Version**: Emacs Lisp with lexical binding. Preserve Emacs 28.1+ compatibility.

**Primary Dependencies**: Existing `cl-lib`, `subr-x`, project/VC helpers, `persist`, `transient`, and `avy`.
Git supplies repository identity and branch data. Existing SSH and stock zmx support remote attachment.
The metadata probe uses only the remote POSIX shell, Git, and POSIX utilities.
No remote Python, jq, service, or patched zmx is required.

**Storage**: Existing persisted manager state. Add global `:view` and validated `group-metadata` values. Migrate schema 3 to 4 without changing identities.

**Testing**: Existing ERT file and dependency mocks, isolated Git fixtures, bounded SSH-control simulations, and live manager validation through Emacs.
Run `./scripts/compile-and-test.sh` after implementation. Reload changed Elisp through `emacsclient` after verification.

**Target Platform**: Desktop Emacs on supported platforms, with the development proof on macOS.
Grouped local manager behavior remains backend-neutral for vterm, eat, and ghostel.
Existing remote attachment remains ghostel-only with its explicit unsupported-backend error. This feature does not expand remote backend support.

**Project Type**: Emacs package with interactive manager commands and an internal remote metadata protocol.

**Performance Goals**: Cached ordering/render preparation for 1,000 Sessions across 100 groups should take less than 100 ms median over 20 runs.
Measure on the development workstation after implementation. Cached preparation starts zero external processes.
Deduplicate local Git metadata by directory per refresh. Remote operations use one active metadata SSH process per host.

**Constraints**: No SSH from startup, restoration, ordinary `G`, redraw, view toggle, navigation, or repo-local sidebar operations.
Preserve existing strict SSH options, thirty-second control deadlines, and no-retry behavior.
Keep Agent processes, state acknowledgment, Session IDs, and saved layouts independent of metadata success.
Remote metadata remains opaque to local filesystem and TRAMP handlers.

**Scale/Scope**: A single user's manager Sessions across local repositories and explicitly configured hosts.
Validate 1,000 cached rows, more than ten selectable rows, and multiple Sessions per Worktree.
Metadata batches contain at most 32 unique directories and 16 KiB of encoded command text, with at most 1 MiB of stdout each.
These bounds protect transport operations. They are not a new configurable scaling framework.

## Constitution Check

The initial gate passed before Phase 0 research. The post-design gate uses the completed contracts and data model.
A PASS here means the design satisfies the rule. It does not claim implementation tests have run.

| Principle | Initial gate | Post-design gate | Evidence |
|---|---|---|---|
| I. Shared Session core, thin adapters | PASS | PASS | Manager owns grouping. Session orchestration supplies the post-attach trigger. Agent command builders stay unchanged |
| II. Batch-verifiable quality | PASS | PASS | ERT behavior boundaries and the full byte-compile/test command appear in quickstart. Live UI checks supplement the suite |
| III. Optional dependencies | PASS | PASS | No new runtime package. Missing Git/SSH metadata produces a clear result without breaking attachment |
| IV. Terminal-backend neutrality | PASS | PASS | Existing manager/Session interfaces handle UI behavior. Existing remote backend limitation remains explicit |
| V. Simplicity and compatibility | PASS | PASS | Emacs 28.1+, existing state stores, one ordering path, two real adapters sharing one SSH runner |
| Branch, commit, and file ownership | PASS | PASS | Work remains on `main`. No commit or source implementation occurs in this workflow |

No gate exception or new dependency needs a Complexity Tracking justification.

## Project Structure

### Documentation for this feature

```text
specs/004-grouped-global-view/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    ├── manager-view.md
    └── remote-metadata.md
```

`tasks.md` belongs to the later `/speckit.tasks` workflow and is not created by this plan.

### Source files to change during implementation

| File | Responsibility |
|---|---|
| `claude-code-ide-manager.el` | Metadata-derived groups, view state, ordering, rendering, slots, navigation, grouped E, remote metadata orchestration |
| `claude-code-ide.el` | Session metadata slot, preservation during reattach, post-registration optional metadata trigger |
| `claude-code-ide-zmx.el` | Shared owned SSH transport, validated Git metadata adapter and parser |
| `claude-code-ide-transient.el` | New view, group-navigation, and explicit metadata-refresh menu entries |
| `claude-code-ide-tests.el` | Observable grouping, migration, ordering, editor, metadata, and race regressions |
| `README.org` | User commands, view behavior, compatibility, and remote metadata trigger rules |
| `TODOs.org` | Link this feature and record completion only after acceptance |
| Feature 003 remote contracts | Describe the read-only metadata extension and grouped host presentation without weakening attach/Stop contracts |

**Structure Decision**: Extend existing files. Do not add a group service, generic job framework, or replacement manager module.
The single transient host-operation table owns real overlapping metadata triggers and is never persisted.

## Phase 0 Research Results

[research.md](research.md) resolves the technical questions and records sources, alternatives, and the executed Git experiment.

1. Canonical common-directory identity handles linked worktrees, independent clones, symlinks, and bare-repository worktrees.
2. Shared scope/view-aware ordering keeps every row consumer consistent.
3. Shared scalar order keys can preserve flat interleaving when grouped edits change only a group's occupied positions.
4. Existing Session and manager item records carry metadata through refresh, disconnect, and persistence.
5. The existing SSH runner can support zmx and Git adapters without relaxing zmx argument validation.
6. Metadata follows the existing Emacs-side attach milestone and never defines terminal success.
7. Explicit protocol result kinds separate non-Git directories from failed queries.
8. Grouped editor snapshots detect stale grouping before any order or pin mutation.

No technical question remains marked for clarification.

## Phase 1 Design

### Metadata and view-state migration

Implement the [data model](data-model.md) on existing structs and global scope state.
Update both serialization directions, state reset values, and the version whitelist together.
Keep versions 1–3 readable. Invalid new metadata must not remove an otherwise valid remembered Session.
Carry existing cached metadata through `--materialize-remote-target`, `--create-remote-session`, `--make-item`, and `--remember-remote-session`.
The pre-attach remembered row must not erase its previous metadata before a new Session exists.

Compute local metadata once per unique Session directory during refresh, not during row rendering.
Keep Git identity separate from existing repo-local root helpers to avoid changing repo-local scope semantics.
A local query error preserves a prior matching cache or produces an unresolved group. Never silently treat permission failure as non-Git.
Use the same local classification rules as the remote probe: C locale, separate stderr, retained exit status, and cleared repository-location overrides.
Read global-row help text from cached branch metadata instead of invoking `--session-branch-name` during `--insert-item`.
This includes help-echo work in the zero-process cached-render target.

### One ordering and presentation path

Extend `--sorted-items` to take explicit scope and view context, including the editor's captured view and ignore-pin-order flag.
Migrate every production caller named in research R2 rather than adding a parallel grouped-only ordering implementation.
Derive grouped labels without overwriting flat labels or Session custom names.
Build one ordered Session projection per render/command and pass it to slot and heading rendering where possible.
Do not sort separately for each row, slot, or heading.

Preserve the existing pin and manual-key comparator.
Use a same-group guard beside the existing same-pin-bucket guard for sidebar moves.
For grouped sidebar moves, swap rows in the displayed group sequence before assigning any manual keys.
Merge all displayed group sequences into their occupied positions in the flat baseline, then assign keys without clearing pins.
Grouped `E` uses the same merge with its edited sequences and existing pin-clearing rule.
This preserves displayed order and occupied flat positions when flat and grouped fallback labels disagree.
Materialization may change an untouched group's internal flat fallback order to its displayed grouped order.
Keep flat-view swaps unchanged. Do not blindly swap keys assigned from the flat fallback sequence.

### Rendering, commands, and selection

Implement the public commands and bindings in [manager-view.md](contracts/manager-view.md).
Insert headings only at group/host transitions in the ordered Session sequence.
Do not attach Session identity properties or Avy targets to headings.
Retain the existing row status indicators, active marker, disconnected text, and Session action behavior.

The toggle saves view state before any reload-capable refresh.
Restore point by selected Session ID without displaying another Session or acknowledging a result.
Group navigation resolves point, then stored selection, then active Session, and uses the existing switch path only for actual Session selection.
A disconnected target keeps the active terminal unchanged and becomes the origin for the next group jump.

### Grouped E

Capture view, group identities, fixed headings, row labels, Session IDs, and baseline flat order when the editor opens.
Update row movement, renumbering, kill/yank validation, row counting, and sort resync to distinguish Session rows from headings.
Validate current group membership and all snapshot rows before mutating pins or order.
Use current scope-item presence for grouped disconnected rows while preserving flat editor behavior.
Do not auto-resync a dirty editor on metadata completion or a sidebar view toggle.

### Remote request orchestration

Implement the [remote metadata contract](contracts/remote-metadata.md) without modifying Agent execution or zmx attach/Stop arguments.
The manager snapshots only known targets on one prompted host for explicit refresh.
The post-attach trigger queues only the newly registered target and never requests discovery.
Make this enqueue operation non-signaling with its own local error handler at the end of `--create-remote-session`, after normal display/logging.
Host validation and SSH-start failures must report locally and still return the registered Session.
They must not reach the creation cleanup handler, change bulk-attach counts, or prevent reattach from selecting its returned Session.
Build bounded directory batches and serialize them through one transient host operation.
Capture live owner/process identity or remembered identity per target and reject stale callbacks.

Save accepted cache updates before refresh. Do not recreate removed Sessions or let an old callback update a replacement terminal.
Check Stop ownership before accepting a target result. Keep metadata request ownership separate from attach and Stop ownership.
Errors preserve the previous cache and the attached terminal. Missing caches retain exact-directory unresolved grouping.

### Lifecycle and concurrency cases

| Case | Required design result |
|---|---|
| Two Sessions share one directory | One directory probe per batch, separate Session rows and ownership checks |
| Reattach preserves Session ID | Old metadata result cannot update the new live process |
| Detach during metadata request | Existing detach copies the last accepted cache. Old live-target result is ignored |
| Verified Stop during request | Missing target remains missing. No remembered row resurrection |
| Host removed during request | No further dispatch or result publication |
| Explicit refresh while host operation exists | Report in-progress operation, do not start a duplicate |
| New attach during host operation | Queue the new captured target without discovery or blocking terminal display |
| Metadata changes group while E is open | Sidebar regroups. Apply rejects stale editor membership without pin/order mutation |
| Sidebar view changes while E is open | Editor retains its captured view and snapshot |
| New Sessions appear after E opens | Existing fallback behavior and scope-wide pin clearing remain intact |

## Validation Strategy

Use [quickstart.md](quickstart.md) for commands and observable acceptance results.
Permanent regressions must defend plausible bugs: identity boundaries, slot/order disagreement, stale editor mutations, unsafe remote input, or stale callback ownership.
Do not add tests that only check command forwarding, copied fields, source text, or incidental wording.
Adapt existing behavior tests where the shared ordering interface changes.
Reset the transient host-operation table and cancel its owned test processes in the existing test reset helper.

The final implementation gate is byte compilation plus the full existing ERT suite.
Then use `emacsclient` to reload changed Elisp and verify the real manager surface, including Spacemacs/Evil bindings.
Validate local manager behavior for supported backends and the existing explicit remote-backend limitation.
Use only user-approved remote Sessions for live checks. Do not send Agent input, Stop, or create remote Sessions as part of this feature's validation.

The planning Git experiment already passed the identity and shell-quoting checks recorded in research R1.
The feature commands, protocol parser, migration, and UI remain unimplemented and untested at this planning stage.

## Complexity Tracking

No constitution violations. No new runtime dependency.
The shared SSH runner serves two concrete adapters. The transient host-operation table owns bounded concurrent metadata work, not a speculative extension framework.

## Review

The independent reviewer approved this plan in the second review. No blocking findings or required user decisions remain.

The first review produced three corrections:

- Grouped sidebar moves now use the occupied-position merge, including cases where flat and grouped fallback labels disagree.
- Post-attach metadata enqueue has a local non-signaling error handler, preserving the registered Session and bulk-attach counts.
- Terminal validation uses the dependency-aware verification script. Optional interactive ERT uses a quoted Lisp selector and checks for a nonzero test count.

The final cautions are also covered: the interactive selector uses Lisp string syntax, and implementation documentation must explain separate-Git-directory heading names.
The Git identity experiment and 360-case merge model passed during planning. Feature implementation and its ERT/UI acceptance remain future work.
