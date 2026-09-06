# Contract: Remote Grouping Metadata

**Status**: Implemented and verified on `ramhorn` and `vps`. See [acceptance results](../quickstart.md#8-implementation-validation-record).
**Scope**: Read-only Git metadata. No discovery, remote Session creation, reattach, or Stop.
**Existing transport**: [Remote Session Access](../../003-attach-remote-agents/contracts/remote-sessions.md).

## Triggers and target selection

Post-attach metadata runs after the existing creation path registers a live remote Session and installs its cleanup hooks.
It is optional work after that Emacs-side milestone, not a claim that SSH or zmx can no longer fail.
A later terminal exit still follows existing disconnect handling.
The post-attach enqueue operation must not signal into the creation or bulk-attach error handlers.
At the end of `--create-remote-session`, wrap enqueue in a local error handler after normal display/logging.
Report dispatch failure locally and return the registered Session normally, preserving terminal ownership, attach counts, and reattach selection.

The explicit command prompts for one currently configured host and snapshots its current global manager items.
Include connected Sessions and remembered disconnected Sessions. Exclude all other hosts.
Deduplicate exact directory strings for transport, but retain all Session IDs mapped to each directory.
Do not discover new targets, reinterpret directories locally, or reattach remembered Sessions.
If the chosen host has no known targets, report that result without starting SSH.

Normal `G`, refresh-all, render, startup, restore, navigation, and view toggles cannot enqueue metadata work.

## Transport seam

Within `claude-code-ide-zmx.el`, extract the current async SSH runner into a private shared function.
Its arguments are host, operation label, package-built remote command, callback, and optional request name.
Keep host validation inside the shared runner so neither adapter can bypass it.

`claude-code-ide-zmx--call-remote` remains the zmx adapter.
It retains zmx argument/name validation and builds the existing guarded zmx command before calling the shared runner.
The new metadata adapter validates directory arguments, builds a fixed package-owned POSIX probe, and parses its response.
Do not expose arbitrary remote shell execution as a public command.

Preserve these transport rules:

- Use `ssh -T -n` for control requests.
- Preserve batch authentication, strict host-key checking, connect timeout, single connection attempt, and `RemoteCommand=none`.
- Require current membership in `claude-code-ide-remote-hosts` immediately before each batch dispatch.
- Use a thirty-second total deadline per batch. Timeout cancels only that owned SSH process.
- Never retry a failed target snapshot in the same operation.
- Keep stdout and stderr separate and deliver the existing callback outcome once.
- Report errors through the requesting context, not an asynchronous error in another editor command.

Do not change zmx attach arguments, the `false` guard, attach/Stop request names, or verified Stop ordering.

Exact private signatures:

```text
claude-code-ide-zmx--run-remote-command
    (host operation command callback &optional name coding output-limit) -> process
claude-code-ide-zmx--call-remote (host args callback &optional name) -> process
claude-code-ide-zmx--query-remote-metadata
    (host directories callback &optional name) -> process
```

`--run-remote-command` is the shared runner. CALLBACK receives one outcome
plist: `:host :operation :process :status :stdout :stderr :cancelled :timeout
:overflow`. `:overflow` is non-nil only when OUTPUT-LIMIT truncated stdout.
`--call-remote` calls it with OPERATION bound to `(car args)`, matching prior
behavior exactly. `--query-remote-metadata` calls it with OPERATION
`"git-metadata"`, CODING `no-conversion`, and OUTPUT-LIMIT
`claude-code-ide-zmx--metadata-max-stdout-bytes`, then adds `:records` (on
success) or `:error` (a string, on failure) to that same outcome plist.

## Batch bounds

Use at most 32 unique directories and 16 KiB of encoded command text per batch.
Run one metadata SSH process at a time per host. The manager owns a finite pending queue and an operation token.
An oversized single directory reports a target error without dispatch. Continue with other valid targets.
Bound accepted stdout to 1 MiB per batch. Excess output fails the batch and preserves cached metadata.

`claude-code-ide-zmx--metadata-max-directories` (32) and
`claude-code-ide-zmx--metadata-max-command-bytes` (16384) hold these two
limits, and `claude-code-ide-zmx--metadata-max-stdout-bytes` (1048576) holds
the stdout bound above. `claude-code-ide-zmx--metadata-command (directories)`
builds the exact `sh -c` command text described under Request construction.
`claude-code-ide-zmx--metadata-command-size (directories)` returns
`(string-bytes (claude-code-ide-zmx--metadata-command directories))`, the
exact byte size `--query-remote-metadata` checks before dispatch.

The manager reports and excludes invalid or individually oversized targets before it forms transport batches.
Valid siblings remain eligible for later dispatch.
The private adapter receives one bounded batch and rejects invalid input before SSH starts.
It does not filter or reindex that batch. Only the remote probe produces per-directory wire error records.

An explicit refresh during an active operation reports that the host already has a refresh in progress.
Post-attach triggers can add newly attached targets to the same host's pending queue.
They cannot turn a metadata operation into discovery or retry directories that already failed for the same target snapshot.
A replacement live owner can enqueue the same directory with a new snapshot after its previous batch started or completed.
Deduplicate pending work by directory while preserving target snapshots. Do not discard new-owner work because an old owner used that directory.
After completion or cancellation, remove the host-operation entry and owned temporary buffers/timers.

## Request construction

Require each directory to be an absolute POSIX path without control characters.
Use the existing POSIX single-quote helper for every directory argument. Do not use interpolation, eval, or local filesystem normalization.
The remote command consists only of package-owned script text and individually quoted data arguments.
No remote script file, Python, jq, daemon, or patched zmx is required.

The fixed probe uses a subshell per directory, C-locale Git diagnostics, and a fixed record format.
Clear repository-location overrides such as `GIT_DIR`, `GIT_WORK_TREE`, and `GIT_COMMON_DIR` for the probe.
This prevents the remote environment from overriding the requested Session directory.
Clear `CDPATH` before any directory change. Resolve relative common-directory output only against the requested working directory.
Run the fixed probe body under `sh -c`, while retaining the existing remote-command quoting rules.
A login shell that cannot parse the package's quoted command fails closed rather than weakening quoting.
Do not modify the environment of the attached Agent or SSH configuration.

## Git query semantics

1. Change to the requested directory on the remote host. Failure produces `error`, never `non-git`.
2. Query `git rev-parse --git-common-dir` and retain its exit status.
3. Resolve a successful common-directory result on that host using a subshell and `pwd -P`.
4. Derive the project display path from that canonical common directory: parent directory for a literal `.git` basename, otherwise the common directory.
5. Query the current worktree root with `git rev-parse --show-toplevel`. A bare repository has no worktree root.
6. Query the branch with `git symbolic-ref --quiet --short HEAD`. Status 1 means detached HEAD and an empty branch.

A bare repository must first be positively identified through `git rev-parse --is-bare-repository` before accepting a missing worktree root.
An unborn symbolic branch is a valid branch name.
Other failed queries produce `error` and do not replace a prior good cache with partial Git metadata.

Classify `non-git` only for a recognized C-locale not-a-repository diagnostic from the initial Git query.
Allow the standard parent-directory and filesystem-boundary variants, with their expected diagnostic structure.
Do not classify arbitrary exit 128, unsafe ownership, inaccessible directories, or missing Git as `non-git`.
Unknown diagnostic formats fail closed as `error`.
The implementation must include real local Git cases for ordinary non-Git paths, permission failure, and malformed repositories.

## Response grammar

Use NUL-delimited UTF-8 fields with a final NUL. The fixed version header rejects login banners and unexpected output.

```text
cci-git-metadata-v1 NUL COUNT NUL
INDEX NUL KIND NUL COMMON-DIR NUL PROJECT-PATH NUL WORKTREE-PATH NUL BRANCH NUL DIAGNOSTIC NUL
... exactly COUNT records ...
```

`COUNT` equals the number of directories in the captured batch.
`INDEX` is the decimal zero-based index of that input directory, not a path supplied by the server.
Each index appears once, in ascending input order. No extra fields, records, or nonempty trailing output are allowed.

| KIND | Required fields | Empty fields |
|---|---|---|
| `git` | Canonical absolute COMMON-DIR and PROJECT-PATH. WORKTREE-PATH unless positively bare | DIAGNOSTIC. BRANCH may be empty |
| `non-git` | PROJECT-PATH equals the exact requested directory | COMMON-DIR, WORKTREE-PATH, BRANCH, DIAGNOSTIC |
| `error` | A bounded human-readable DIAGNOSTIC | COMMON-DIR, PROJECT-PATH, WORKTREE-PATH, BRANCH |

Validate UTF-8 decoding, field count, version, record count, indices, kind, and all field combinations before applying any record.

`claude-code-ide-zmx--parse-metadata (host directories stdout)` performs this
validation and returns one plist per directory, in DIRECTORIES' order:
`(:kind git :host H :directory D :common-dir C :project-path P :worktree-path
W-or-nil :branch B-or-nil)`, `(:kind non-git :host H :directory D
:project-path D)`, or `(:kind error :host H :directory D :diagnostic
STRING)`. It signals a `user-error` for any violation described above, so a
caller never receives a partial result for a malformed response.
Reject path and branch control characters and non-absolute paths.
Display diagnostics as inert text. Never evaluate them, pass them back to a shell, or add text properties from them.
A valid response may contain individual `error` records. Those targets retain cached data while successful records remain eligible.
Malformed framing, excess output, or nonzero SSH command exit rejects the complete batch.

This wire format is internal to the package-owned probe, not an extension API.

## Callback ownership and persistence

The manager callback receives the transport outcome and captured target snapshots.
It accepts data only while its host-operation token is current.
Revalidate host membership before publishing and before starting another batch.

For each Session target:

- Require the current Session or remembered item still exists with the captured host, exact directory, and zmx name.
- For a captured live target, require the same live Session object and terminal process.
- For a captured remembered target, require no new live Session replaced it.
- Do not update a target while an explicit Stop owns it.
- Never create a missing Session or manager item from a metadata callback.

If a newer attachment replaces the owner, discard the old result.
Post-attach metadata for the new owner supplies its own snapshot and request.
Detach preserves the last accepted cache through existing remembered-item handling.

Apply valid metadata to current live records and current manager items.
Save state before any refresh path can reload persisted values.
Update grouped labels and membership without changing Session IDs, active/selected IDs, layouts, or Agent-state acknowledgment.
An open grouped `E` editor retains its snapshot and later rejects changed membership.

## Failure and cancellation

A metadata failure never fails or undoes terminal attachment.
Retain last valid cached metadata. If no cache exists, retain the unresolved group defined by the exact host and directory.
Host removal prevents new requests and result publication. It does not delete remembered Sessions.
Cancellation invalidates the operation token, clears its pending queue, and cancels only its owned control process.
Timeout or a per-directory error is reported with the host and affected target context.
No failure triggers discovery, automatic reconnect, or local interpretation of a remote path.
