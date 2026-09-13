# Elisp and Interaction Contract: Predefined Manager Layouts

**Feature**: `007-add-layout-presets` | **Date**: 2026-09-12

This contract describes the planned interface.
The new preference does not exist until implementation.
See [data-model.md](../data-model.md) for runtime ownership and persistence details.

## 1. Preset preference

### `claude-code-ide-manager-layout-preset`

| Property | Contract |
| --- | --- |
| Kind | `defcustom` in the manager customization group |
| Default | `magit-left` |
| Accepted values | `magit-left`, `magit-right`, `shell-left`, `shell-right`, `dired-left`, `dired-right` |
| Selection workflow | Existing Emacs customization workflow or user configuration |
| Immediate effects | None on windows, Agent processes, companion processes, or remote access |
| Application points | New default layout or explicit layout reset |
| Saved layouts | Keep their applied arrangement and selected window until reset or unrelated restoration failure |
| Invalid value | Explain the invalid selection, preserve Agent usability, do not silently select another preset |

Example user configuration after implementation:

```elisp
(setq claude-code-ide-manager-layout-preset 'dired-left)
```

This example selects a default. It does not apply the layout immediately.
No new menu, command family, or arbitrary layout registration interface is required.

## 2. Built-in arrangements

| Label | Left content window | Right content window |
| --- | --- | --- |
| Magit left | Configured Git companion, Magit status by default | Agent |
| Magit right | Agent | Configured Git companion, Magit status by default |
| Shell left | Ordinary Ghostel shell | Agent |
| Shell right | Agent | Ordinary Ghostel shell |
| Dired left | Dired for the Session directory | Agent |
| Dired right | Agent | Dired for the Session directory |

The sidebar is outside these two content windows.
The preset does not select or replace the Agent CLI or its Ghostel terminal.
A new layout selects the Agent window unless the invoking manager action requests continued manager focus.

## 3. Existing custom-content preference

### `claude-code-ide-manager-status-buffer-function`

Keep its current function contract: one Session directory argument, returning a usable buffer.
The Magit presets continue to call the captured configured function.
On a remote Session, pass the qualified RPC directory for that exact Session directory.
The default remains the existing Magit provider.

If the function fails or returns no usable buffer, retain the existing Dired fallback for Magit presets.
Shell and Dired presets do not call this function.
Selecting either kind leaves the function setting unchanged.

This preference is temporary compatibility for the current feature.
Whole-layout customization and removal of this preference belong to a later feature.

### Removed orientation preference

Remove `claude-code-ide-manager-session-window-side` from package layout decisions and customization declarations.
Do not provide an alias, migration rule, or fallback to its old value.
An old configuration that sets it no longer controls new layouts or resets.
Users choose `magit-right` explicitly if they want Git on the right.
Existing saved layouts remain unchanged.

## 4. Existing manager commands

### `claude-code-ide-manager-reset-layout-at-point`

The sidebar's existing `R` binding remains the reset action.
It applies the selected preset to the Session at point through the shared reset path.
It does not create an additional Agent Session.

### `claude-code-ide-manager-reset-layout`

Keep the existing public arguments:

```elisp
(claude-code-ide-manager-reset-layout
 SESSION-ID &optional KEEP-MANAGER-FOCUS SCOPE)
```

Resolve the target Session and selected preset before discarding saved layout state or starting companion work.
For a live owned shell, reset reuses the same buffer and process.
For an exited or missing shell, reset to a shell preset creates a new ordinary shell in the Session directory.
Reset to Git or Dired does not create, terminate, or restart an existing shell.

The existing return value remains the selected target window when the action succeeds.
Remote preparation may complete after this return. That does not mean a companion is already ready.
Asynchronous failure reports its error while leaving the Agent window usable.

### `claude-code-ide-manager-switch-to-session`

Keep its existing public arguments and focus policy.
A normal return restores the saved arrangement and selected window when possible.
It must not use the newly selected default to replace a missing or exited saved shell.
Show retained output when available, otherwise restore the remaining layout with the Agent visible.
Explain that an explicit reset to a shell preset starts a replacement.

A saved shell buffer name does not authorize adopting an unrelated buffer with the same name.
A user-closed shell window stays closed on normal restoration if that is the saved arrangement.
Its live process remains available for an explicit shell-preset reset.

## 5. Companion shell lifecycle

A companion shell is an ordinary Ghostel shell associated with one Session.
It has no managed Agent row, CLI startup command, Agent environment injection, or zmx attachment created by this feature.
The Session layer uses Ghostel's existing shell creation and liveness interfaces.

| Action | Required behavior |
| --- | --- |
| First shell-preset layout | Create one shell if the Session has no live companion |
| Mirror shell preset | Move the same live shell to the other side |
| Return to saved live shell | Reuse the same process, output, and current directory |
| Return to saved exited shell | Show available output and reset guidance, no process launch |
| Return to saved missing shell | Keep Agent usable and show reset guidance, no process launch |
| Explicit shell reset without a live shell | Create a replacement in the Session directory |
| Select Git/Dired and reset | Display the chosen non-shell companion, preserve any live shell separately |
| Temporary remote disconnect | Retain ownership for the remembered Session ID |
| Explicit Agent reattachment with that ID | Reuse its live companion if the saved layout displays it |
| Session end or removal | Release ownership without killing the shell or its command |
| Ordinary Emacs shutdown | Preserve existing Emacs/Ghostel behavior, no new process persistence |

Do not force `ghostel-kill-buffer-on-exit` to retain output.
With its default value, the exited buffer normally disappears and the missing-shell case applies.

## 6. Remote access and preparation

Remote companion creation requires the host in both existing admission lists:

- `claude-code-ide-remote-hosts`.
- `claude-code-ide-remote-project-view-hosts`.

Preset selection never adds a host to either list.
Disabled project access retains the existing terminal-only behavior without attempting a companion connection.
Enabled access that fails reports the failure and leaves the Agent usable.

Use `claude-code-ide-remote-project-rpc-directory` to qualify the exact Session directory.
Use the installed RPC client's existing PTY policy and Ghostel's ordinary remote shell preferences.
Do not create a package-specific SSH path, force RPC-only PTYs, or substitute a local terminal.
The existing optional remote project path requires Emacs 30.1 and a compatible RPC client.

Remote Git/Dired views and new shells can appear after preparation because remote access takes time.
The Agent remains usable before they appear.
Completion uses the captured preset and preserves the user's current focus.
It does not read a newer default preference as permission to change the layout.

### Session preparation interface change

Extend the existing Session-managed preparation entry point with a required captured request:

```elisp
(claude-code-ide-remote-project-prepare
 SESSION-ID HOST ATTACHMENT FRAME REASON LAYOUT-REQUEST)
```

`LAYOUT-REQUEST` follows [Captured layout request](../data-model.md#5-captured-layout-request).
Update the manager preparation helper, every Session-managed caller, declarations, and affected tests in the same change.
Do not keep an old-arity compatibility path that silently reads the current global preset.

The request must carry whether it can create a shell.
A reattach or restoration-only path can reuse a live shell, but cannot replace an exited or missing saved shell.
A superseding reset cancels the older request through the existing attempt lifecycle.

### Unchanged explicit Project-view interface

Keep this existing interface and callback result contract unchanged:

```elisp
(claude-code-ide-remote-project-open-target
 HOST DIRECTORY CALLBACK &optional REASON ON-CLOSE)
```

An explicit non-Session Project-view request does not inherit the manager's shell or Dired preset.
It retains its existing Git-provider and approval semantics.
Its internal key construction must still use the new provider-aware key format.
Capture the Git provider when the explicit request starts, not when its worker completes.

### Publication checks

Before adopting or displaying a result, verify:

1. The attempt still owns its Session or explicit target.
2. The exact host remains admitted.
3. The Agent attachment still matches the captured attachment.
4. The frame and captured layout epoch still match the intended display.
5. The captured preset, provider, and directory still match the active layout action.
6. A shell creation result had explicit creation permission.

A stale result cannot overwrite a newer companion or select a window.
If it already started a shell, keep that shell as an ordinary terminal rather than terminate its running command.
It must not enter another Session's shell table.
No cancellation path may close a shared remote connection.

## 7. Failures and recovery

| Condition | Companion outcome | Agent outcome |
| --- | --- | --- |
| Unknown preset | No substituted preset, actionable explanation | Usable |
| Git provider unavailable or unusable | Existing Dired fallback | Usable |
| Dired cannot access requested directory | Explain directory/host problem, no unrelated directory | Usable |
| Ghostel package/module unavailable | Explain missing support, no automatic installation | Usable |
| Shell startup fails | Explain failure, no alternate terminal or local shell | Usable |
| Content split cannot fit | Explain split failure, no unnecessary shell startup | Usable |
| Remote project access disabled | No companion work | Existing terminal-only behavior |
| Enabled remote access fails | Explain unavailable companion | Independent attachment remains usable |
| Saved shell exited or missing | Retained output when available and explicit-reset guidance | Usable |
| Old remote completion arrives | No stale publication or focus change | Current Session remains usable |

Prefer checking split feasibility before starting a new local shell.
If a remote shell starts before its final display becomes impossible, retain it and report where its ordinary buffer remains available.

## 8. Validation references

- [Quickstart](../quickstart.md) defines commands and end-to-end scenarios.
- [Data model](../data-model.md) defines identity, persistence, and state transitions.
- [Plan](../plan.md) identifies affected source seams and required tests.

These documents do not claim that the new interface or layouts are implemented.
