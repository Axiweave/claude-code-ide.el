# User Interface Contract

This contract defines the planned public configuration and manager actions. These new symbols do not exist yet.

## Host Preferences

### `claude-code-ide-remote-project-view-hosts`

- Type: list of exact host strings.
- Default: nil.
- Meaning: permit automatic Project-view preparation on first managed display and explicit preparation through manager `R`.
- Prerequisite: the host must already belong to `claude-code-ide-remote-hosts`.
- No side effect from setting the option itself.

### `claude-code-ide-remote-project-cleanup-hosts`

- Type: list of exact host strings.
- Default: nil.
- Meaning: permit conservative cleanup of feature-owned Magit/Dired view buffers after explicit manager detach.
- Independent of Project-view enablement.
- No side effect from setting the option itself.

The manager declares these options without loading RPC. The feature module loads only when an enabled workflow needs it.

Example for an already approved host:

```elisp
(setq claude-code-ide-remote-project-view-hosts '("approved-dev-host"))
(setq claude-code-ide-remote-project-cleanup-hosts nil)
```

This example does not approve a host, install a package, deploy a server, or change `tramp-default-method`.

Exact strings matter. Two SSH aliases remain separate feature destinations even when SSH resolves them to the same machine.

## Existing Status Provider

`claude-code-ide-manager-status-buffer-function` remains authoritative.

Its existing signature stays unchanged:

```text
DIRECTORY -> live buffer
```

The directory is a proper `/rpc:` remote directory for this feature. A normal provider error or non-buffer result uses the existing Dired fallback.

The default provider uses Magit when available. An accessible non-Git directory uses Dired through the same local fallback policy. Missing Magit is not a failed RPC health check.

A cancellation condition must bypass fallback. Cancellation is not an instruction to try Dired or another remote method.

Custom providers retain their directory-to-buffer contract. Preparation supplies normal no-window controls, not permission to change unrelated windows or start unmanaged background work. A custom buffer does not establish cleanup ownership.

## Manager Actions

| Action | Contract |
|--------|----------|
| First managed display | Show the terminal immediately. Prepare the enabled host's view without a separate command. |
| Bulk attach | Keep the existing no-display behavior. Do not prepare every attached project. |
| Ordinary navigation | Restore surviving view/layout state without automatic remote refresh. |
| `R` — Reset layout | For an attached Session on an enabled host, clear its suppression and supersede its pending attempt. Reset the whole layout and start fresh health. |
| `? C` — Cancel Project-view preparation | Cancel only the selected Session's pending attempt. Do not detach, retry, close the connection, or change preferences. |
| `o` — Open project/worktree | Retain its current project selection and Session start/resume meaning. Do not repurpose it as remote view retry. |
| `K` — Stop | Retain existing confirmation and terminal lifecycle behavior. Do not invoke Project-view cleanup. |
| `D` / `X` — Detach | Retain existing detach behavior. Apply the separate view-cleanup policy only after explicit detach succeeds. |

The new interactive command is `claude-code-ide-manager-cancel-project-view-at-point`.

`C` is a suffix in the manager action menu, not a new direct manager key. Do not reuse `C-g`, which can trigger the RPC client's connection-retirement path.

If no preparation is pending, the cancel command reports that fact and performs no remote work. Local and disabled-host `R` behavior remains unchanged.

## Display and Focus

Use `claude-code-ide-manager-session-window-side` for the existing terminal/status positions. Retain the manager sidebar.

Valid completion can add the view beside the current visible terminal even when the manager or another window has keyboard focus. Preserve the selected window.

Do not rebuild an unrelated layout when a worker finishes. `R` may reset the whole layout because the user explicitly requested that action.

If another Session becomes current, keep the completed buffer available without displaying it over that Session.

## Manual Closure

A user command that dismisses an actually displayed Project-view window suppresses automatic display for that Session. Killing its shared buffer has the same effect only for the initiating Session.

Navigation, reattach, and sibling view creation do not clear suppression. Only manager `R` clears it.

An ordinary Session switch or a result that never appeared is not a close action. No new cross-restart suppression store is introduced.

## Diagnostics

Messages must identify the host and the failed phase when relevant. They must give a corrective action without performing it.

| Condition | Required guidance |
|-----------|-------------------|
| Missing or unsupported local RPC client | Install or update the client separately, then use `R`. Keep the terminal usable. |
| Missing or incompatible selected server | Set up the normally selected server separately, then use `R`. Do not acquire software automatically. |
| Authentication or host-trust prerequisite | Establish credentials or host trust separately. Do not request them from automatic preparation. |
| Health deadline | Report the host and the 30-second health limit. Leave the terminal and shared connection alone. |
| Directory inaccessible | Identify the directory and request a permission/path correction before `R`. |
| Both provider and normal fallback fail | Retain terminal-only display and report the provider/directory problem. |
| Explicit cancellation | Report cancellation without implying that the remote process or connection stopped. |
| Cleanup retains views | Report relevant retained view buffers and their reasons. Do not prompt for saves. |

Do not report an RPC failure merely because Magit is absent. Do not claim an acceleration result without a measured comparison.
