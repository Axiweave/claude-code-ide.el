# Contract: Emacs adopt command and pull path

## `claude-code-ide-adopt-session HOST NAME`

```elisp
;;;###autoload
(defun claude-code-ide-adopt-session (host name) ...)
```

- `HOST` is nil for a local session, or a member of `claude-code-ide-remote-hosts`.
- `NAME` must pass `claude-code-ide-zmx--package-name-p`.
- A bad `HOST` or `NAME` makes the command return `refused` (FR-011, spec edge case "Host not configured in Emacs"). The first refusal of a `(HOST . NAME)` pair shows one `message` in Emacs that names the refused value and the Session name. The command adds the pair to `claude-code-ide--refused-sessions` and shows no message for it again. The Intake sends an event on each Agent state change, so without this list the message would repeat. The pair does not go to the adopted list. Thus, after the user fixes the config, the next event adopts the Session. The command does not signal an error, because `emacsclient --eval` would return the error to the caller and Emacs would show nothing. `emacsclient` prints `refused`.
- When `(HOST . NAME)` is in `claude-code-ide--adopted-sessions` or `claude-code-ide--pending-adoptions`, or is already a live Session target, the command returns `skipped`. When the pair is a live Session target, the command also adds the pair to the adopted list. Thus a Session that the user attached by hand is not adopted again after the user disconnects it.
- Otherwise it adds the pair to the pending list. It schedules `claude-code-ide--adopt-spawned-session` with `run-at-time 0` and returns `adopting`. The pair leaves the pending list when the adopt call ends, with or without success.
- When the adopt call ends and the Session is live, the command adds the pair to the adopted list. The pair stays there for the life of this Emacs. Thus a Session attached once by this command is not adopted again in this Emacs. A failed adopt does not add the pair, so the next event tries again. The Intake sends a `running` event on each Agent state change. Without this list, the next event would attach a Session again after the user disconnects it. The user can still attach it by hand with `claude-code-ide-attach`. The manual attach commands do not read the adopted list.
- The adopted Session follows `claude-code-ide-switch-on-spawn`, as a Sibling Session does (FR-010).

### Push call from the Intake

```sh
emacsclient --eval '(claude-code-ide-adopt-session "v12dev" "cci-omp-api-x1y2z3")'
emacsclient --eval '(claude-code-ide-adopt-session nil "cci-omp-api-x1y2z3")'
```

The Intake checks both strings against the host pattern and the zmx name pattern before it builds the form. Neither pattern allows a quote or a backslash. For an Emacs on another machine, the Intake runs the same command through `ssh EMACS_HOST --`.

## Pull path: `claude-code-ide-intake.el`

| Option | Type | Default | Meaning |
|---|---|---|---|
| `claude-code-ide-intake-url` | string or nil | nil | The Intake base URL. nil turns pull off, and the package then never contacts the Intake (FR-012). |
| `claude-code-ide-intake-token-file` | file | `"~/.config/cci-intake/token"` | The file that holds the bearer token. It is read at each connect. |
| `claude-code-ide-intake-client` | string | `(system-name)` | The `[[emacs]]` name that the Intake knows this Emacs by. |

Global minor mode `claude-code-ide-intake-mode`:

- **On**: It signals a `user-error` when `curl` is missing or the URL is nil. It then opens the stream (`GET /v1/events?client=…`), and then reads the list once (`GET /v1/launches?state=running&client=…`). It adopts each listed Launch that has an `emacs_host` key. The stream opens first, so a Launch that starts between the two requests is not lost.
- **Event**: For a `launch` event with `state` `running` and an `emacs_host` key, it calls `(claude-code-ide-adopt-session emacs_host name)`. It ignores every other event.
- **Stream end**: It reconnects after the current delay, then doubles the delay up to 60 s. Each reconnect repeats the list read. The first event resets the delay to 1 s.
- **Off**: It deletes the curl process and cancels the timer.

Both requests run `curl -sN --fail --config -`. The command sends `header = "Authorization: Bearer <token>"` and `url = "<url>"` on stdin, then closes stdin. The token never appears in a process argument.

Both requests use `--fail`. When the Intake answers with an HTTP error, curl exits with code 22. Emacs then shows one message: "Intake refused PATH: check `claude-code-ide-intake-client' and `claude-code-ide-intake-token-file'". PATH is the request path. A connection error shows no message. The stream then reconnects as for a stream end.
