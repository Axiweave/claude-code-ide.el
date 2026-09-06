# Data Model: Attach Remote Agents

**Specification**: [spec.md](spec.md)
**Decisions**: [research.md](research.md)

## Identity Rules

- A Session ID identifies one Emacs-side Session and its remembered manager row. It remains stable through disconnect, restart, and reattach.
- A remote target is the pair `(host, zmx-name)`. Different hosts may use the same zmx name.
- A remote project is the pair `(host, directory)`. The directory is remote metadata, not a local filesystem instruction.
- Local project keys keep their existing normalized directory strings. Remote project keys use a host-directory pair without changing local key formats.
- SSH aliases remain distinct configured hosts, even if they reach the same machine.
- Target lookup checks live Sessions and remembered remote items. It never deduplicates by project basename or zmx name alone.

## Configured Host

**Representation**: One string in the proposed `claude-code-ide-remote-hosts` customization.

| Field | Meaning | Validation |
|-------|---------|------------|
| Destination | Exact SSH destination and manager host label | Nonempty, no control characters or whitespace, no leading option marker |

The list defaults to empty. The user owns its contents. A new remote operation requires exact membership in the current list.

SSH configuration still supplies connection details such as keys, ports, and jump hosts. The package does not scan that configuration for destinations.

Removing a destination does not remove remembered rows. It blocks new discovery, attach, reattach, and Stop requests. Existing terminal connections need not terminate.

## Live Session

**Representation**: Existing `claude-code-ide-session` record, with one new `host` slot.

| Field | Remote meaning | Persistence |
|-------|----------------|-------------|
| `id` | Stable Emacs Session ID | Copied to manager `session-key` |
| `host` | Configured SSH destination | Copied to manager `host` |
| `zmx-name` | Exact full remote zmx session name | Copied to manager `zmx-name` |
| `directory` | Absolute remote project directory | Existing manager directory field |
| `cli-type` | Agent identity for terminal behavior | Copied to manager `cli-type` |
| `buffer` | Current local terminal buffer | Never serialize |
| `process` | Current local SSH attach client | Never serialize |
| `pid` | Always nil for remote Agent PID lookup | Never query the local process table for a remote Agent |
| Existing presentation fields | Order, names, title, creation and access times | Existing manager persistence rules |

`host=nil` retains the existing local semantics. A non-nil host requires a nonempty zmx name and forbids remote creation, continue, and resume.

The live registry still contains only live Session records. Disconnect removes its record after the manager receives the remembered target metadata.

The terminal's `default-directory` is a valid local directory, such as `temporary-file-directory`. It must not use the remote metadata directory.

## Remembered Manager Item

**Representation**: Existing `claude-code-ide-manager-item`, with three new slots.

| Field | Meaning | Rule |
|-------|---------|------|
| `session-key` | Stable Session ID | Reattach reuses it |
| `host` | Remote destination, or nil for local items | New persisted slot |
| `zmx-name` | Exact remote target name | New persisted slot |
| `cli-type` | Previously identified Agent type | New persisted slot |
| `directory` | Remote project metadata when host is non-nil | No local existence check |
| `live-p` | Current live-record observation | Remote restoration always resets it to nil |
| `custom-name`, `display-name`, `secondary-text` | Existing local presentation | Host remains visible despite renaming |
| `order`, `created-at`, `pinned`, `order-key` | Existing ordering and pin state | Preserve across disconnect and reattach |

Do not add `connected-p`. It would duplicate `live-p` and risk restoring a stale connection claim.

Remote metadata must be sufficient to reattach without a surviving terminal buffer or live registry record. The manager must materialize the item when the user selects an attach target.

If the first attachment fails, retain the selected target as a disconnected item. The user can retry explicitly without repeating Agent identification.

### Scope Membership

Remote items belong to the existing global manager scope. They do not belong to local Git repository scopes merely because their directory strings match.

The manager can sort and label remote items using host and stored directory text. It must not run Git, Magit, Dired, TRAMP, or Treemacs queries for them.

### Persistence Version

Advance manager state from version 2 to version 3. Keep the current version 1 and version 2 readers.

- Old items have `host=nil`. Preserve their existing local migration and visibility behavior.
- New remote items require valid host, zmx name, Agent type, and directory metadata.
- Invalid saved remote entries produce an actionable diagnostic and do not authorize remote commands.
- Restore valid remote items with `live-p=nil`, regardless of the saved value.
- Preserve selected-row identity when possible. Clear an active-terminal reference that has no current live record.
- Preserve stored layout choices, but never restore a dead terminal as a connected target.
- During refresh, a current live record overrides the saved disconnected snapshot for the same Session ID.
- With persistence disabled, in-memory disconnected rows remain available for the current Emacs lifetime. A later Emacs does not load them.

## Connection State

Connection state describes the local attach client. It does not establish whether the remote Agent is alive or has completed a turn.

| State | Representation | Display |
|-------|----------------|---------|
| Disconnected | Remembered remote item without a current live attach record | Explicit disconnected status |
| Attach pending | An explicit request owns a temporary local process handle | Progress message, with no output-idle claim |
| Connected | Current Session owns a live attach process and terminal buffer | Existing output activity and idle status |
| Stop pending | A confirmed request owns its control process | Stopping message, without premature success |

Pending request handles are transient. Do not serialize them or create another session-history store.

### State Transitions

| Event | Before | After | Required action |
|-------|--------|-------|-----------------|
| User selects discovered target | No item or disconnected | Attach pending | Reuse target identity or allocate one Session ID |
| Attach succeeds | Attach pending | Connected | Register under the same ID and expose terminal |
| Attach fails or target disappears | Attach pending | Disconnected | Report failure and retain item without creating a remote target |
| SSH client ends | Connected | Disconnected | Clear timers and activity, retain metadata, release local client resources |
| User closes terminal buffer | Connected | Disconnected | Detach only that client |
| Manager refresh or ordinary selection | Disconnected | Disconnected | Preserve row and perform no remote operation |
| Explicit reattach | Disconnected | Attach pending | Check current host configuration, then attach with the exit guard |
| Duplicate attach request | Attach pending or connected | Unchanged | Reuse the current request or Session |
| Editor restarts with persistence | Any remembered remote item | Disconnected | Restore metadata without contacting the host |
| User cancels Stop confirmation | Any | Unchanged | Send no stop request |
| Stop succeeds and absence check passes | Stop pending | Removed | Invalidate the live owner, release its client, then remove rows and layouts |
| Stop result remains unconfirmed | Stop pending | Connected or disconnected | Preserve row and follow actual client state |
| Host leaves configuration | Any remembered item | Same connection state | Reject new remote requests until configuration returns |

Confirmed Stop removes the remembered target. Unavailable or missing targets remain remembered after failed reattach. There is no automatic row garbage collection.

## Process Ownership and Races

A lifecycle callback carries the process and buffer that produced it. Before cleanup, compare that process with the current Session's process.

If the live record is absent or a later attachment owns the Session ID, ignore the old callback. The old buffer's kill hook must use the same ownership check.

For an owned disconnect:

1. Copy current remote metadata and presentation into its manager item.
2. Mark the item disconnected and clear its active-terminal reference.
3. Remove the live registry record as the recursion guard.
4. Disable idle timers and clear activity in the old buffer.
5. Release only the old client's local resources.
6. Save manager state before any refresh that reloads persistence.

Reuse process-object identity instead of a global generation counter. Ensure each request completes its callback once, including cancellation and deadline expiration.

### Verified Stop Ordering

Only the current Stop request can finalize its captured Session ID and target. Reject reattach while that target has a pending Stop request.

For verified Stop success:

1. Check that the request still owns the target and has not completed.
2. Remove the captured live Session record before releasing its process or buffer.
3. Release the captured client resources with a verified-stop disposition that never remembers a disconnected item.
4. Remove the target's manager items, layouts, and selected or active references.
5. Save manager state before refresh can reload it.
6. Complete the request once and release its pending-operation ownership.

If the attach sentinel runs first, it may preserve a disconnected item until Stop verification finishes. Verified completion then removes that item.

If verified completion runs first, later sentinels find no matching live owner and do nothing. They must not recreate rows from captured metadata.

An unconfirmed Stop does not run verified-stop cleanup. The current attach-client state continues to determine whether its retained row is connected or disconnected.

Regression coverage must exercise both callback orders, refresh after each order, and a late callback against a newer attachment.

## Validation Rules

- Reject session names that are empty, contain control characters or path separators, begin with `-`, equal `.`, or end with `*`.
- Quote valid names containing spaces, quotes, or shell punctuation at both shell interfaces where needed.
- Accept absolute remote directories as text. Manual metadata entry uses a text prompt, not local directory completion.
- A changed or unavailable Agent configuration requires existing manual identification behavior. Do not launch or probe a local Agent executable.
- Reject malformed remote listing output instead of silently treating it as a successful empty list.
- No disconnected item can supply a local Agent PID or receive a local MCP Agent-state association.
