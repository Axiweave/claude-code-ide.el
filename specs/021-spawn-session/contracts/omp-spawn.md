# Contract: omp Commands, Tool, and Setting

## `/spawn <request>`

1. If `ZMX_SESSION` is unset, show "spawn needs a zmx session" and stop (FR-020).
2. If the shared child builder finds `--api-key` in A's argv, show the `/fork` refusal text and stop (FR-020).
3. If another guided command is running, refuse with its name. If a spawn window is already open, refuse with a warning. A second window would close when the first spawn call runs, so its kickoff would have no spawn tool.
4. Open the spawn window (`data-model.md`). Send a hidden kickoff prompt rendered from `OMP/src/prompts/spawn/spawn-kickoff.md` with the request. While a turn is running, queue the kickoff with `followUp`.

## Tool `spawn_session` (hidden)

- **Allowed**: only while the spawn window flag is set (`isToolAllowed`). The spawn handler is always set in interactive mode, so the tool works whenever it is in the tool set (FR-018). Without a handler, as in print or RPC mode, the tool throws `ToolError`.
- **Arguments**: see `data-model.md` "Spawn request".
- **Steps**:
  1. If a `spawn_session` call already ran in this agent run, refuse (SC-008). The check runs before the first `await`, so parallel calls in one message create one session. Then validate the arguments. A fork mode with no saved session file is a refusal (FR-020).
  2. If `spawn.confirm` is true, call `showHookConfirm` with the mode, the directory, and the start content, with "No" as the default. A "no" returns "Spawn declined" and creates nothing.
  3. With `new_worktree`, call `createSessionWorktree(cwd, settings, branch, { keepChanges: true })`. Never call `cleanSourceCheckoutIfConfigured`.
  4. For `handoff_summary`, call `session.generateHandoffDocument(text)`.
  5. Write the start content to a mode-0600 temp file.
  6. Build the argv with the shared builder, and pass `model` when the call sets it. The CLI entry is the executable of A's own zmx `cmd=`, so Emacs accepts B's command (FR-011). Run `zmx attach --labels … NAME …argv` (research D9).
  7. On a non-zero exit: run `zmx kill NAME` without a check. If step 3 made a worktree, remove it and its branch with `removeSessionWorktree(wt, false)`. Show the error and return it as a `ToolError`. Send no announcement.
  8. On success: write the announcement, then return `Spawned <NAME> in <dir> (<mode>)`. That text is A's record of the spawn.
- The window closes at this call, whatever the result.

## `/despawn`

1. If `ZMX_SESSION` is unset, show "no children: this Session is not in zmx" and stop.
2. List the children (`contracts/zmx-labels.md`). If none, show "no child Sessions" and stop.
3. Pick one with `showHookSelector`. The label is the name, and the description is the `cwd`.
4. With a full worktree record and `worktree.onExit` not `keep`: `state = inspectSessionWorktree(wt)` and `action = decideWorktreeExit(policy, state)`. With no record, or with `keep`, the action is `keep`.
5. Show one `showHookSelector` confirmation. Its title names the target. When `cci-state=working`, the title adds "It is working on: <cci-work>", or "It is working on a turn." when `cci-work` is empty. The options depend on the action:
   - `keep`: "End <NAME>", "Cancel".
   - `remove`: "End <NAME> and remove its worktree", "Cancel".
   - `prompt`: "End <NAME> and remove its worktree", "End <NAME> and keep its worktree", "Cancel". The title also shows `describeWorktreeRisk(wt, state)`.

   "Cancel" is the default. "Cancel" or an aborted dialog ends nothing. This one dialog is the remove confirmation of FR-015 and FR-024.
6. If the user chose a removal: `plan = planWorktreeExit([wt], "remove", async () => true, warn)`. Step 5 already gave the approval. Otherwise the plan is empty.
7. `zmx kill NAME`. Show any error and stop. Do not touch the worktree after an error.
8. `removeExitWorktrees(plan)`, and show its messages. It keeps the worktree when the fingerprint changed after step 6.

## Setting

```ts
spawn.confirm: boolean = false
```

## B side

When `OMP_SPAWN_PARENT` and `ZMX_SESSION` are set, InteractiveMode runs `zmx set $ZMX_SESSION cci-state=working cci-work=<text>` at the first `message_start` of a run, and `zmx set $ZMX_SESSION cci-state=idle cci-work=` at `agent_end`. It skips messages that are not user or assistant messages. `<text>` is the base64url form of the first line that is not only a tag, at most 80 characters. It does not wait for the result.
