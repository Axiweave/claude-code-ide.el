# Contract: Session Toggle

## User-facing command contract

`claude-code-ide-toggle` remains the single interactive command for local and remote Session visibility. This document defines its observable command and UI behavior, not a new programmatic interface.

## Target precedence

1. If the invoking buffer owns a live Session terminal, toggle that exact Session.
2. Otherwise, if the invoking buffer is the active Session's saved managed project view, toggle that exact Session.
3. Otherwise, if the invoking buffer is remote, signal a user-visible no-session error without directory fallback.
4. Otherwise, use the existing local attached-project and working-directory fallback.
5. If no live Session matches, signal a user-visible no-session error.

Exact Session identity wins over directory, recency, and buffer naming.

## Identity rules

- Local and remote Sessions with identical directory text remain distinct.
- Remote Sessions on different hosts remain distinct.
- Sibling Sessions on one host and directory remain distinct when a terminal or managed view supplies exact ownership.
- An unrelated RPC buffer does not inherit the manager's active Session.
- A remembered disconnected target is not a live toggle target.

## Visibility behavior

- A visible target Session becomes hidden.
- A hidden target Session becomes visible through the existing display path.
- Existing saved layout and focus behavior remain unchanged.
- Repeated invocations do not create duplicate Sessions or terminal buffers.

## Side-effect limits

The command performs no:

- remote discovery or network access,
- attachment or reattachment,
- Agent or shell creation,
- host approval change,
- manager persistence change,
- new prompt or Session selection.

## Error behavior

When no applicable live Session exists, the command signals `user-error`. Tests assert the error type and absence of side effects. They do not pin exact wording.

## Compatibility

Local terminal invocation and local project-buffer fallback retain their existing behavior. The wrapper `claude-code-ide-toggle-window` inherits this contract without a separate code path.
