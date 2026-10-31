# Quickstart: Disconnect Session

## Prerequisites

- Spec 019 in the tree (commit `a19f021` or later).
- For the live checks: `zmx` installed and `claude-code-ide-use-zmx` on. A configured remote host for check 3.

## 1. Batch gate

```sh
./scripts/compile-and-test.sh
```

Expected: byte-compile clean, 0 unexpected failures. The new disconnect tests pass. The existing detach, stop, and reattach tests pass unchanged (SC-005).

## 2. Local disconnect and reattach (US1, US2)

1. Start a local zmx-backed Session. Rename it with `r` and pin it with `P`.
2. In the manager, put point on its row and press `d`.
3. Expect: the terminal buffer is gone, the row shows `[disconnected]` with the same number, name, and pin, and point is on the row. The echo area shows `Disconnected zmx session NAME. Press c to reattach`.
4. Run `zmx list --short` in a shell. Expect: NAME is listed.
5. Press `c` on the row. Expect: the terminal shows the earlier Agent output, and the row is live with the same identity.

Live check without UI clicks:

```sh
~/bin/emacsclient --eval '(claude-code-ide-disconnect "SESSION-ID")'
```

## 3. Remote disconnect (US1 scenario 2)

Repeat check 2 on a remote row. Expect the same result under the host heading. Expect no SSH request from Disconnect itself.

## 4. Refusals (US3)

| Action | Expected message |
|---|---|
| `d` on a plain (non-zmx) Session | `Session is not zmx-backed`, and the Session keeps running |
| `d` on a `[disconnected]` row | `Session is already disconnected. Press c to reattach` |
| `d` on a group heading | `No manager session at point` |
| `M-x claude-code-ide-disconnect` in `*scratch*` | `No Session in the current buffer` |

## 5. `M-x` from the terminal (US1 scenario 7)

In a live zmx-backed Session buffer, run `M-x claude-code-ide-disconnect`. Expect the same result as check 2, step 3.

See [contracts/elisp-surface.md](contracts/elisp-surface.md) for all message texts.
