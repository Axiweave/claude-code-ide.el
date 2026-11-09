# Contract: Intake configuration

File: `$XDG_CONFIG_HOME/cci-intake/config.toml`, or the path in `CCI_INTAKE_CONFIG`. The Intake reads it at start. A change needs a restart. An unknown key or a wrong type stops the start with a message that names the key.

```toml
listen = ["127.0.0.1:7311", "100.101.102.103:7311"]
token_file = "~/.config/cci-intake/token"          # mode 0600, one line

[hosts.local]                                       # the Intake machine
max_sessions = 6
[hosts.v12dev]                                      # an SSH destination
max_sessions = 4

[projects.api]
path = "/Users/me/src/api"                          # path on every host in `hosts`
hosts = ["local", "v12dev"]
default_host = "local"
omp = ["omp", "--profile", "work", "--auto-approve"]  # CHILD_ARGV for launch-session
launch_session = ["omp", "launch-session"]          # the command on the host
linear_teams = ["ENG"]
linear_projects = []                                # Linear project names
linear_labels = ["repo:api"]

[followups]
mode = "queue"                                      # queue | guide | stop
prefix = "/omp"                                     # a Linear comment must start with this to become a follow-up

[sources.api]
enabled = true

[sources.linear]
enabled = true                                      # false: still poll and record Triggers, launch nothing (FR-041)
key_file = "~/.config/cci-intake/linear-key"        # mode 0600
trigger_label = "agent"
teams = ["ENG"]
allow = ["<linear user id>"]
poll_seconds = 30                                   # 10..60

[[emacs]]
name = "mac"                                        # matches ?client=mac
ssh = ""                                            # empty: emacsclient runs on the Intake machine
emacsclient = ["emacsclient"]
hosts = { local = "", v12dev = "v12dev" }           # Intake host -> Emacs host; "" means local to that Emacs
```

Rules:

- Each `listen` address must be private: loopback (`127.0.0.0/8`, `::1`), RFC 1918 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), `100.64.0.0/10` (Tailscale), or `fc00::/7`. The Intake refuses `0.0.0.0`, `::`, a host name, and every other address (FR-020).
- `hosts.*` names other than `local`, a non-empty `[[emacs]].ssh`, and each non-empty `[[emacs]].hosts` value must be valid SSH destinations. They must not start with `-` and must not have a space, a control character, `"`, or `\`. The Intake puts a host into a Lisp string in the push form, so this rule is stricter than `claude-code-ide-zmx--valid-host-p` in the package.
- `followups.prefix` must not be empty and must not start with a space.
- `max_sessions` must be at least 2, because one slot stays free (FR-025).
- `projects.*.hosts` must name entries in `[hosts]`. `default_host` must be in `hosts`.
- `projects.*.omp[0]` must have the base name `omp`, for example `omp` or `/Users/me/.bun/bin/omp`. The Intake refuses to start with any other name.
- `[[emacs]].hosts` leaves out an Intake host when that Emacs cannot attach it. The Intake then sends no push for it, and the stream for that client omits `emacs_host`.
- A missing `[[emacs]]` table turns push off. Pull still works.
- Secrets live only in `token_file` and `key_file`, never in this file. The Intake refuses to start when either file is readable by group or other users.
