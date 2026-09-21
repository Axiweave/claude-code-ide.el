# Feature Specification: Remote Preview for the Project File Pickers

**Feature Branch**: `main` (unchanged. Feature directory numbering is independent.)

**Created**: 2026-09-20

**Status**: Implemented

**Input**: User description: "the saved cursor ... h does not work over tramp-rpc path" and "to make them look like this (this transient + F); both for f (projectile <- think how to make it work? or use consult-fd; why you currently do) and h"

**Supersedes**: The scope restriction of `specs/009-fix-remote-references`. Spec 009 kept the pickers `f`, `F`, and `h` on their old contract. This specification extends the same remote conversion to those pickers.

## Problem

The `h` action built its reference from `(expand-file-name selected home)`. A remote pick therefore reached the Agent as `@/rpc:v12mac:/Users/yufu/v12x/packages/core/lib/executor.ts`. The remote Agent cannot resolve that path. A live probe in the author's Emacs confirmed the exact string. The same expression handed an RPC name to its file name handler.

The `f` and `F` actions called `claude-code-ide--file-reference-path` without `remote-aware`, and they passed RPC names through `file-relative-name`. A remote pick therefore reached the Agent with the editor prefix as well. `f` also read its file list from `project-files`, which cannot enumerate a remote host.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Send a file from home on a remote host (Priority: P1)

A user works in a Session on a remote host and invokes `h`. The prompt browses the account home directory on that host. The Agent receives the host-local absolute path.

**Acceptance Scenarios**:

1. **Given** a Session for host `v12mac` and a pick of `/rpc:v12mac:/Users/yufu/notes.txt`, **When** the user invokes `h`, **Then** the reference is `@/Users/yufu/notes.txt`.
2. **Given** the same Session, **When** the prompt opens, **Then** the prompt directory is `/rpc:v12mac:~/`.
3. **Given** the same Session and a pick of `/rpc:v12mac:/Users/yufu/v12x/packages/main.el`, **When** the user invokes `h`, **Then** the reference keeps the absolute path and is not relative to the Session directory.

---

### User Story 2 - Pick a project file on a remote host (Priority: P2)

A user invokes `f` or `F` while the target Session runs on a remote host. The prompt browses the Session directory on that host, and the reference is relative to it.

**Acceptance Scenarios**:

1. **Given** a Session for host `v12mac` with directory `/Users/yufu/v12x`, **When** the user invokes `f` and picks `/rpc:v12mac:/Users/yufu/v12x/packages/main.el`, **Then** the reference is `@packages/main.el`.
2. **Given** the same Session, **When** the prompt opens, **Then** the prompt directory is `/rpc:v12mac:/Users/yufu/v12x/`.
3. **Given** a local project and a local Session, **When** the user invokes `f`, **Then** the picker still offers the flat project file list, and the reference is unchanged.

---

### User Story 3 - Reject a pick from another file context (Priority: P3)

A picker never sends a path that the receiving Agent cannot resolve.

**Acceptance Scenarios**:

1. **Given** a Session for host `v12mac` and a pick of the local file `/work/a.ts`, **When** the user invokes `f`, `F`, or `h`, **Then** the command signals an error and sends nothing.

---

### Edge Cases

- Reference generation never dispatches an RPC name to a file name handler. The conversion uses string work only.
- A local target keeps the local home directory for `h`, and the flat project file list for `f`.
- The remote home is named without a remote call, because the transport expands the trailing tilde.
- A host without the remote Project module fails before insertion, as in spec 009.
- A configured picker decides the search tool, the prompt, and the fallback when the host cannot run that tool.

## Requirements *(mandatory)*

- **FR-001**: For a remote Session, the `h` prompt MUST start at the account home directory on the Session host, expressed through the editor transport.
- **FR-002**: For a remote Session, the `f` and `F` prompt MUST start at the Session directory on the Session host, expressed through the editor transport.
- **FR-003**: Every picker MUST convert a remote pick to the target-visible host-local path, without the `/rpc:HOST:` prefix.
- **FR-004**: The `f` and `F` actions MUST relativize the host-local path against the Session directory when the path lies inside it.
- **FR-005**: The `h` action MUST send the absolute host-local path, inside or outside the Session directory.
- **FR-006**: A pick from a file context that does not match the target Session MUST produce an explanation and no reference.
- **FR-007**: Reference generation MUST NOT pass an RPC name to `expand-file-name` or `file-relative-name`.
- **FR-008**: A local target MUST keep the current local behavior: the local home directory for `h`, and the flat project file list for `f`.
- **FR-009**: The transport encoding MUST come from `claude-code-ide-remote-project`, never from the command code.
- **FR-010**: The `f` and `h` actions MUST read their file through `claude-code-ide-file-reference-picker-function` when it is set.  The function MUST receive the search directory and the Session host, and it MUST return an absolute file name or a name relative to that directory.
- **FR-011**: A name relative to an editor remote directory MUST resolve without a transport call.

## Key Entities

- **Picker action**: `f` (`claude-code-ide-send-file`), `F` (`claude-code-ide-send-file-from-root`), `h` (`claude-code-ide-send-file-from-home`).
- **Browse root**: the directory a picker prompt shows. A remote Session uses its host transport. A local target uses the local filesystem.
- **File reference**: the `@` marker and a path the receiving Agent can resolve.

## Success Criteria

- **SC-001**: A remote `h` reference contains no `/rpc:` text and starts with `/`.
- **SC-002**: A remote `f` reference inside the Session directory is relative to that directory.
- **SC-003**: No test observes an RPC name in `expand-file-name` or `file-relative-name`.
- **SC-004**: All local picker tests keep their current expectations.
- **SC-005**: A configured picker receives the Session directory and the Session host for both actions.
