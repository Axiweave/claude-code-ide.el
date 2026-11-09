# Research: Start the Intake from Emacs

## D1 One setting: the Intake command setting as a list

- **Decision**: `claude-code-ide-intake-command` is a list of strings, the program and its arguments, default `nil`. Emacs runs it in the user's home directory. Example: `("/Users/me/.bun/bin/bun" "run" "/Users/me/agents/cci-intake/src/main.ts")`.
- **Rationale**: The constitution (I) keeps CLI paths as user configuration, so the default is empty and names no program. `bun run` takes an absolute file path, and the Intake reads its configuration and database from fixed places, not from the working directory. So a fixed directory is enough. One list avoids shell quoting.
- **Alternatives considered**: A separate directory setting. It is not needed for the Intake, and a user who needs one can use `("sh" "-c" "cd DIR && …")`. A shell string. It needs quoting rules.

## D2 "Answers" is a non-blocking TCP connect

- **Decision**: Emacs checks the host and port of `claude-code-ide-intake-url` with `make-network-process :nowait t`. The sentinel's first event `"open\n"` means that the Intake answers. An event that starts with `"failed"` means that it does not. Emacs deletes the connection after the first event.
- **Rationale**: This matches the spec ("accepts a connection"). It needs no token and no curl, so it also works before the token file exists. It does not block Emacs. A live check on this MacBook gave `"open\n"` for the running Intake on 7311, and `"failed with code 61\n"` for a closed port.
- **Alternatives considered**: `curl` to a route. It needs the token, or it reads a 401 as "answers", and it adds a dependency to the start command. A blocking `open-network-stream`. It can freeze Emacs on a bad host.
- **Double start**: The connect check is asynchronous, so two start steps can both wait for an answer. Each callback checks `--managed` again before `make-process`. Emacs Lisp runs one callback at a time, so the first callback sets `--managed` before the second one runs. A second Intake process is harmful even when it cannot bind the port, because the Intake runs `recover()` before `serve()` (`main.ts`). `recover()` resets the sending Notices and sends follow-ups and Notices again (`launches.ts`).

## D3 Only a loopback URL

- **Decision**: Emacs starts the Intake only when the URL host is `localhost`, `::1` (written `[::1]`), or an IPv4 address `127.N.N.N`. A name such as `127.example.com` is not loopback. Otherwise the start command gives a `user-error` that names the URL.
- **Rationale**: FR-004. `url-generic-parse-url` gives the host `"127.0.0.1"`, `"localhost"`, or `"[::1]"` (checked live). A private address such as `100.64.1.2` can be another machine, so it does not count.
- **Alternatives considered**: Resolve the host and compare it with the local interfaces. This adds complexity for no current use.

## D4 The managed process

- **Decision**: `make-process` with `:command` from D1, `:connection-type 'pipe`, `:noquery t`, and stdout and stderr to the buffer `*claude-code-ide-intake*`. Each start erases that buffer. The buffer's mode line shows the process status with `mode-line-process` `(":%s")`. Emacs keeps the process object in one variable. There is at most one managed Intake.
- **Rationale**: FR-006 and FR-010. With `:noquery t`, Emacs asks no question at exit. When Emacs exits, it sends `SIGHUP` to its child processes. A live check showed that a `:noquery` child got `SIGHUP` and ended. The Intake ends on `SIGHUP`, and its records stay safe, because it records each Launch before it acts (024). So no `kill-emacs-hook` is needed.
- **Alternatives considered**: A `kill-emacs-hook` that sends `SIGTERM` first. Emacs sends `SIGHUP` right after the hook, so the hook gains nothing. `start-process-shell-command`. It adds a shell and quoting.

## D5 Start wait

- **Decision**: After `make-process`, Emacs runs the check from D2 every 0.5 seconds, for up to 20 checks (10 seconds). The first `open` gives the message `Intake answers at URL`. The process ending first gives the start-failure message from D6. After 20 failed checks, Emacs shows `Intake started but does not answer yet; see *claude-code-ide-intake*`. A timer drives the checks, so Emacs does not block.
- **Rationale**: FR-005 and SC-001. The Intake usually answers in less than 1 second.
- **Owner check**: Each wait step holds the process that it waits for. A step, or the callback of its connect check, that finds this process is not `eq` to `--managed` does nothing: no message and no new timer. A connect check that is open during a stop or a restart then has no effect.

## D6 Ended and failure messages

- **Decision**: The process sentinel handles an end that the user did not ask for. It shows one message, `Intake ended (exit N): LINE`, where LINE is the last output line that starts with `error:`. Without such a line, LINE is the last non-blank line. Emacs does not start the Intake again.
- **Exit status**: The sentinel takes N from its event text, not from `process-exit-status`. The event `exited abnormally with code N` gives N. The event `finished` gives 0. For a signal event, such as `killed: 9`, the parenthesis holds the trimmed event text instead of `exit N`. The tests end a mocked pipe process, and `process-exit-status` of such a process is 0. The event text carries the status in both cases.
- **Sentinel actions**: When the process is not live, the sentinel always sets `--managed` to nil and cancels the start wait. Only the "ended" message depends on `--stopping`: it appears when `--stopping` is nil.
- **Rationale**: FR-007 and SC-005. When the Intake refuses its configuration, Bun prints a stack and ends with the line `Bun v1.4.4 (macOS arm64)`. The useful line is `error: projects.p026.path: …` (seen in the 026 live run).

## D7 Stop and restart

- **Decision**: Stop sends `SIGTERM` to the managed process. It waits in up to 50 steps of `(accept-process-output process 0.1)`, which is about 5 seconds. If the process is still live, stop sends `SIGKILL` and waits with the same step until the process is not live. Then it shows `Intake stopped`. The wait counts steps, not clock time, so a test with a mocked `accept-process-output` ends at once. During a stop, the sentinel shows no "ended" message. Stop runs its steps inside `unwind-protect`. Its cleanup cancels the start wait, sets `--managed` to nil, and clears `--stopping`. So the next unasked end shows its message (FR-007), also after a `C-g` during the wait, and also when the sentinel did not run. Restart is stop, then start. With no managed process, stop shows `Emacs did not start the running Intake` when the check from D2 answers, and `No Intake runs` when it does not. Stop and restart never end an Intake that this Emacs did not start.
- **Rationale**: FR-008. The Intake handles `SIGTERM` (`main.ts`), so it closes its database and exits 0.

## D8 Start with Intake pull

- **Decision**: When `claude-code-ide-intake-mode` turns on, the Intake command setting is set, and the URL is loopback, the mode first runs the start step. When an Intake already answers, or the managed Intake already runs, the start step is silent. The mode then connects as it does today. If the stream fails before the Intake answers, the existing reconnect connects later. Turning the mode off does not stop the Intake.
- **Timing**: The reconnect delays are 1, 2, 4, 8 … seconds, so the tries come about 0, 1, 3, 7, and 15 seconds after the mode turns on. The first successful connection is the first try after the Intake answers, which satisfies US3 AC1 ("connects to it after it answers"). The Intake usually answers in less than 1 second, so the mode connects at about 1 second. If the Intake answers late in the 10-second start wait, the mode connects at about 15 seconds. That is at most 8 seconds after the Intake answers.
- **Rationale**: FR-009 and clarification Q2. The start step is issued before the first connection, so the Intake starts first. Reusing the existing reconnect needs no new wait in the mode.
- **Alternatives considered**: Connect from the `open` result of the start wait. This adds a second path into `--connect`. It saves at most 8 seconds, and only when the Intake answers slowly.

## D9 Commands

- **Decision**: `claude-code-ide-intake-start`, `claude-code-ide-intake-stop`, `claude-code-ide-intake-restart`, and `claude-code-ide-intake-log` (show the output buffer). All four are autoloaded. They live in `claude-code-ide-intake.el`.
- **Rationale**: The prefix and file of the existing Intake client. The new commands do not need `curl` or the token file, so they do not call `claude-code-ide-intake--check`.
