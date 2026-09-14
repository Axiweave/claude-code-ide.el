# Remote Project Picker Contract

## Explicit Remote Open

Command: `claude-code-ide-manager-open-remote`

1. Ask for one currently configured host.
2. Show recent repositories for that exact host in most-recent-first order.
3. Accept an absolute path that is not a remembered candidate.
4. Resolve a remembered label through its candidate value. Do not parse the displayed text.
5. Retry invalid input until the user enters a valid absolute path or cancels.
6. Submit one remote-open request for the selected host and repository.
7. If submission returns an operation ID, move the target to the front of its host history and save manager state.
8. If selection stops or submission signals an error, leave history unchanged.

The command always performs host and repository selection. A manager row or remote Project view does not bypass these prompts.

## Contextual Open

Command: `claude-code-ide-manager-open`

When a selected remote Session or remote Project view supplies an exact host and repository, submit that context directly. Do not add discovery prompts to this command.

## Candidate Rules

- Candidate scope is one exact host.
- Repository paths remain plain strings.
- Paths with spaces remain intact.
- Duplicate repository paths produce one candidate.
- An empty history still accepts an absolute path as minibuffer input.
- The picker does not contact the host.

## Persistence Rules

- History uses existing manager persistence enablement.
- History survives an Emacs restart only when manager persistence is enabled.
- Missing history in older state means an empty history.
- Restore and rendering never authorize an unconfigured host.
- Each host retains at most 20 repositories.
