# Data Model: Remote Login Environment

## Remote Launch Configuration Entry

One entry describes fresh Agent creation for one exact configured host.

| Field | Type | Rules |
|---|---|---|
| Host | String | Exact member of the configured remote-host list. Identity is textual. |
| Agent executable | Optional string | Existing field. Nonempty literal with no control characters. A leading hyphen is invalid. |
| Agent arguments | Ordered list of strings | Existing field. Every value is literal and has no control characters. |
| Shell executable | Optional absolute path string | New field. Nonempty, absolute, and free of control characters. It cannot start with a hyphen. |
| Shell arguments | Optional nonempty ordered list of strings | New field. Must appear with the shell executable. Every value is literal and has no control characters. |
| Environment assignments | Optional ordered list of strings | Optional within a shell preference. Each entry is one unique literal `NAME=VALUE`. Names use shell variable syntax and cannot replace zmx identity variables. |

### Identity

The host string is the lookup key. Two SSH names for the same machine have independent entries.

### Relationships

- One configured host has zero or one effective launch entry.
- One launch entry has zero or one shell environment preference.
- A shell preference has zero or more ordered environment assignments.
- A shell preference contains exactly one shell executable and one ordered argument list.
- A fresh sibling launch reads one entry at launch time.
- A remote Worktree operation captures one immutable copy when the request starts.
- No Session, manager row, or persisted manager record owns this preference.

### Validation

1. Validate the host through the existing configured-host check before launch.
2. Reject an improper property list, unknown key, or duplicate key.
3. Validate each environment entry as one unique literal `NAME=VALUE`.
4. Reject environment assignments for `ZMX_SESSION` and `ZMX_SESSION_PREFIX`.
5. Require shell executable and shell arguments when environment assignments appear.
6. Require shell executable and shell arguments together.
7. Require an absolute shell executable path.
8. Require at least one shell argument that makes the selected shell execute the package command argument.
9. Reject control characters in every executable, argument, and environment entry.
10. Copy all strings and lists into the launch specification.
11. Make no remote request while reading user configuration.

The package validates syntax. The remote host determines whether the shell exists and whether its arguments provide the requested startup mode.

## Effective Launch Specification

The launch specification is an immutable launch-time value.

| Field | Type | Source |
|---|---|---|
| CLI type | Symbol | Global Agent selection. |
| Agent executable | String | Host override or standard command name. |
| Agent arguments | Ordered list of strings | Host override or empty list. |
| Environment assignments | Optional ordered list of strings | Exact host preference. |
| Shell executable | Optional absolute path string | Host shell preference. |
| Shell arguments | Optional ordered list of strings | Host shell preference. |

A remote Worktree operation adds its target name, bootstrap token, directory state, and resolved absolute Agent executable. These operation fields do not alter the host preference.

### State Transitions

```text
No shell preference
    │ fresh launch
    └──────────────► Direct launch

Valid shell preference
    │ fresh launch
    └──────────────► Login-environment launch

Malformed preference
    │ launch request
    └──────────────► Rejected before remote creation

Captured Worktree preference
    │ user changes configuration before dispatch
    └──────────────► Operation invalidated before dispatch

Login initialization failure
    │ no direct retry
    └──────────────► Failed launch
```

### Lifecycle Boundaries

- A new launch reads or captures the current preference.
- An existing remote target keeps the environment from its creation.
- Attach and reattach never read the shell preference.
- Removing a preference affects only later fresh launches.
- A failed preference does not mutate manager persistence or another host entry.
