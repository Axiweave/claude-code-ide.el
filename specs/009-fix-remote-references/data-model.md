# Data Model: Remote File References

This feature uses existing values. It adds no records, persistence fields, or Session state.

## Source File

| Field | Representation | Rule |
| --- | --- | --- |
| Editor filename | Existing absolute buffer or browser filename | Preserve the original value. |
| Remote identity | Parsed remote destination, or nil for local | Must match the target context before conversion. |
| Host-local path | Absolute path without editor connection syntax | Extract only after identifying the remote source. |
| Selection | Existing start/end line pair, or nil | Preserve current selection semantics. |

The Source File comes from the existing file-reference context resolver. No new file discovery or remote access occurs.

## Target Session

| Field | Representation | Rule |
| --- | --- | --- |
| Buffer | Existing live Session buffer | Resolve through the existing reference target selection. |
| Host | Existing Session host string, or nil for local | Read the Session object, not terminal `default-directory`. |
| Session directory | Existing bare absolute directory string | Remains metadata on the Session host. |

A remote Source File requires a known compatible Target Session and a usable Session directory. A local Source File retains existing local project fallback when no Session is available.

A remote Target Session cannot resolve a local Source File without an explicit filesystem mapping. This feature adds no such mapping.

## File Reference

| Field | Representation | Rule |
| --- | --- | --- |
| Marker | `@` | Unchanged. |
| Path | Relative in-directory path or host-local absolute path | No editor-only remote prefix reaches a remote target. |
| Suffix | Empty, `#LSTART`, or `#LSTART-END` | Reuse existing selection formatting. |

The insertion layer owns surrounding whitespace and destination selection. The path conversion does not add escaping, quoting, or terminal behavior.

## Relationships and Validation

- One invocation resolves one Source File and one Target Session context.
- A compatible pair produces one File Reference.
- An incompatible or incomplete remote context produces a `user-error` before insertion or terminal send.
- Directory containment uses normalized path components, not a raw directory prefix.
- A relative result equal to `..`, or starting with `../`, represents an outside-directory file.
- Outside-directory files retain the host-local absolute path.
- Normalization is lexical. It does not resolve symlinks or inspect local or remote filesystems.
- A remote Session directory remains bare throughout conversion, as required by ADR 0003.

## State Transitions

There is no new persistent state machine.

```text
existing source and target resolution
    -> validate remote context, if either side is remote
    -> convert the path
    -> append the existing selection suffix
    -> use the existing insertion/send action
```

Validation failure stops the action before any reference reaches a prompt buffer or terminal. It does not detach, reconnect, or modify the Session.
