# Quickstart: Validate Remote Current-File References

This guide validates current-file reference behavior. Path probes alone do not prove the complete command.

## Prerequisites

- Use Emacs 28.1 or later with this checkout available.
- For live validation, use the existing Emacs server and configured `v12mac` remote Session.
- The remote Session directory must be `/Users/yufu/v12x` for the reported example.
- Enable the existing RPC file integration and Ghostel terminal support through normal user configuration.
- Do not install dependencies, approve hosts, or create remote Sessions as part of this check.

## Read-Only Path Probe

Run this command in the repository terminal:

```bash
emacsclient --eval '(let* ((file "/rpc:v12mac:/Users/yufu/v12x/packages/core/lib/executor.ts") (host (file-remote-p file (quote host))) (path (file-local-name file)) (file-name-handler-alist nil) (default-directory "/")) (list host path (file-relative-name path "/Users/yufu/v12x/")))'
```

Expected values:

```text
("v12mac" "/Users/yufu/v12x/packages/core/lib/executor.ts" "packages/core/lib/executor.ts")
```

This probe does not send a reference or open a new remote connection. Research ran equivalent host extraction and relative-path probes successfully.

## Automated Command Validation

Run the focused reference tests from the repository root.

If batch Emacs cannot find installed dependencies, set `CCI_REQUIRED_LOAD_PATH` to their colon-separated directories.
Include the required libraries and their installed dependencies.
Keep the trailing colon below so Emacs retains its standard library path.

```bash
export EMACSLOADPATH="${CCI_REQUIRED_LOAD_PATH}:"
```

Use `emacsclient --eval '(locate-library "with-editor")'` to locate an installed library.
The complete gate also attempts its existing dependency discovery.

```bash
emacs -batch -L . --eval '(setq load-prefer-newer t)' -l ert -l claude-code-ide-tests.el \
  --eval '(ert-run-tests-batch-and-exit "claude-code-ide-test-send-\\(current-file\\|file\\)")'
```

New regression cases:

- `claude-code-ide-test-send-current-file-remote-selected-line`
- `claude-code-ide-test-send-current-file-remote-rejects-context`
- `claude-code-ide-test-send-current-file-remote-containment`
- `claude-code-ide-test-send-current-file-without-remote-module`
- `claude-code-ide-test-send-file-preserves-remote-target-policy` (superseded by spec 015; replaced by `claude-code-ide-test-send-file-remote-target`)

Expected result: zero unexpected results, including the reported reference, context rejection, directory containment, and existing local command behavior.

Format only the changed Elisp files, then run the complete implementation gate:

```bash
./scripts/format-and-clean.sh claude-code-ide.el claude-code-ide-tests.el
./scripts/compile-and-test.sh
```

Expected result: successful byte compilation and zero unexpected ERT results. Do not treat the planning probes as a substitute.

## Live Validation

1. After successful verification, reload the changed source file through the existing Emacs server.

   ```bash
   emacsclient --eval '(load (locate-library "claude-code-ide.el"))'
   ```

   Make sure this checkout takes precedence in the live Emacs `load-path`.

2. Display the intended remote Agent Session beside the source file.
3. Make sure no unrelated Session or prompt buffer can receive the reference.
4. Open `/rpc:v12mac:/Users/yufu/v12x/packages/core/lib/executor.ts` through the existing file workflow.
5. Select line 316.
6. Invoke the transient `@` action.
7. Inspect the inserted reference before submitting an Agent prompt.

Expected body:

```text
@packages/core/lib/executor.ts#L316
```

Do not press Enter to submit the Agent prompt for this validation. An automated assistant must obtain authorization before it inserts text into a real Agent Session.

Repeat the no-selection and multi-line cases in the [acceptance matrix](contracts/current-file-reference.md). Use the matrix for outside-directory, nested-directory, and incompatible-context checks.

For a context error, verify that no text reaches either a prompt buffer or the terminal. Verify that the Session remains connected.

For a non-submitting live check, display a temporary prompt buffer beside the source and intended Session.
Use the existing prompt-buffer preference to receive the reference there.
Confirm the exact body in that buffer, then restore the previous windows and remove only the temporary buffer.
This exercises the real command and prompt insertion without sending text to the Agent terminal.
Record the destination so this check cannot be mistaken for terminal-send verification.

## Compatibility Checks

1. Exercise the existing local relative-path and outside-project reference scenarios.
2. Exercise a file-browser source and a Session-buffer source.
3. Exercise the separate `#` action and the file-picker actions.
4. Compare each output with its existing contract.

Use existing automated coverage for these cases where available. Do not create extra remote resources solely to repeat equivalent cases.

## Evidence to Record

- Focused ERT result and complete gate result.
- Exact reference body from the reported live case.
- No insertion on incompatible or incomplete remote context.
- Confirmation that local behavior and other command contracts remain unchanged.

See [data-model.md](data-model.md) for ownership and validation rules.

## Implementation Evidence — 2026-09-13

- The new selected-line regression failed before the fix with `@/rpc:v12mac:/Users/yufu/v12x/packages/core/lib/executor.ts#L316 `.
- After the fix, the final focused command passed all 25 tests with zero unexpected results.
- The formatter ran with explicit `claude-code-ide.el` and `claude-code-ide-tests.el` arguments.
- The complete gate passed byte compilation and ran 890 tests: 876 expected results, zero unexpected results, and 14 skipped tests.
- Compilation reported warnings, including the test debug macro replacement and obsolete macros in installed dependencies. Native compilation was not requested.
- The verified runtime source was reloaded through `emacsclient`. The test file was not loaded into live Emacs because it replaces runtime functions with mocks.

The live check used the existing `executor.ts` buffer and Session `*claude-code[v12x@v12mac]*`.
It called the interactive current-file action behind transient `@` and used the existing prompt-buffer preference.
A temporary local prompt received these exact strings, including the normal trailing space:

```text
"@packages/core/lib/executor.ts#L316 "
"@packages/core/lib/executor.ts "
"@packages/core/lib/executor.ts#L316-320 "
```

The check used the real Source File, Session metadata, RPC parser, selection formatter, and prompt insertion.
It did not submit an Agent prompt or send text to the Agent terminal.
Terminal delivery behavior has automated coverage, not a live terminal-send claim.

The check restored the window configuration and removed its temporary prompt buffer.
A separate inspection confirmed zero remaining smoke buffers and a live target Session.
No runtime source changes followed these successful checks.

### Final Review Verification

The local dependency regression now checks that local references never request the remote module.
Its remote case confirms that unavailable remote support raises an error before delivery.
The retained public prompt-insertion test checks actual buffer contents and rejects terminal delivery.

After these test and portability corrections, the complete gate passed again: 876 expected results, zero unexpected results, and 14 skipped tests.
This run supplied installed dependency directories through `CCI_REQUIRED_LOAD_PATH` and the documented trailing-colon `EMACSLOADPATH` convention.
