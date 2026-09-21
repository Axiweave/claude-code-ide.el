# Research: Remote Current-File References

## Scope and Evidence

Research covered the current-file command, every shared formatter caller, Session metadata, RPC identity parsing, and existing reference tests. Two read-only research agents investigated identity handling and command/test contracts independently. The parent checked their recommendations against source and runtime evidence.

This phase does not reproduce the user-reported failure again or modify runtime code. The user report establishes the failure. Runtime probes below evaluate the proposed path operations only.

## Decision 1: Convert at the Existing Reference Formatter

**Decision**: Extend `claude-code-ide--file-reference-path` with an optional `remote-aware` argument. Only `claude-code-ide-send-current-file` passes a non-nil value.

**Rationale**: The formatter already owns relative-versus-absolute selection. Its other direct caller, `claude-code-ide-send-file`, must retain its current contract under the specification’s scope restriction. Superseded by spec 015, which removes that restriction.

The optional argument represents two required policies, not future flexibility. It defaults to the unchanged behavior for file-picker actions. Current-file local behavior also remains unchanged.

**Alternatives considered**:

- Changing every formatter caller automatically would expand the requested scope.
- A second complete formatter would duplicate path selection and project fallback.
- Changing the transient menu or insertion transport would put conversion outside its existing owner.

**Evidence**: `claude-code-ide.el:414-429`, `:2972-3019`, and `claude-code-ide-transient.el:809-813`. A repository search found two direct formatter call sites. The separate `#` command does not call this formatter.

## Decision 2: Reuse the Exact Approved RPC Destination Parser

**Decision**: For the remote-aware branch, reuse `claude-code-ide-remote-worktree-target-for-file` for RPC source identity and host-local path extraction. Load its existing package module optionally at this feature boundary and report unavailability before sending.

**Rationale**: The parser already matches exact configured destination strings, validates the path, rejects ambiguous matches, and performs no remote I/O. A new regular expression or host-only comparison would create a second identity convention.

Compare the parser’s `:host` value with `claude-code-ide-session-host` using `equal`. Do not use manager wrappers for a remembered target. The reference action resolves a live Session buffer and already retrieves its Session object.

**Alternatives considered**:

- `file-remote-p` and `file-local-name` correctly decode the reported simple hostname, as the live probe confirms. A host-only comparison can discard destination details and bypass the existing approved-route policy.
- Moving or renaming the exported parser would expand this change across Worktree callers without changing the required behavior.
- Resolving SSH aliases, users, ports, or jump hosts would require a new identity policy and potentially external work.

**Limits**: Match the exact configured RPC destination, including any destination text already accepted by the existing parser. SSH configuration owns authentication, ports, and jump hosts. Do not infer equivalence between aliases. Other remote routes cannot establish compatibility under this package’s existing RPC policy and produce an explicit error.

**Evidence**: `claude-code-ide-remote-worktree.el:175-192`, `claude-code-ide-zmx.el:64-95`, and ADR 0003. Configured destinations are strings. They are not restricted to bare DNS hostnames by the validator.

## Decision 3: Keep Session Directories Bare and Conversion Lexical

**Decision**: Use the Session’s existing `host` and `directory`. For compatible remote context, compute a relative path from the extracted host-local filename to the bare Session directory.

Normalize only as text with `file-name-handler-alist` bound to nil and `default-directory` bound to `/`. Use existing Emacs path operations, not filesystem predicates or `file-truename`.

An absolute, nonempty, unqualified Session directory is required. A relative result of `..` or one starting with `../` selects the host-local absolute filename instead. Do not return the original RPC filename for outside-directory files.

**Rationale**: ADR 0003 defines the Session directory as metadata on its host. Remote terminal `default-directory` is a local temporary directory and cannot supply the reference base.

**Alternatives considered**:

- Storing an RPC filename in the Session conflicts with ADR 0003.
- Using the source project root can produce a path that the receiving Session resolves incorrectly.
- Filesystem containment checks or symlink resolution add I/O to a text-formatting operation.

**Evidence**: `CONTEXT.md`, ADR 0003, and `claude-code-ide.el:420-429`.

## Decision 4: Fail Before Reference Delivery

**Decision**: Reject mismatched hosts, local/remote mismatches, unknown remote targets, unsupported remote routes, and missing or invalid remote Session directories before `claude-code-ide--send-reference-body` runs.

**Rationale**: Removing the prefix without checking identity can silently refer to another file. A visible prompt buffer does not establish a remote destination.

Keep local project fallback, source context selection, selection suffix formatting, insertion whitespace, prompt preference, and terminal delivery unchanged.

**Alternatives considered**: Sending an absolute filename across hosts still names the wrong filesystem. Guessing a host from the terminal directory conflicts with ADR 0003.

**Evidence**: `claude-code-ide.el:407-453`, `:2931-3001`.

## Decision 5: Test Observable Command Behavior

**Decision**: Extend existing ERT command tests in `claude-code-ide-tests.el`. Call the real current-file action and inspect its inserted or sent reference. For rejection cases, assert `user-error` and no delivery.

**Rationale**: A test of path string manipulation alone cannot catch a missing opt-in at the public command. The existing tests already create temporary source and Session buffers and intercept terminal delivery.

Use isolated Session registries and temporary buffers. Exercise the real RPC parser with configured test destinations without installing RPC or opening connections. Bind a failing handler for bare-path operations to catch accidental filesystem dispatch where practical.

**Coverage**: The reported selected-line case, same-host outside-directory and sibling-prefix cases, incompatible contexts, missing directory/target, and existing local behavior. Preserve existing selection and source-context tests instead of duplicating them. Add a compatibility case for file-picker behavior if the changed helper could alter it.

**Alternatives considered**: Full live-remote tests alone cannot run in batch mode without optional dependencies. Helper-only tests miss the public command contract.

**Evidence**: `claude-code-ide-tests.el:13678-13748` and the existing `claude-code-ide-test-send-current-file-` test family.

## Runtime Probe Results

The parent ran a batch Emacs documentation/path probe and two read-only `emacsclient --eval` probes.

Observed source decomposition:

```text
host: "v12mac"
localname: "/Users/yufu/v12x/packages/core/lib/executor.ts"
```

Observed bare-path calculations:

```text
base /Users/yufu/v12x/:          "packages/core/lib/executor.ts"
base /Users/yufu/v12x/packages/: "core/lib/executor.ts"
outside file:                   "../notes.txt"
sibling directory:              "../v12x-other/a.ts"
```

The selected parser also loaded in `emacs --batch -Q` without optional packages. With two configured destinations, its actual outputs were:

```text
(:host "v12mac" :directory "/Users/yufu/v12x/packages/core/lib/executor.ts")
(:host "user@v12mac" :directory "/work/a.ts")
```

This confirms that reuse preserves exact destination text rather than comparing only the hostname.

Emacs documents that `file-remote-p` never opens a new remote connection. These results support lexical conversion and the outside-directory decision. They do not prove that the current-file command is fixed.

The direct source review also corrected two research suggestions: MCP at-mention is not this transient action, and remembered manager targets are not its target interface.

## Resolved Unknowns

All planning unknowns are resolved: conversion owner, caller scope, remote identity policy, directory representation, dependency loading, error behavior, and verification approach. No new dependency, schema, connection workflow, or configuration is required.
