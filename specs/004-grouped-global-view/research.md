# Research: Grouped Global View

**Date**: 2026-09-06
**Status**: Complete. No unresolved technical questions block design.
**Scope**: Read-only source research plus an isolated local Git experiment. No feature implementation or remote requests ran.

## R1. Repository identity is the canonical Git common directory

**Decision**: Identify a Git Project group by host plus canonical common-directory path, not worktree root, branch, label, or remote URL.
Local queries canonicalize on the local filesystem. Remote queries canonicalize on the remote host and return validated absolute strings.

Use `git rev-parse --git-common-dir`, resolving a relative result against the query directory on that same host.
A remote POSIX subshell can change to the common directory and use `pwd -P`.
This avoids requiring the newer `--path-format` option solely for absolute output.
Use `git symbolic-ref --quiet --short HEAD` for branch names. Exit 1 means detached HEAD and an empty branch label.
An unborn branch still has a symbolic branch name. Other branch-query failures are errors, not detached HEAD.

For display, use the parent of a canonical common directory named exactly `.git`. Otherwise use the common directory itself.
This names separate Git directories and bare repositories directly without another worktree-list parser.
Capture the current worktree root separately for directory-label fallback.
Do not change existing repo-local scope keys as part of global grouping.

**Rationale**: The current helper accepts the common directory only when its basename is `.git`.
That rule splits worktrees of bare repositories. Common-directory identity also handles separate Git directories without guessing from names.

**Alternatives considered**: `vc-git-root` per worktree splits linked worktrees. Remote URLs merge independent clones. Labels are not identities.

**Sources**:
- `claude-code-ide-manager.el:368–383,426–439`.
- [Git rev-parse documentation](https://git-scm.com/docs/git-rev-parse), `--git-common-dir`, `--path-format`, and `--show-toplevel`.
- [Git symbolic-ref documentation](https://git-scm.com/docs/git-symbolic-ref).

**Executed evidence**: Git 2.52.0, isolated temporary repositories on the planning workstation.

| Scenario | Observed result |
|---|---|
| Main and linked worktree | Same canonical common directory |
| Independent clone | Different canonical common directory |
| Linked worktree of a bare repository | Common directory equals the bare repository path |
| Symlink to the main worktree | Same canonical identity as the main worktree |
| Detached HEAD | `symbolic-ref --quiet --short HEAD` returned no branch and status 1 |
| Path containing quotes and shell punctuation | POSIX quoting preserved one inert NUL-delimited field |

The experiment removed its temporary repositories. It did not modify the project checkout.
The portable path-resolution method matched `--path-format=absolute` for the tested Git version.
Older Git versions and the final remote protocol still require implementation-time validation.

## R2. One ordered Session sequence serves every consumer

**Decision**: Extend the existing private ordering function with explicit scope/view context. Return Session items only, never heading items.
Preserve the flat comparator. In grouped global view, order host sections and groups first, then apply existing Session precedence within each group.
Use natural name order for headings, with group identity as the deterministic tie-breaker.
Reverse applies only to the configured Session fallback sort, as it does today.

The grouped name comparator uses the final grouped row label. Flat and repo-local label rules remain unchanged.
Resolve duplicate grouped labels within each group, with stable Session ID as the final collision suffix.
Do not overwrite persisted flat `display-name` with a grouped label.

Migrate these consumers together:

- `--render` and `--slot-map`.
- `--visible-session-keys`, ordinary row navigation, and priority navigation.
- Both `switch-by-slot` commands.
- `--neighbor-in-bucket`, `--materialize-order-keys`, and `--swap-order`.
- `edit-pin-order` and `--pin-order-resync`, including its ignore-pin-order path.

**Rationale**: Separate render-only grouping would make numeric shortcuts and navigation select different Sessions from the displayed rows.

**Alternatives considered**: A second grouped visible-key function duplicates ordering rules. Persisted group lists become stale after metadata updates.

**Sources**: `claude-code-ide-manager.el:1209–1277,1568–1572,1626–1636,1813–1836,1875–1918,2233–2265,2485–2496,2603–2661,3222–3245`.

## R3. Share pins and order without regrouping the flat list accidentally

**Decision**: Keep the existing scalar order keys and shared pin state. Do not create independent flat/grouped order stores.
A grouped move captures the current flat sequence and the displayed Session sequence within every group.
Swap the two eligible adjacent rows in the moved group's displayed sequence, then apply the same occupied-position merge used by grouped `E`.
Assign keys from that merged result without clearing pins. Keep the existing same-pin-bucket restriction and the flat-view swap unchanged.
Do not blindly swap keys materialized from flat order: flat directory labels and grouped branch labels can have opposite fallback order.

For grouped `E`, capture the flat sequence of snapshot Session IDs as well as the grouped editor snapshot.
At apply, replace each group's occupied positions in that flat sequence with the group's edited Session order.
Then assign order keys to that merged sequence and clear pins using the existing apply rule.
Sessions created after editor open retain fallback ordering and receive the existing pin-clearing behavior.
This changes the edited Sessions without placing all Sessions from one group together in flat view.
Materialization gives all affected snapshot rows explicit keys. Untouched groups retain their displayed order and occupied flat positions, not their earlier flat fallback order.

**Executed evidence**: A disposable Python model checked 360 adjacent moves across all flat-order permutations of two groups.
Every case preserved the requested move, the other group's displayed order, and each group's occupied flat positions.
This validates the planned merge algorithm, not the unimplemented Elisp integration.

**Rationale**: Assigning keys directly in grouped display order would silently reorder unrelated projects in flat view.
Pins remain shared, so pin changes naturally affect both presentations.

**Alternatives considered**: Per-view keys add another state model. Per-group integer keys collide when returning to flat view.

**Sources**: `claude-code-ide-manager.el:1768–1793,2233–2265` and `claude-code-ide-tests.el:14975–15098,15314–15372`.

## R4. Grouping metadata belongs on existing Session and manager items

**Decision**: Add one `group-metadata` plist slot to the existing Session and manager item structs.
Use the live Session as the source for connected metadata and the remembered manager item for disconnected metadata.
Copy the validated value through item rebuild, detach, serialization, and restoration.
Derived group keys, grouped labels, and headings are not persisted.

Store the view choice in the existing global scope state. Keep scope keys and layout keys unchanged.
Advance persisted schema version 3 to 4. Continue accepting versions 1–3 with flat view and absent metadata.
Reject invalid metadata separately from an otherwise valid remembered Session.
A missing or invalid cached value must not cause network work during restoration.

**Rationale**: `refresh-items` can load persisted state and rebuild every live item.
A render-only cache or unsaved callback update would disappear at the next refresh.

**Alternatives considered**: A separate durable cache duplicates lifecycle ownership. Recomputing remote metadata on redraw violates the accepted network boundary.

**Sources**: `claude-code-ide.el:409–411`; `claude-code-ide-manager.el:248–262,829–879,889–985,1096–1207,1515–1532`.

## R5. Remote metadata uses the existing asynchronous transport

**Decision**: Extract the generic owned SSH-process runner from `--call-remote` within `claude-code-ide-zmx.el`.
Retain `--call-remote` as the meaningful zmx adapter, with its host/name checks and current callers.
Add a read-only Git metadata adapter with directory validation and an explicit response parser.
Both adapters share the same process ownership, SSH options, deadline, and callback outcome.
No raw remote-command entry point becomes public.

Use finite directory batches for one chosen host. Deduplicate exact directory strings within each batch and the pending queue.
A replacement live owner may enqueue the same directory with a new snapshot after an earlier batch started or completed.
This is new target work, not a retry of a failed snapshot.
Each batch contains at most 32 directories and at most 16 KiB of encoded command text.
Run batches sequentially with one active metadata SSH process per host.
A single directory exceeding the encoded limit fails visibly without dispatch. Other valid targets remain eligible.
These are fixed transport limits, not new user settings.

A transient manager host-operation table owns the current process, queue, target snapshots, and operation token.
It is not persisted. An explicit duplicate refresh reports that the host already has a refresh in progress.
Post-attach requests can append newly attached targets to that host's finite queue without discovering additional targets.
Do not reuse the attach/Stop request name or block terminal interaction.

**Rationale**: Host batching avoids one SSH handshake per Session. Finite batches bound command size and timeout scope.
The two real adapters justify the shared transport seam. Existing zmx validation must remain separate from metadata validation.

**Alternatives considered**: A new SSH library is unnecessary. Unbounded shell arguments can fail at process creation. Concurrent requests per row waste connections.

**Sources**: `claude-code-ide-zmx.el:70–188`; [existing remote control contract](../003-attach-remote-agents/contracts/remote-sessions.md).

## R6. Metadata success does not define terminal success

**Decision**: Start optional metadata work after the existing remote creation path registers a live Session and installs its terminal cleanup hooks.
This is the current Emacs-side attachment milestone, not proof of a new zmx handshake protocol.
Do not add a terminal-output detector, zmx capability probe, or timer that declares remote readiness.
If the terminal later exits, existing disconnect handling remains authoritative.
The enqueue operation must be non-signaling. Put a local error handler around it at the end of `--create-remote-session`, after normal display/logging.
Report validation or SSH-start failure locally, then return the registered Session normally.
No metadata error may reach the creation cleanup handler or the bulk-attach loop, change attach counts, or prevent reattach selection.

Capture Session ID, host, exact directory, zmx name, and the live Session/process identity for each target.
For remembered targets, capture their identity tuple and require that no new live owner replaced them.
Late callbacks cannot create Sessions or restore deleted rows.
Apply a valid result only to still-current targets, save state before refresh, and retain the last good metadata on failure.

**Rationale**: Successful process creation does not guarantee the remote endpoint will remain attached.
Metadata must never become a prerequisite for terminal display or a reason to undo attachment.

**Alternatives considered**: Startup hooks create unauthorized network requests. Polling terminal output adds backend-specific readiness assumptions.

**Sources**: `claude-code-ide.el:1287–1330,2065–2154,2358–2391,2429–2461`; `claude-code-ide-manager.el:1187–1207,1515–1532`.

## R7. Unknown, non-Git, and failed metadata are different results

**Decision**: Use a fixed NUL-delimited protocol with indexed records and explicit `git`, `non-git`, and `error` kinds.
The [remote metadata contract](contracts/remote-metadata.md) defines framing, fields, and validation.
Do not evaluate remote text as Lisp or shell code. Force C-locale diagnostics for the package-owned Git probe.
A generic nonzero Git exit is not evidence of a non-Git directory.
Only a recognized not-a-repository diagnostic resolves to `non-git`. Permission, ownership, missing-Git, and protocol failures remain errors.

On error, retain a valid previous cache. Without one, use exact `(host, Session directory)` unresolved identity.
Do not strip trailing separators from unresolved directory identity. The user explicitly accepted exact comparison.

**Rationale**: A permission failure must not split a known repository into a false non-Git group.
NUL framing preserves spaces, quotes, tabs in diagnostics, and field boundaries without JSON tooling on the remote host.

**Alternatives considered**: Parsing arbitrary stdout lines is unsafe. Requiring remote Python or jq adds unnecessary dependencies.

**Sources**: `claude-code-ide-zmx.el:103–110,120–188`; specification FR-029 and FR-031–FR-034.

## R8. Grouped E snapshots identity and validates before mutation

**Decision**: Store editor view, fixed heading identities/text, snapshot Session IDs, group keys, labels, and baseline flat order in the editor buffer.
Make heading text read-only, but also validate it at apply because kill/yank or programmatic edits can bypass normal movement commands.
Allow blank lines as the existing editor does. Count Session rows, not headings.

In grouped view, check current scope membership rather than process liveness.
Before changing pins or order, reject missing/duplicate/foreign rows, renamed row text, changed headings, vanished Sessions, or changed group membership.
Do not resync a dirty editor automatically on metadata completion or a global view toggle.
Reopening or the existing explicit sort action creates a fresh snapshot.
The flat editor keeps its current behavior, including its known disconnected-row limitation.

**Rationale**: Metadata can change a group while the editor is open. Snapshot validation prevents an edit from crossing a new boundary silently.

**Alternatives considered**: Implicit resync loses user edits. Accepting stale grouping violates the fixed-group contract.

**Sources**: `claude-code-ide-manager.el:1609–1836`; `claude-code-ide-tests.el:14832–15632`.

## R9. Planning gates and verification scope

**Decision**: Keep all feature code in existing manager, Session orchestration, zmx, transient, and ERT files. Add no runtime dependency.
Support Emacs 28.1+ and preserve backend dispatch through the shared Session layer.
Performance validation measures cached ordering/render preparation with 1,000 Sessions across 100 groups.
Target less than 100 ms median over 20 runs on the development workstation, with zero external processes during cached preparation.
This is a proposed validation target, not an observed feature benchmark.
Local Git metadata queries deduplicate directories per refresh and never run once per Session row during render.

**Rationale**: This is a desktop sidebar, not a distributed service. Connection bounds and cached rendering matter more than server throughput or uptime targets.

**Alternatives considered**: New group registries, background polling, telemetry, and third-party UI libraries are not needed.

**Sources**: `.specify/memory/constitution.md`; `scripts/compile-and-test.sh:95–153`; [quickstart validation guide](quickstart.md).

The initial constitution gate passed before research. The final plan records the post-design gate separately.
