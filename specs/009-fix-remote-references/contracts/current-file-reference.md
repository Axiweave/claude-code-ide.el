# Interface Contract: Current File `@` Reference

## Entry Point

- Interactive command: `claude-code-ide-send-current-file`.
- Existing transient key: `@`.
- Sources: the existing file buffer, file-browser item, or selected file context from a Session buffer.
- Destination: the existing prompt-buffer or Session-terminal insertion path.

No new command, key, setting, transport, or external protocol is introduced.

## Reference Body

```text
@<path>[#L<start>[-<end>]]
```

The existing insertion layer controls leading and trailing whitespace. The body does not include that whitespace.

| Source / target context | Path result |
| --- | --- |
| Same remote destination, file inside Session directory | Relative host-local path |
| Same remote destination, file outside Session directory | Absolute host-local path |
| Different remote destinations | Error, no insertion or send |
| Local source with remote target | Error, no insertion or send |
| Remote source with local target | Error, no insertion or send |
| Remote source without a known target | Error, no insertion or send |
| Remote target without a usable directory | Error, no insertion or send |
| Local source and local target, or existing local project fallback | Existing local behavior |

A matching path suffix on different hosts does not establish compatibility. The implementation must compare the source destination with the target Session host before it removes remote qualification.

## Acceptance Matrix

Unless stated otherwise, the target is `v12mac` with Session directory `/Users/yufu/v12x`.

| Case | Source path on target host | Selection | Expected body |
| --- | --- | --- | --- |
| Reported example | `/Users/yufu/v12x/packages/core/lib/executor.ts` | 316 | `@packages/core/lib/executor.ts#L316` |
| No selection | Same file | None | `@packages/core/lib/executor.ts` |
| Multiple lines | Same file | 316–320 | `@packages/core/lib/executor.ts#L316-320` |
| Root-level file | `/Users/yufu/v12x/main.ts` | None | `@main.ts` |
| Outside directory | `/Users/yufu/notes.txt` | None | `@/Users/yufu/notes.txt` |
| Similar directory prefix | `/Users/yufu/v12x-other/a.ts` | None | `@/Users/yufu/v12x-other/a.ts` |
| Nested target `/Users/yufu/v12x/packages` | Reported file | 316 | `@core/lib/executor.ts#L316` |
| Spaces and Unicode | `/Users/yufu/v12x/docs/设计 notes.txt` | None | `@docs/设计 notes.txt` |

The spaces-and-Unicode case preserves the existing raw-body contract. This feature does not add a quoting scheme.

## Error Contract

Raise a user-visible error before the existing send action when remote context is missing, invalid, or incompatible. Explain whether the user must select a matching Session or restore its directory context.

Tests assert the error category and absence of insertion or send. They must not pin exact error wording.

Errors leave the terminal, connection, Session directory, host approval, and source buffer unchanged.

## Compatibility

- Preserve selection behavior for Emacs regions and Evil visual selections.
- Preserve existing target selection and prompt-buffer preference.
- A prompt buffer does not supply missing remote target identity.
- Preserve local project-root fallback when no target Session is known.
- Preserve the separate `#`, `f`, `F`, and `h` command contracts.
- Apply the same current-file contract to supported Agents without Agent-specific path conversion.

See [data-model.md](../data-model.md) for value ownership and [quickstart.md](../quickstart.md) for validation steps.
