# Contract: Terminal Editor Handoff Protocol

Wire protocol between Oh My Pi (Agent) and an attached Emacs Session buffer of this package. Both directions travel over the Session PTY. The multiplexer forwards Agent output to every client unchanged. For client input, zmx has a leader client: a non-leader client's write is forwarded (and makes it the leader) only when `util.isUserInput` finds a printable, CR/LF/TAB/BS, or a CSI key sequence in it (zmx 0.7.1 `main.zig:1036-1046`, `util.zig:567-608`). A write that holds only an APC and a BEL is dropped. Every Emacs → Agent write below therefore carries a key encoding that passes this gate.

## Emacs → Agent (APC, on the Agent's stdin)

Frame: `ESC _ pi:<kind>;<value> ESC \`. Same family as the existing `pi:prompt` and `pi:keyword` packets. `<value>` never contains whitespace, `/`, or control characters. The origin markers `editor-open` and `editor-submit` are always followed, in the same write, by the key they describe: kitty CSI-u ctrl+g (`ESC [ 103;5 u`) for `editor-open`, `\r` for `editor-submit`. The Agent matches the key by key id, so `\x07` and `ESC [ 103;5 u` both count as ctrl+g in either keyboard mode. The Agent's input buffer delivers the APC and the key as two events, so an Agent that predates this contract consumes the marker event and still receives the key.

| kind | value | Meaning |
| --- | --- | --- |
| `editor-open` | client nonce | Origin marker. The ctrl+g that follows in the same write (CSI-u, so zmx forwards it) is the external-editor keystroke from this Emacs. The Agent arms the nonce for exactly the next input event. |
| `editor-submit` | client nonce | Origin marker. The `\r` that follows in the same write is the Return from this Emacs. The Agent arms the nonce for exactly the next input event, so a submitted command such as `/todo edit` carries it. |
| `editor-ack` | request id | This Emacs accepted the request and will visit the file. |
| `editor-done` | request id | The user finished. The file is saved. The Agent reads it. |
| `editor-cancel` | request id | The user canceled. The Agent keeps its previous text. |

The Agent ignores `editor-ack`, `editor-done`, and `editor-cancel` whose request id is not the pending one. Every packet is consumed and never reaches key parsing. An armed nonce is valid for exactly the next input event: the entry that event starts takes it as its first synchronous statement, and the event after that clears whatever is left. Any other client's byte that lands between the marker and the key therefore takes or clears the nonce, which yields a fallback, never a wrong Emacs. A raw `ctrl+c` byte while a request is pending is consumed as `editor-cancel`. With no pending request it passes through unchanged.

## Agent → Emacs (OSC 52;e, on the Agent's stdout)

Frame: `ESC ] 52;e;"claude-code-ide-session-editor-request" "<request-id>" "<nonce>" "<path>" ESC \`

- `request-id`: unique per request, ASCII, no whitespace.
- `nonce`: the nonce armed by the `editor-open` or `editor-submit` marker that preceded the keystroke. A keystroke without one (plain terminal, other Emacs, or any input between the marker and the key) has an empty origin. No client can accept an empty nonce, so the Agent sends no request for it and goes straight to the fallback with no ack wait.
- `path`: absolute path of the Agent's file on the Agent host, with its extension. Shell-quoted per the Ghostel `ghostel_cmd` convention: backslash and double quote escaped with a backslash.

Every attached client receives this frame. A Ghostel buffer without a live Session owner of this package returns nil from the handler and shows nothing. A Session buffer whose nonce differs ignores it.

## Timing

1. Agent writes the request, then waits up to 500 ms for `editor-ack`. A `ctrl+c` byte during this wait cancels the request and is consumed.
2. No `editor-ack`: the Agent stops listening for this request id and continues with `$VISUAL`/`$EDITOR`, or the existing "No editor configured" warning.
3. `editor-ack` received: the Agent keeps its TUI running and waits without a deadline for `editor-done` or `editor-cancel`. A `ctrl+c` byte on input during this wait counts as `editor-cancel`.
4. `editor-done`: the Agent reads the file. Missing file or read error counts as cancel.
5. The Agent removes the file after step 4 in every outcome.

## Guarantees

- One request id has at most one outcome.
- At most one request is pending per Agent. An editor entry while one is pending returns at once with no file, no packet, and no change to the pending request.
- A request without a nonce never opens a buffer in any Emacs. The Agent does not offer it: an empty origin skips the request and the 500 ms window.
- Content never crosses the terminal. Only the path does, so content size is bounded by the file system alone.
- The Agent never blocks input while a request is pending.
- Agents that predate this contract consume the markers and receive the raw key, so `C-g` and Return behave as before. Clients that predate it ignore the request. Both combinations keep the old `$EDITOR` behavior.

## Examples

Emacs presses the key (one write):

```
ESC _ pi:editor-open;a3f9c1 ESC \ ESC [ 103;5 u
```

Agent request:

```
ESC ] 52;e;"claude-code-ide-session-editor-request" "r-7f2e" "a3f9c1" "/var/folders/xy/T/omp-editor-1234.md" ESC \
```

Emacs answers:

```
ESC _ pi:editor-ack;r-7f2e ESC \
... user edits, C-c C-c ...
ESC _ pi:editor-done;r-7f2e ESC \
```
