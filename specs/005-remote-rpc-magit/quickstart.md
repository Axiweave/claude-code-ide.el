# Quickstart and Acceptance Guide

This guide applies after implementation receives authorization and exists. The planning session did not run these remote scenarios.

Do not use a production host for delay, failure, or missing-server experiments. Use an explicitly approved fixture host.

## Prerequisites

- The package implementation passes its local verification gate.
- The installed RPC client supports the safety contract in [contracts/execution.md](contracts/execution.md).
- The fixture host already belongs to `claude-code-ide-remote-hosts`.
- The operator already installed a compatible server at the client's normally selected path.
- SSH credentials and host trust already exist.
- The fixture contains a Git Worktree, two subdirectories within it, another Worktree, and an accessible non-Git directory.
- The fixture has two attachable Sessions in the first Worktree.
- Magit is available for the Magit case.

Preparation must not create any missing prerequisite. A missing prerequisite should produce guidance and retain the terminal.

## Local Verification Gate

1. Run the repository's required command from the package root.

```bash
./scripts/compile-and-test.sh
```

Expected: successful byte compilation and zero unexpected ERT results.

2. Review failures against the changed observable contracts.
3. Remove temporary experiment scripts after their results are recorded.

Do not run this script in a shared checkout while another user is changing application files. It byte-compiles files in that checkout.

When loading an authorized edit into the user's Emacs, use `emacsclient`, as the local repository instructions require. Do not change the user's RPC package source or default TRAMP method.

## Disabled-Host Control

1. Set both new host options to nil.

```elisp
(setq claude-code-ide-remote-project-view-hosts nil
      claude-code-ide-remote-project-cleanup-hosts nil)
```

2. Open the manager.
3. Refresh its rows and metadata through the existing commands.
4. Bulk-attach fixture Sessions without displaying them.
5. Display an attached remote Session.
6. Detach it through the manager.

Expected: existing terminal-only behavior. No additional RPC client load, health request, provider call, or Project-view cleanup occurs.

## Enabled Git View

1. Enable Project views for the already approved fixture host.

```elisp
(setq claude-code-ide-remote-project-view-hosts '("approved-dev-host")
      claude-code-ide-remote-project-cleanup-hosts nil)
```

2. Confirm that setting the option itself causes no remote request.
3. Attach the two same-Worktree Sessions without displaying them.
4. Display the first Session through the manager.
5. Type in its terminal while preparation runs.

Expected: the terminal works before the Project view appears. Health requires a current server response. Magit appears beside the terminal after successful preparation.

6. Display the second Session from the other subdirectory.
7. Compare the two Sessions' Project-view buffer objects.

Expected: both use the same buffer. Their Session IDs and directory metadata remain unchanged.

8. Display a Session from the other Worktree.
9. Display an equivalent path on another approved fixture host, if available.

Expected: those view identities and buffers remain separate.

## Non-Git and Provider Fallback

1. Display a Session in the accessible non-Git fixture directory.

Expected: Dired opens through the normal provider fallback. Git availability is not a universal RPC health requirement.

2. Repeat in an isolated profile without Magit.

Expected: successful health followed by Dired, not a missing-Magit health failure.

3. Set the existing provider option to `dired-noselect` in the isolated profile.
4. Display a Git Session through `R`.

Expected: the configured provider remains authoritative. The feature does not force Magit or change VC/cache options.

5. Restore the original provider option.

## Focus and Late Completion

1. Start a delayed preparation on the fixture host.
2. Keep the terminal selected until completion.

Expected: the view appears without changing the selected window.

3. Repeat while the manager has focus.
4. Repeat while another existing window has focus.

Expected: the same view appears beside the visible terminal. Completion preserves each selected window and unrelated content.

5. Start preparation for Session A.
6. Switch to Session B before completion.

Expected: A may finish in the background. Its result does not replace B's layout.

7. Return to Session A after completion.

Expected: the surviving view restores without automatic remote refresh.

## Manual Closure and Reattach

1. Display Session A's shared Project view.
2. Dismiss only its Project-view window with `C-x 0`.
3. Navigate away and return to A.
4. Close A's terminal buffer normally, without manager detach.
5. Use manager `c` on A's remembered disconnected row.
6. Display A again.

Expected: A remains suppressed through navigation and reattach. Session B remains free to display the shared view.

7. Use manager `R` on A.

Expected: `R` clears A's suppression, resets the whole default layout, and starts fresh health without restarting the Agent.

8. Kill the shared Project-view buffer while A is current.
9. Display B.

Expected: only A gains suppression. B may recreate the missing view because its own layout still requests it.

10. Start a delayed attempt that has never displayed a view.
11. Switch Sessions before it finishes.

Expected: the switch does not count as manual closure. A never-displayed candidate does not set suppression.

## Cancellation, Supersession, and Health Deadline

Use an operator-controlled delay fixture and an independent RPC consumer on the same host.

1. Start a delayed health attempt.
2. Use manager `? C` on that Session.
3. Use the independent RPC consumer.

Expected: preparation stops without retry or fallback. No later result changes the view or layout. The shared connection remains usable unless it independently fails.

4. Repeat cancellation during identity resolution and initial status preparation.
5. Repeat while another Session waits for the same view writer.

Expected: cancellation schedules no new work for the canceled attempt. Unrelated Sessions and terminal interaction continue.

6. Start a delayed health attempt and let its feature deadline expire.

Expected: the manager reports the host at the 30-second health deadline. The feature does not detach the terminal or retire the shared connection.

7. Run status preparation for longer than 30 seconds after successful health.

Expected: no new fixed status deadline fires. The cancel action remains available.

8. Press `R` twice during a pending attempt.
9. Detach a Session during another pending attempt.
10. Attach that same remote zmx Session again through `M-x claude-code-ide-attach`.
11. Disable the host or remove its approval during another pending attempt.

Expected: old tokens cannot publish. No result affects a newer attachment. Preference changes start no replacement request.

## No Acquisition and Current Health

Observe acquisition entry points in an isolated instrumented test profile. Keep the installed client's normal server selection unchanged.

1. Run a successful attempt with an existing server.
2. Repeat after a normal client reconnect.
3. Repeat against a fixture with the normally selected server missing.
4. Repeat with `auto-deploy` enabled in the user's normal configuration.
5. Repeat with a buffer-local deployment override.

Expected: zero download, build, installation, transfer, deployment, or update calls from every preparation path. Failure retains the terminal and reports separate setup guidance.

6. Compare deployment and SSH configuration before and after the attempt.
7. Run an unrelated RPC operation outside the feature worker.

Expected: global and saved settings remain unchanged. The unrelated RPC operation keeps its normal configuration.

8. Repeat with a live connection and warm metadata caches.

Expected: each fresh attempt still receives its own uncached health response. Cached installation or directory state cannot pass health alone.

## Cleanup Matrix

Enable the independent cleanup option only for the fixture host.

```elisp
(setq claude-code-ide-remote-project-cleanup-hosts '("approved-dev-host"))
```

1. Prepare the buffers listed below.
2. Explicitly detach the owning Session with manager `D` or `X`.
3. Compare live buffer objects after detach.

| Buffer or situation | Expected result |
|---------------------|-----------------|
| Unmodified feature-created Magit/Dired view, known exclusive ownership | Eligible for cleanup. |
| Preexisting Magit/Dired buffer returned by the provider | Retained. |
| Custom buffer with uncertain origin | Retained. |
| Modified feature-created view | Retained with guidance, without a save prompt. |
| Source-file buffer opened from the view | Retained. |
| Another attached Session shares the Worktree from a different subdirectory | Shared view retained. |
| Same-host attached sibling has unknown project identity | View retained conservatively. |
| Another host has the same directory spelling | Its buffers remain unchanged. |
| Old detach snapshot encounters a newer attachment | New attachment and its view remain unchanged. |
| Unknown buffer-local kill or query hook | Retained without running that local hook. |
| Default view in the perspective-enabled user profile | Eligible views close without query prompts. Global perspective hooks still run. |

4. Repeat using generic terminal close, network loss, Stop, and Emacs exit.

Expected: these events do not invoke the new Project-view cleanup policy.

5. Observe remote calls and connection lifecycle during explicit detach.

Expected: cleanup resolves no remote paths, saves no files, and closes no shared RPC connection.

## Completion Evidence

Record the tested client/server versions, host fixture scope, ERT result, and actual manager behavior. Distinguish synthetic transport tests from real-server tests.

The feature is complete only when the specified cases pass. A compiling module, successful local Magit call, or isolated cancellation primitive is not end-to-end acceptance.
