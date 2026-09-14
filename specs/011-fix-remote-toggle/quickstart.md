# Quickstart: Validate Remote Session Toggle

## Prerequisites

- Use Emacs 28.1 or later.
- Load this package with Ghostel available.
- Prepare one local Session and one attached remote Session with the same directory text.
- For the managed-view scenario, enable the existing remote project view for the remote Session.

## Batch validation

From the repository root, run the project test runner. It supplies the installed package load paths:

```bash
./scripts/compile-and-test.sh
```

Expected result: byte compilation succeeds and the ERT suite reports zero unexpected results. The suite includes all `claude-code-ide-test-toggle-` scenarios.

## Reload changed files

After the gate passes, load each changed Elisp file through the active Emacs server:

```bash
emacsclient --eval '(load "/absolute/path/to/claude-code-ide-manager.el")'
emacsclient --eval '(load "/absolute/path/to/claude-code-ide.el")'
```

Expected result: each expression returns a non-nil load result without an error.

## Live scenario 1: Exact remote terminal

1. Attach a remote Agent Session.
2. Start or retain a local Session with identical directory text.
3. Select the remote terminal.
4. Invoke `M-x claude-code-ide-toggle`.
5. Invoke the command again from the associated managed context.

Expected result: the remote terminal hides and restores. The local terminal does not change.

## Live scenario 2: Host collision

1. Attach Sessions on two hosts with identical directory and zmx Session names.
2. Invoke the toggle from each remote terminal.

Expected result: each invocation affects only the terminal on the invoking Session's host.

## Live scenario 3: Managed project view

1. Open the managed remote project view for one attached Session.
2. Keep a sibling Session for the same host and directory live.
3. Invoke the toggle from the managed project view.

Expected result: the layout's exact Session hides or restores. The sibling does not change.

## Live scenario 4: Remote Magit buffer

1. Open Magit for the remote Session's RPC project directory.
2. Keep a Session with the same path on another host.
3. Invoke the toggle from the remote Magit buffer.

Expected result: the command toggles the Session on the Magit buffer's host. The other host does not change.

## Live scenario 5: No implicit reattach

1. Disconnect a remembered remote target.
2. Select an unrelated remote project buffer with matching path text.
3. Invoke the toggle.

Expected result: the command reports no applicable live Session. It makes no connection and changes no local Session.

See [the Session toggle contract](contracts/session-toggle.md) for target precedence. See [the data model](data-model.md) for identity and liveness rules.
