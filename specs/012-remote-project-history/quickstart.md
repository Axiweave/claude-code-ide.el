# Quickstart: Validate Remote Project History

## Prerequisites

- Use Emacs 28.1 or later.
- Configure at least two exact remote hosts.
- Prepare one valid repository path on each host.
- Keep manager persistence enabled for restart checks.
- Use a test environment where remote requests can be canceled safely.

## Batch Gate

From the repository root, run:

```sh
./scripts/compile-and-test.sh
```

Expected result: byte compilation succeeds and the full ERT suite reports zero unexpected results.

## Scenario 1: Manual Entry Becomes Recent

1. Open the global manager.
2. Invoke the Remote Worktree menu, then explicit remote open.
3. Select host A.
4. Enter a valid absolute repository path that is not listed.
5. Accept the remote-open request.
6. Invoke explicit remote open again and select host A.

Expected results:

- The entered path appears first.
- The path appears once.
- No remote directory browser opens.

## Scenario 2: History Survives Restart

1. Complete Scenario 1.
2. Restart Emacs.
3. Open the global manager.
4. Invoke explicit remote open and select host A.

Expected result: the repository from Scenario 1 remains selectable without retyping.

## Scenario 3: Host Isolation

1. Record one repository for host A.
2. Record a different repository for host B.
3. Open the picker for each host.

Expected results:

- Host A shows only host A history.
- Host B shows only host B history.
- Identical path text on both hosts remains two separate targets.

## Scenario 4: Explicit and Contextual Commands

1. Put point on a remote Session row for host A.
2. Invoke explicit remote open from the Remote Worktree menu.
3. Select host B and one of its repositories.
4. Return point to the host A row.
5. Invoke ordinary contextual open.

Expected results:

- Explicit remote open asks for host and repository.
- Ordinary open keeps using the selected row's host and repository.

## Scenario 5: Refusal Does Not Pollute History

1. Invoke explicit remote open.
2. Enter a relative or malformed path, then cancel.
3. Invoke the picker again.

Expected result: the refused path is absent and prior MRU order is unchanged.

## Scenario 6: Restore Is Inert

Run the focused ERT coverage for restored history with malformed paths, duplicate paths, and an unconfigured host.

Expected results:

- Valid paths restore in stored order.
- Invalid and duplicate paths do not become duplicate choices.
- Unconfigured-host entries remain unavailable.
- No SSH, RPC, Worktree, or Agent request occurs during restore.

See [data-model.md](data-model.md) for identity and restore rules. See [contracts/remote-project-picker.md](contracts/remote-project-picker.md) for command behavior.
