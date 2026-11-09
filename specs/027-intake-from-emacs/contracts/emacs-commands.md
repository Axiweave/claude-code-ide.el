# Contract: Emacs commands for the Intake process

All four commands are interactive and autoloaded. They need neither `curl` nor the token file. `URL` is `claude-code-ide-intake-url`. `BUFFER` is `*claude-code-ide-intake*`.

## `claude-code-ide-intake-start`

The command checks these cases in order. The first case that matches gives the result.

| Case | Result |
|---|---|
| `claude-code-ide-intake-command` is `nil` | `user-error`: `Set claude-code-ide-intake-command to start the Intake from Emacs` |
| `URL` is `nil` | `user-error`: `Set claude-code-ide-intake-url to use the Intake` |
| `URL` host is not loopback | `user-error`: `Emacs starts the Intake only on this machine; URL is not a loopback address` |
| The managed Intake runs | message: `The Intake that Emacs started already runs` |
| An Intake answers at `URL` | message: `An Intake already answers at URL; Emacs starts no second one` |
| Otherwise | Erase `BUFFER`, start the process in `~`, and run the start wait |

The check for an answering Intake is asynchronous. So the last two cases give a message, not a `user-error`.

The start checks the managed Intake twice: before the connect check, and again in its callback, just before it starts the process. When a process started in the meantime, the callback gives `The Intake that Emacs started already runs` and starts nothing. So two start steps that run before the first answer, such as the start command and the mode, start exactly one process.

Start wait results (one message each):

| Event | Message |
|---|---|
| The connect check gives `open` | `Intake answers at URL` |
| The process exits first | `Intake ended (exit N): LINE` |
| 20 checks, 0.5 seconds apart, without `open` | `Intake started but does not answer yet; see *claude-code-ide-intake*` |

`LINE` is the last output line that starts with `error:`. Without such a line, it is the last non-blank output line.

`N` comes from the sentinel event: the number in `exited abnormally with code N`, or 0 for `finished`. For a signal event, such as `killed: 9`, the parenthesis holds the trimmed event text instead of `exit N` (research D6).

## `claude-code-ide-intake-stop`

| Case | Result |
|---|---|
| The managed Intake runs | Send `SIGTERM` and wait up to 50 steps of 0.1 seconds. If the process is still live, send `SIGKILL` and wait until it is not live. Message: `Intake stopped` |
| No managed Intake, and an Intake answers | message: `Emacs did not start the running Intake; stop it where it was started` |
| No managed Intake, and none answers | message: `No Intake runs` |

The stop ends only the managed process. A stop shows no "ended" message.

## `claude-code-ide-intake-restart`

Stop the managed Intake when it runs, then run `claude-code-ide-intake-start`. When an Intake that Emacs did not start answers, the result is the start's "already answers" message.

## `claude-code-ide-intake-log`

Show `BUFFER` in another window. When it does not exist, show the message `Emacs has not started the Intake`.

## Unasked end

When the managed process exits without a stop, after the start wait or during it, Emacs shows `Intake ended (exit N): LINE` once. It does not start the process again. When Emacs exits, Emacs ends the process without a question.

## `claude-code-ide-intake-mode` (changed)

When the mode turns on, and `claude-code-ide-intake-command` is set, and the `URL` host is loopback, the mode first runs the start step. When an Intake already answers, or the managed Intake already runs, the start step is silent. The mode then connects as it does today. In every other case, the mode works as it does today. Turning the mode off does not stop the Intake.

The first connection can come before the Intake answers. It then fails without a message, and the existing reconnect tries again after 1, 2, 4 … seconds. The first successful connection comes at most 8 seconds after the Intake answers (research D8).
