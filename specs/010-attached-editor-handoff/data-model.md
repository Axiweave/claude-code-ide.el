# Data Model: Attached-Editor Handoff for Oh My Pi

All values are runtime only. Nothing is persisted.

## Client Nonce (Emacs)

| Field | Type | Owner | Rule |
| --- | --- | --- | --- |
| `claude-code-ide-session--editor-nonce` | global string | Emacs process | Random token created on first use from `random` and the PID. Empty string never occurs. Different Emacs processes have different values with overwhelming probability. |
| `claude-code-ide-session--editor-request` | global cons `(REQUEST-ID . SESSION-BUFFER)` | Emacs process | The one accepted request. Nil when none. |

Relationship: one Emacs process, one nonce. The nonce identifies the initiating Emacs, not the Session or the buffer.

## Editor Origin (Agent)

| Field | Type | Owner | Rule |
| --- | --- | --- | --- |
| `editorOrigin` | `string \| undefined` | module state in `external-editor.ts` | Armed by the composer's `editor-open` or `editor-submit` marker case. Valid for exactly the next input event: the entry that event starts takes it as its first synchronous statement (`onSubmit` for Return, which forwards it as `TuiSlashCommandRuntime.editorOrigin`). The event after that clears whatever is left. |

Lifecycle: armed → taken by the next event's entry → cleared at the start of the event after. The take belongs at the first synchronous statement of whatever the key starts: the key handler for the four key entries, `onSubmit` for a Return. The plan caller awaits a file read (`interactive-mode.ts:4302-4324`) and the submit pipeline awaits several steps (`input-controller.ts:853-959`) before either reaches the helper, which is why neither the helper nor the todo handler can take it.

## Editor Request (Agent)

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | Unique per request. Existing `Snowflake.next()`. |
| `nonce` | string | `options.origin`. Empty for a plain-terminal keystroke or command. |
| `path` | string | Absolute path of the Agent's temp file, `os.tmpdir()/omp-editor-<id><ext>`. |
| `state` | `offered \| accepted \| done \| canceled \| declined` | See transitions. |

Transitions:

```
offered --editor-ack(id)---------> accepted
offered --500 ms without ack-----> declined   (fallback to $EDITOR path)
offered --ctrl+c on input--------> canceled   (byte consumed, draft kept)
accepted --editor-done(id)-------> done       (read file)
accepted --editor-cancel(id)-----> canceled
accepted --ctrl+c on input-------> canceled   (byte consumed, draft kept)
```

Answers with a different id do not change state. `done` with an unreadable file becomes `canceled`. The file is removed on leaving `done`, `canceled`, or `declined`.

At most one request is pending per Agent. `openInEditor` reserves the slot synchronously at entry, before any file write or await, and returns `null` at once when the slot is taken. The existing entries have no busy guard of their own (`custom-editor.ts:1087-1091`, `input-controller.ts:2418-2438`, `hook-editor.ts:248-264`), so the helper owns single-flight. The slot is released in `finally`.

## Prompt Buffer (Emacs)

| Field | Type | Rule |
| --- | --- | --- |
| `buffer-file-name` | string | Local: `path`. Remote: `(concat (claude-code-ide-remote-project-rpc-directory host dir) (file-name-nondirectory path))`. |
| `with-editor-mode` | minor mode | Enabled. Supplies finish and cancel keys. |
| `with-editor-post-finish-hook` | buffer-local | Sends `editor-done;id` to the origin Session buffer after the save. |
| `with-editor-post-cancel-hook` | buffer-local | Sends `editor-cancel;id` to the origin Session buffer after the return. |
| origin Session buffer | buffer object, closure-captured | Target for the answer packets. A dead buffer sends nothing. |

Relationship: one Editor Request, at most one Prompt Buffer, in exactly the Emacs whose nonce matched.

## Session record (existing, read only)

`claude-code-ide-session-host` decides local versus remote file naming. `claude-code-ide--session-cli-type` decides key dispatch. Neither gains a field.
