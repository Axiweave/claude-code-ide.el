---
status: accepted
---

# A Session directory stays bare; TRAMP qualification happens at the edge

A remote Session stores its host and its directory as two plain strings, for
example `alpha` and `/work/topic`. The directory is the path on that host. It
is never a TRAMP file name. Only code that is about to touch the remote
filesystem builds an RPC file name, through
`claude-code-ide-remote-project--rpc-directory`. Everything else treats the
value as metadata text.

## Considered option: store the TRAMP file name in the Session

Storing `/rpc:alpha:/work/topic` would let any caller use ordinary file
primitives without thinking. Rejected: session metadata would then encode the
transport, so a Session could not be listed, grouped, or displayed without a
live connection, and every label would run through
`file-name-handler-alist`. Grouping already avoids that by keying remote
projects as `(host . directory)` in `claude-code-ide--project-key`, and
`claude-code-ide--path-basename` splits the text itself instead of calling
`file-name-nondirectory`.

## Consequences

- Any caller that wants a real file operation must qualify first. Passing a
  bare remote directory to a local file predicate silently asks about the
  local filesystem.
- Callers outside the package must read the host from the Session, not from
  `default-directory`. The terminal buffer of a remote Session sits in
  `temporary-file-directory`.
- Settings that name a local filesystem location are local-only. The
  project-local CLI path is one: it resolves a local project root with no
  host awareness, so from a remote Session terminal it fails with a confusing
  "not in a project" error, and the value it would write names a local
  location that means nothing on the remote host. The transient must refuse
  to write it when the Session has a host. An audit on 2026-09-07 found that
  every supported remote attach path binds `claude-code-ide-cli-path` per
  Session, so a local `.dir-locals.el` value reaching a remote launch is not
  a proven path today.
