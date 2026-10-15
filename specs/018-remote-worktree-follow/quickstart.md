# Quickstart: Remote Worktree Follow

**Feature**: `018-remote-worktree-follow` | **Date**: 2026-10-15

## Prerequisites

- A host in `claude-code-ide-remote-hosts` with an RPC method (for example
  `v12dev`).
- A Git repository on that host with one linked worktree on another branch.
- Oh My Pi on the host with `terminal.reportCwd` on.

## 1. Batch gate

```sh
./scripts/compile-and-test.sh
```

Expected: 0 unexpected results. The new and rewritten tests follow
[contracts/elisp-surface.md](contracts/elisp-surface.md) invariants 1 to 7.

## 2. Live smoke: the row follows a move (User Story 1)

1. Load the changed files in the running Emacs with `emacsclient`.
2. Start or reattach a remote omp Session in the main worktree.
3. In the Agent, run `wtmove` to the linked worktree.
4. Check the Session record:

   ```sh
   ~/bin/emacsclient --eval '(let (r) (maphash (lambda (_ s) (when (claude-code-ide-session-host s) (push (list (claude-code-ide-session-directory s) (plist-get (claude-code-ide-session-group-metadata s) :branch)) r))) claude-code-ide--sessions) r)'
   ```

Expected: the directory is the bare worktree path, and the branch is the
worktree branch within 5 seconds. The sidebar row is in the same group.

## 3. Live smoke: restart (User Story 2)

1. Restart Emacs.
2. Look at the disconnected row. Expected: the worktree path.
3. Press `c` on the row. Expected: the Session attaches in the worktree and
   keeps its number.

## 4. Live smoke: views (User Story 3)

1. Open the Session layout with a Magit preset before the move.
2. Move the Agent. Switch to another Session, then back.
   Expected: the same Magit buffer on the old worktree, with no error.
3. Press `R` on the row. Expected: Magit on the new worktree.
