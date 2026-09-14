# Feature Specification: Fix Remote File References

**Feature Branch**: `main` (unchanged. Feature directory numbering is independent.)

**Created**: 2026-09-13

**Status**: Draft

**Input**: User description: "for remote; the transient @ will send like @/rpc:v12mac:/Users/yufu/v12x/packages/core/lib/executor.ts#L316. how can we get an actual relative path? packages/.../executor.ts"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Send a Relative Remote Reference (Priority: P1)

A user edits a remote project file and uses the transient `@` action to reference it in the target Agent Session. The reference identifies the file relative to that session’s directory, without the editor’s remote connection prefix.

**Why this priority**: The current reference exposes an editor-specific path that the remote Agent cannot use directly.

**Independent Test**: Open the reported remote file, select line 316, and invoke `@` for a session rooted at `/Users/yufu/v12x`. Inspect the resulting reference.

**Acceptance Scenarios**:

1. **Given** file `/rpc:v12mac:/Users/yufu/v12x/packages/core/lib/executor.ts` and a target session directory `/Users/yufu/v12x` on `v12mac`, **When** the user sends a reference with line 316 selected, **Then** the reference is `@packages/core/lib/executor.ts#L316`.
2. **Given** the same file and session with no selection, **When** the user invokes `@`, **Then** the reference is `@packages/core/lib/executor.ts`.
3. **Given** the same file with lines 316 through 320 selected, **When** the user invokes `@`, **Then** the reference is `@packages/core/lib/executor.ts#L316-320`.

---

### User Story 2 - Keep References Correct for the Target Session (Priority: P2)

A user works with multiple session directories and files outside a session directory. Each reference must identify the intended file from the receiving session, not from an unrelated editor directory.

**Why this priority**: A short path is useful only when it points to the correct file.

**Independent Test**: Send references to sessions with different base directories. Compare each reference with the file location visible to its target session.

**Acceptance Scenarios**:

1. **Given** the reported file and a target directory `/Users/yufu/v12x/packages` on the same host, **When** the user invokes `@`, **Then** the path portion is `core/lib/executor.ts`.
2. **Given** a target directory `/Users/yufu/v12x` and file `/rpc:v12mac:/Users/yufu/notes.txt` on the same host, **When** the user invokes `@`, **Then** the reference is `@/Users/yufu/notes.txt` without a selection.
3. **Given** a local file and local target session, **When** the user invokes `@`, **Then** existing relative-path, absolute-path, and selection behavior remains unchanged.
4. **Given** a source file on a different host from the target session, **When** the user invokes `@`, **Then** no reference is sent and the user receives an explanation of the host mismatch.

### Edge Cases

- A sibling directory such as `/Users/yufu/v12x-other` is outside `/Users/yufu/v12x`, despite its shared text prefix.
- A remote file directly inside the target directory produces only its filename as the path portion.
- Spaces and non-ASCII characters retain their file identity and existing reference quoting behavior.
- A local file and a remote target, or a remote file and a local target, have different file contexts. No shared filesystem mapping is assumed.
- If the target directory or remote host identity cannot be established, the command explains the missing context instead of sending a guessed remote reference.
- Invocations from file browsers or a session buffer follow the existing source-file selection rules.
- A buffer without a usable source file retains the existing missing-file behavior.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The transient `@` action MUST express a remote file inside the target session’s directory as a path relative to that directory.
- **FR-002**: A reference sent to a remote session MUST omit editor-only remote connection syntax, including `/rpc:v12mac:` in the reported example.
- **FR-003**: Reference generation MUST use the receiving session’s directory, not an unrelated project root or editor directory.
- **FR-004**: The action MUST preserve the `@` marker and existing selection suffix behavior: no suffix, `#L316`, or `#L316-320`.
- **FR-005**: For a file outside the target directory on the same host, the action MUST use the absolute path visible on that host.
- **FR-006**: Directory containment MUST respect directory boundaries. A shared text prefix alone MUST NOT make a file relative.
- **FR-007**: The action MUST NOT send a reference across incompatible local or remote file contexts. It MUST explain the mismatch to the user.
- **FR-008**: If the target directory or host identity is unavailable, the remote action MUST explain the missing context and send no guessed reference.
- **FR-009**: Existing local reference behavior, source-file selection, and missing-file behavior MUST remain unchanged.
- **FR-010**: The behavior MUST apply to supported Agents that receive this action, without a separate user workflow for remote sessions.

### Key Entities *(include if feature involves data)*

- **Source File**: The file the user references, its local or remote host context, and any selected line range.
- **Target Session**: The receiving Agent Session, its host context, and its directory for resolving relative paths.
- **File Reference**: The `@` marker, a target-visible file path, and an optional selection suffix.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The reported example produces exactly `@packages/core/lib/executor.ts#L316` in one invocation, with zero manual path edits.
- **SC-002**: All in-directory remote acceptance cases produce a relative path with zero editor-only connection prefixes.
- **SC-003**: All selection cases preserve the selected line numbers, and all same-host outside-directory cases identify the correct absolute file path.
- **SC-004**: All incompatible-context and missing-context cases send zero misleading references and show an explanation.
- **SC-005**: Existing local acceptance cases produce unchanged references. Users keep the same action for local and remote files.

## Assumptions

- The example session’s directory is `/Users/yufu/v12x` on `v12mac`.
- “Relative” means relative to the target session’s directory, consistent with the existing action’s documented behavior.
- The existing session directory is the reference base. Detecting later directory changes inside an Agent is outside this feature.
- Existing session selection, connection approval, and file access provide the required context. This feature introduces no connection or permission workflow.
- No implicit mapping exists between different hosts or between local and remote filesystems.
- The remote-only difference removes editor connection syntax because the receiving Agent uses paths on its own host.
- Scope is the transient `@` action and its existing entry points. The separate `#` action and other file-send actions retain their current contracts.
- This specification defines behavior only. Implementation and implementation verification belong to the planning and implementation phases.
