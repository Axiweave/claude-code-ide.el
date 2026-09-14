# Tasks: Attached-Editor Handoff for Oh My Pi

**Input**: Design documents from `specs/010-attached-editor-handoff/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: The constitution requires a batch-verifiable ERT gate. The plan names the Agent `bun test` cases and the package ERT cases. Each story below lists its tests before its code.

**Organization**: Two repositories. The Agent (`~/agents/oh-my-pi`, `packages/coding-agent`) lands first because the package is verified against it. Paths below are relative to each repository root. `A:` marks the Agent, `P:` marks the package.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (attached Emacs edits), US2 (local unchanged), US3 (fallback), US4 (other editor entries)

---

## Phase 1: Setup

- [X] T001 Confirm `bun test` passes on a clean checkout of `~/agents/oh-my-pi/packages/coding-agent` and `./scripts/compile-and-test.sh` passes on this repository (baseline before any edit).

---

## Phase 2: Foundational (Agent protocol, blocks every story)

**Purpose**: The packet and OSC contract that every story uses. See `contracts/terminal-editor-protocol.md` and `data-model.md`.

- [X] T002 A: In `src/modes/composer.ts`, add the listener cases `pi:editor-open;NONCE` and `pi:editor-submit;NONCE` (call `armEditorOrigin(nonce)`, `consume: true`) and `pi:editor-ack;ID`, `pi:editor-done;ID`, `pi:editor-cancel;ID` (resolve the pending request by id, ignore a stale id, `consume: true`). Keep the existing unknown-`pi:` consume.
- [X] T003 A: In `src/utils/external-editor.ts`, add the origin slot: `armEditorOrigin(nonce)` stores the nonce for exactly the next input event, `takeEditorOrigin()` returns it once, and the composer listener clears the slot synchronously on any non-marker input event that is not the expected raw key (`StdinBuffer` can deliver several events in one `process` call, so the clear cannot be deferred).
- [X] T004 A: In `src/utils/external-editor.ts`, implement `openInEditor(ui, content, { origin, apply?, ... })` per plan.md "Flow inside the helper" steps 1-8: synchronous single-flight slot (return `null` when busy), temp file, OSC 52;e request write, 500 ms ack timer, keep the TUI started while pending, `await apply(text)` before `ui.start()` or resolution, `\x03` consumed as cancel in both the offered and accepted states, fallback to `$VISUAL`/`$EDITOR` with `ui.stop()` only on that path, file removal and slot release in `finally`.
- [X] T005 A: Route a `\x03` to the pending request before the ordinary Ctrl-C handling. Done in `handleEditorInput` (the first input listener, `src/modes/composer.ts`), which consumes the byte while a request is pending, so `handleCtrlC` never sees it and needs no change. Covered by the `ctrl+c` cases in T006.
- [X] T006 [P] A: Tests in `test/external-editor.test.ts` (existing file) with a fake host, one case per outcome in quickstart.md section 1: ack then done returns file text and awaits `apply`; no ack with no editor returns `undefined`; no ack with an editor spawns it and awaits `apply` before `ui.start()`; cancel returns `null`; stale id ignored; `ctrl+c` before ack and after ack both return `null`, keep the draft, and never reach `handleCtrlC`; `ctrl+c` with no pending request passes through; second entry while pending returns `null` without a file or packet; 64 KB mixed-content round-trip identical on both paths apart from the trailing-newline option; deferred async `apply` sees no `ui.start()` and no render before it settles; empty origin skips the offer.
- [X] T007 [P] A: Tests in `test/modes/composer-editor-handoff.test.ts` through a real `Composer` on a `VirtualTerminal`: `editor-open` marker plus `\x07` arms the nonce, is consumed, and `\x07` still reaches the editor; `editor-submit` plus `\r` reaches the editor with the origin available; marker plus an ordinary character plus `\x07` yields an empty origin; the nonce is gone at the event after the key; a plain `\x07` yields an empty origin; the existing `pi:prompt` packet still works.

**Checkpoint**: `bun test` green. The Agent answers the protocol but no caller uses it yet.

---

## Phase 3: User Story 1 - Edit a Prompt in the Emacs That Is Attached Now (Priority: P1) 🎯 MVP

**Goal**: `C-g` in a Ghostel terminal-input mode opens the composer prompt in the Emacs that pressed the key, local or remote.

**Independent Test**: spec.md User Story 1 Independent Test, quickstart.md section 4.

### Agent

- [X] T008 [US1] A: Migrate the composer caller in `src/modes/controllers/input-controller.ts` (`:2418-2438`): capture `const origin = takeEditorOrigin() ?? ""` as the first synchronous statement of the key entry, remove the pre-call `ui.stop()` and `getEditorCommand()` guard, move the code between editor return and `ui.start()` into the `apply` callback, and delete that post-await code from the caller. `apply` is the only application point. The return value is a status only.

### Package: key command and nonce

- [X] T009 [US1] P: In `claude-code-ide-session.el`, add the per-process `claude-code-ide-session--editor-nonce` (random, created on first use) and the shared helper that looks up the shadowed binding with `emulation-mode-map-alists` bound to the current list minus `claude-code-ide-session--emulation-mode-map-alist` only. (Plan change: per-process, not per-buffer; the spec's client is one Emacs process.)
- [X] T010 [US1] P: In `claude-code-ide-session.el`, make the public `claude-code-ide-session-send-control-g` send `ESC _ pi:editor-open;NONCE ESC \` + `\x07` in one `claude-code-ide-session-send-string` (after clearing `quit-flag` and deactivating the mark) when `(claude-code-ide--current-cli-type)` is `omp`, else the raw `ghostel-send-C-g`. Add `claude-code-ide-session-send-control-g-marked` (`C-g`): when the shadowed binding is `ghostel-send-C-g` in an omp Session call that command; otherwise `call-interactively` the shadowed binding. Install with a top-level `define-key` on the existing emulation map, outside the `defvar` initializer (`:98-105`). (Plan change: the marker lives in the public command so user wrappers around it get it.)

### Package: request handler

- [X] T011 [US1] P: In `claude-code-ide-session.el`, add `claude-code-ide-session-editor-request (request-id nonce path)` per `contracts/emacs-session-editor.md`: return nil silently when `claude-code-ide--session-for-buffer` is nil or the nonce differs; remote preflight `(or (fboundp 'claude-code-ide-remote-project-open-file) (and (require 'claude-code-ide-remote-project nil t) (fboundp 'claude-code-ide-remote-project-open-file)))`, host in `claude-code-ide-remote-hosts`, `claude-code-ide-remote-project-target-available-p`, each failure a `user-error`; send `pi:editor-ack;ID` via `claude-code-ide-session-send-omp-packet` before the visit; local visit by deferred `find-file-noselect`; visit failure after ack sends `pi:editor-cancel;ID` and one message.
- [X] T012 [US1] P: In `claude-code-ide-session.el`, in the visited buffer enable `with-editor-mode`, display it, add buffer-local `with-editor-post-finish-hook` sending `pi:editor-done;ID` and `with-editor-post-cancel-hook` sending `pi:editor-cancel;ID` (both run after `with-editor-return` saves, `with-editor.el:355-364,374-397`); register the dispatcher once under `with-eval-after-load 'ghostel` with `(add-to-list 'ghostel-eval-cmds '("claude-code-ide-session-editor-request" claude-code-ide-session-editor-request))`.
- [X] T013 [US1] P: In `claude-code-ide.el` `claude-code-ide--find-prompt-buffer` (`:357-372`), match on `(or (file-remote-p name 'localname) name)`.

### Package: remote open

- [X] T014 [US1] P: In `claude-code-ide-remote-project.el`, add public `claude-code-ide-remote-project-open-file (host path callback)` beside `claude-code-ide-remote-project-open-target` (`:1459-1504`) with the same guards (`claude-code-ide-zmx--validate-host`, `target-available-p`, absolute `path`), a new attempt field `file`, one worker branch (`:1296-1345`) that after the health check calls `find-file-noselect` on `(concat (claude-code-ide-remote-project-rpc-directory host (file-name-directory path)) (file-name-nondirectory path))` under `inhibit-interaction`, then `run-at-time 0` a new `--finish-file-success` that rechecks `--attempt-current-p` and calls `callback` once with `(:status completed :buffer B)` or via `--finish-failure` `(:status failed :error E)`. No view registry, no publication. Existing 30 s deadline and cancel apply.
- [X] T015 [US1] P: Wire T011's remote path to T014: on `completed` run T012's visit on the returned buffer; on `failed` send cancel and one message.

### Package: ERT

- [X] T016 [US1] P: In `claude-code-ide-tests.el`, add the cases from plan.md "Verification Design" for this story: non-Session buffer returns nil silently; nonce mismatch returns nil; matching nonce local Session sends ack, visits with `with-editor-mode`, post-finish sends done, post-cancel sends cancel, neither pre hook sends; remote host missing from `claude-code-ide-remote-hosts` signals `user-error` with no ack; remote feature unavailable and feature-provided-but-function-unbound each signal `user-error` with no ack; remote completed callback visits the RPC file name; admission removed while the worker runs yields `:failed` and cancel; post-ack visit failure sends cancel and leaves no buffer; `find-prompt-buffer` matches a remote name by localname; key command in an omp char-mode buffer sends marker plus `\x07` in one string.

**Checkpoint**: quickstart.md sections 2 and 4 pass. Reload order: `claude-code-ide-remote-project.el`, then `claude-code-ide-session.el`, then `claude-code-ide.el`, then the `lookup-key` assertions.

---

## Phase 4: User Story 2 - Keep the Local Workflow Unchanged (Priority: P2)

**Goal**: A local Session behaves as today. Non-omp CLIs, Ghostel line mode, copy mode, and Evil states keep their own keys.

**Independent Test**: spec.md User Story 2 Independent Test, quickstart.md section 3.

- [X] T017 [US2] P: In `claude-code-ide-tests.el`, add the shadowed-binding cases: line mode (`ghostel-line-mode-send-or-open-link`), copy mode, Evil normal state, and a non-omp buffer each run the shadowed binding and send no marker; the same Session viewed in two windows of one Emacs opens exactly one prompt buffer.
- [X] T018 [US2] P: In `claude-code-ide-tests.el`, add the two-Emacs case: a request carrying another client's nonce is ignored (nil, nothing sent). Note: the nonce is per Emacs process, not per Session buffer. A request only ever arrives on its own Agent's pty, into that Session's Ghostel buffer, so two Sessions in one Emacs cannot receive each other's requests; the nonce only separates two Emacs clients on one shared terminal.
- [X] T019 [US2] A: Verify by `bun test` that the composer caller without a marker (empty origin) reaches the fallback within the 500 ms window with the draft intact, then run the local scenario in quickstart.md section 3 through `emacsclient`.

**Checkpoint**: Local `C-g` opens the prompt in the current window with the existing finish and cancel keys.

---

## Phase 5: User Story 3 - Fall Back Outside Emacs (Priority: P3)

**Goal**: A plain terminal or no attached client gets the configured external editor or the existing warning within one second. The Session never hangs.

**Independent Test**: spec.md User Story 3 Independent Test, quickstart.md section 5.

- [X] T020 [US3] A: In `src/utils/external-editor.test.ts`, add the US3 cases beside T006: no ack with an editor configured spawns it after `ui.stop()` and restarts in `finally`; no ack without an editor returns `undefined` and the composer caller shows the existing "No editor configured" warning; the fallback decision lands within the 500 ms window with no client attached.
- [X] T021 [US3] Manual, from a plain terminal attached through zmx: (a) quickstart.md section 5 with `$EDITOR` set, expect the editor within one second; (b) unset `$VISUAL`/`$EDITOR`, press `C-g`, expect the existing "No editor configured" warning and a responsive composer; (c) detach every client, trigger `/todo edit` through a scripted write to the zmx session, reattach, expect the fallback ran and the Session did not hang. Result: all three passed live in iTerm through the computer-use tool (`/tmp/cc-handoff`, Sessions `cc-handoff-b`/`cc-handoff-c`); (c) needed the text and CR in one `zmx send` payload because a bare CR alone is held by the raw-paste classifier.

**Checkpoint**: SC-004 holds: editor or warning within one second.

---

## Phase 6: User Story 4 - Other Prompt Editors Follow the Same Path (Priority: P4)

**Goal**: Plan, plan annotation, todo, and hook editors use the same handoff from a Ghostel terminal-input mode.

**Independent Test**: spec.md User Story 4 Independent Test, quickstart.md section 8.

### Agent: submit origin for commands

- [X] T022 [US4] A: In `src/slash-commands/types.ts`, add `editorOrigin?: string` to `TuiSlashCommandRuntime` (`:111-117`, beside `draftDetached`).
- [X] T023 [US4] A: In `src/modes/controllers/input-controller.ts`, capture `const editorOrigin = takeEditorOrigin() ?? ""` as the first statement of `onSubmit` (`:854`) and of `handleFollowUp` (`:1616`) and pass it as `editorOrigin` to both `executeBuiltinSlashCommand` callers (`:961`, `:1644`). The follow-up key is not Return, so its origin is empty unless a user binds it to a marked key.
- [X] T024 [US4] A: In `src/modes/types.ts` (`:416`) change the signature to `handleTodoCommand(args, origin)`; in `src/slash-commands/builtin-session.ts` (`:174`) forward `runtime.editorOrigin ?? ""`; in `src/modes/interactive-mode.ts` (`:6310`) accept and forward the origin.

### Agent: caller migrations

- [X] T025 [P] [US4] A: Migrate the plan and annotation callers in `src/modes/interactive-mode.ts` (`:4302-4339`, `:4349-4360`): capture the origin before the file read that precedes the helper, remove the pre-call `ui.stop()` and editor-command guard, move the `Bun.write` and render into `apply`, and delete that post-await code. The return value is a status only.
- [X] T026 [P] [US4] A: Migrate `src/modes/controllers/todo-command-controller.ts` (`:410-445`): `#editInExternalEditor(origin)` passes the origin and moves the parse, commit, report, and render into `apply`, deleting that post-await code. The return value is a status only.
- [X] T027 [P] [US4] A: Migrate `src/modes/components/hook-editor.ts` (`:248-272`): pass the origin, move the `#disposed` check and the apply into `apply`, delete that post-await code, keep silent on `undefined` as today.

### Package: submit key

- [X] T028 [US4] P: In `claude-code-ide-session.el`, add `claude-code-ide-session-send-return-marked` bound to `RET` with the same top-level `define-key` install (`<return>` reaches `RET` through `function-key-map`; binding it would block that translation): when the CLI type is `omp` and the shadowed binding is `ghostel--send-event`, call `ghostel--on-user-input` first (`ghostel.el:1677`, keeps `ghostel-scroll-on-input` anchoring), then send `ESC _ pi:editor-submit;NONCE ESC \` + `\r` in one string; otherwise `call-interactively` the shadowed binding. Add the `declare-function` for `ghostel--on-user-input`.
- [X] T029 [US4] P: In `claude-code-ide-tests.el`: Return in an omp char-mode buffer sends marker plus `\r` in one string; a scrolled buffer with `ghostel-scroll-on-input` anchors on Return exactly as the shadowed path does, and `C-g` does not; Return in line mode, copy mode, Evil normal state, and a non-omp buffer runs the shadowed binding with no marker.

**Checkpoint**: `/todo edit`, the plan editor, the annotation editor, and the hook editor open in the attached Emacs from a terminal-input mode. Line-mode `/todo edit` falls back to `$EDITOR` (spec Clarification 2026-09-13).

---

## Phase 7: Polish

- [X] T030 [P] P: Add the short note under the with-editor paragraph in `README.org`: omp Sessions open the prompt in the attached Emacs; requires an Agent started after the upgrade; terminal-input modes only.
- [X] T032 Run the full gates: `bun test` in `packages/coding-agent`, `./scripts/compile-and-test.sh` here (expect the same skip count as baseline, 0 unexpected), then quickstart.md sections 2-8 in order (reload, local, remote, plain-terminal fallback, two Emacs instances, declined remote access for FR-014, other entries for US4). Result: gates green (Agent handoff files 35/35, `tsgo` clean, oxfmt clean; package 911/0 unexpected, 14 skipped); sections 2, 3, 4, 8 through `emacsclient`; section 5 in iTerm (T021); section 6 with a second `emacs --daemon=cchb` (each Emacs got only its own prompt); section 7 against `v12mac` (local `C-g` visited `/rpc:v12mac:…/omp-editor-*.omp.md` with no remote buffer, `C-c C-c` returned the edit to the remote composer, remote `C-g` opened only in the remote Emacs, and a host removed from `claude-code-ide-remote-hosts` gave one message plus remote vim after 0.5 s). Section 7 exposed three unrelated main-thread hangs fixed on the way: a dead SSE peer entering the debugger from a process filter, a `magit-prime` process leak reaching "Too many open files", and a remote Session buffer without a `/rpc:` prefix that let timers open tramp-sh to the Agent's self-reported hostname.
- [X] T033 Record the two `ponytail:` ceilings in code comments where they apply: raw default `ctrl+g`/Return bytes in `claude-code-ide-session.el`, and no Agent → Emacs abort during a slow remote open in `external-editor.ts`.

---

## Dependencies & Execution Order

- **Phase 1** first. **Phase 2** (T002-T007) blocks every story; T006 and T007 run in parallel after T002-T005.
- **US1** (T008-T016) depends on Phase 2. T009 → T010 → T011 → T012; T013 and T014 in parallel with T010-T012; T015 after T011, T012, and T014; T016 last in the phase.
- **US2** (T017-T019) depends on T010 and T011.
- **US3** (T020-T021) depends on Phase 2 and T008.
- **US4** (T022-T029) depends on Phase 2 and T009. T022 → T023 → T024; T025 and T027 in parallel after T004; T026 after T024; T028 → T029.
- **Polish** last. T032 is the acceptance run.

### Parallel Example: Phase 2 tests

```text
Task: "T006 external-editor.test.ts handoff cases"
Task: "T007 composer.test.ts marker cases"
```

### Parallel Example: US4 caller migrations

```text
Task: "T025 interactive-mode.ts plan + annotation"
Task: "T026 todo-command-controller.ts"
Task: "T027 hook-editor.ts"
```

---

## Implementation Strategy

1. Phase 1 + Phase 2 → `bun test` green.
2. US1 → run quickstart sections 2 and 4: the reported topology works. MVP.
3. US2 → local parity confirmed. US3 → plain-terminal fallback confirmed.
4. US4 → remaining editor entries.
5. Polish → full gates, then report. Do not commit unless asked. Submodule-first commit order applies when commits are requested.

## Notes

- Never send a marker without the raw key byte in the same write: `StdinBuffer` splits them into two events, and a pre-upgrade Agent consumes only the marker.
- The ack must precede the visit: the Agent ack timer is 500 ms and a remote worker may take up to 30 s.
- `require` never reloads a provided feature: reload `claude-code-ide-remote-project.el` first, and install the two key bindings outside the `defvar` initializer.
