# Research: Fix Remote Session Toggle

## Decision 1: Resolve an owned Session before directory lookup

**Decision**: `claude-code-ide-toggle` first resolves the Session owned by the invoking terminal buffer. It uses that Session's buffer and directory directly.

**Rationale**: The current command computes a directory first and then calls `claude-code-ide--get-session-buffer` with a non-nil directory. That skips the helper's current-buffer ownership branch. Directory-only lookup also omits the Session host. `claude-code-ide-stop` already uses the correct exact-Session-first pattern.

**Alternatives considered**:

- Add remote logic to `claude-code-ide--get-session-buffer`. Rejected because this changes unrelated callers and still makes the command discard exact Session identity.
- Add a remote-only toggle command. Rejected because local and remote workflows must use the same command.
- Prompt for a host or Session. Rejected because the invoking terminal already supplies exact identity.

## Decision 2: Use the managed layout for project-view ownership

**Decision**: Resolve terminal ownership in the core command first. Only if that fails, call one private manager accessor that accepts the active Session when its saved project-view buffer exactly equals the input buffer.

**Rationale**: A remote project view is not the Session terminal, but the manager layout records which Session owns that view. Exact buffer equality prevents an unrelated RPC buffer from inheriting the current manager Session. The manager owns this state, so the resolver belongs at that seam.

**Alternatives considered**:

- Use host and directory recency for a managed view. Rejected because sibling Sessions can share the same host and directory. This lookup remains valid only for an ordinary remote project buffer without exact ownership.
- Scan private remote-project intents from the core command. Rejected because views can be shared and the manager already owns active layout selection.
- Use the global current Session without checking the saved view buffer. Rejected because an unrelated buffer could toggle the wrong Session.

## Decision 3: Resolve ordinary remote project buffers by host and path

**Decision**: After exact terminal and managed-view ownership fail, use `file-remote-p` to extract the remote host and local path. Select the preferred live Session for that exact host-qualified project key.

**Rationale**: A Magit buffer can remain useful after its terminal hides without being the manager's active saved view. Host-qualified lookup restores that Session without selecting a same-path local Session or another host.

**Alternatives considered**:

- Scan manager layouts or remote-project internals. Rejected because the managed-view accessor has a constant-size ownership contract.
- Parse `/rpc:` text manually. Rejected because `file-remote-p` already exposes the host and local path.


## Decision 4: Preserve the existing local fallback

**Decision**: If no terminal, managed view, or remote host-path lookup identifies a Session, retain the current local attached-project and working-directory lookup unchanged.

**Rationale**: Local project buffers depend on directory fallback. The fix must not change their prompts, errors, or preferred sibling behavior.

**Alternatives considered**:

- Make all toggle calls require exact Session context. Rejected because this removes the established local project-buffer workflow.
- Pass a host into every directory lookup. Rejected because local fallback has no remote host and must stay local.

## Decision 5: Keep disconnected targets outside toggle resolution

**Decision**: The context resolver returns only live Sessions with live terminal buffers. Remembered disconnected targets continue to require explicit reattach.

**Rationale**: Toggle changes visibility. It must not perform discovery, attachment, network access, or lifecycle changes.

**Alternatives considered**:

- Reattach when a remembered target is selected. Rejected because this creates a network side effect from a visibility command.
- Toggle a manager row without a terminal. Rejected because no Session window exists to hide or restore.

## Decision 6: Test the public command at the resolution seam

**Decision**: Add focused ERT tests that register colliding local and remote Sessions, invoke `claude-code-ide-toggle`, and capture the buffer passed to the existing window-toggle helper.

**Rationale**: These tests observe the public command's target choice without depending on window geometry. They fail on the reported bug and cover host and Session collisions.

**Alternatives considered**:

- Test only the new resolver. Rejected because it would not prove that the public command uses it.
- Add live SSH tests to ERT. Rejected because toggle performs no network operation and batch tests must not require a remote host.

## Research closure

Two read-only research agents inspected the core toggle flow and the remote-view ownership state. Repository evidence resolved every technical question. No clarification remains.
