# Quickstart: Local Session Reattach

## Prerequisites

- `zmx` on `PATH`.
- `claude-code-ide-use-zmx` set to t.
- `claude-code-ide-manager-persist-state` set to t (the default).
- Ghostel installed for the live steps.

## Batch gate

```sh
./scripts/compile-and-test.sh
```

All tests pass. MG3 is a known flaky test. Report it as flaky if it fails.

The ERT tests mock `claude-code-ide-zmx--call` and `claude-code-ide-zmx-list-sessions`. They cover:

- the row lifecycle in [data-model.md](data-model.md): retain, startup cleanup, reattach, adopt, detach, stop, Agent exit.
- the messages in [contracts/elisp-surface.md](contracts/elisp-surface.md).
- remote rows: the existing tests pass without change (FR-017), except for the option rename.

## Live check (one Emacs, uses emacsclient)

1. Start two local Sessions in one project with `claude-code-ide-new-session`.
2. Rename one Session, and pin it in the manager.
3. Kill the first Session's buffer.
   Expected: the row shows `[disconnected]` (US1-3).
4. Select the row.
   Expected: the row reattaches, and the earlier output is still visible (US2-2).
5. Restart Emacs. Open the manager.
   Expected: both rows show `[disconnected]` with the same names, order, and pin (US1-1, US1-2).
6. Press `c` on one row.
   Expected: the row is live, and the Agent did not restart (US2-1).
7. Press `a`, and pick the other row's zmx session.
   Expected: one live row with the original name, and no new row (US3-1).
8. Run `zmx kill NAME` in a shell for one Session. Restart Emacs, and open the manager.
   Expected: that row is gone (US4-2).
9. Press `D` on a disconnected row.
   Expected: the row is gone, and `zmx list` still shows the session (US5-1).
10. Press `K` on a disconnected row, and confirm.
   Expected: the row is gone, and `zmx list` does not show the session (US5-2).
