# Feature Specification: Opt-in Remote RPC Magit View

**Feature Branch**: `main` (unchanged)

**Feature Directory**: `specs/005-remote-rpc-magit`

**Created**: 2026-09-06

**Status**: Confirmed design — ready for planning, implementation not authorized

**Input**: "specify it but dont change current working feature; still some other stuff working around"

**Design confirmation**: The user confirmed the contract after interview questions Q1–Q18. This revision replaces the earlier draft assumptions.

Remote Project views must follow local managed-view behavior where possible, subject to constitution principle VI, Local and Remote Workflow Parity. The user enables Project views and cleanup separately for each Configured host. The installed tramp-rpc package remains authoritative. The source checkout is reference material only.

## Clarifications

### Session 2026-09-06

- Q: Which action should reopen or retry a remote Project view? → A: Use existing manager `R` — Reset layout. Restore the default layout and start a fresh health-gated Project-view attempt.
- Q: May canceling a Project-view attempt or reaching its health timeout disconnect other RPC users on the same host? → A: No. The feature must abandon only its own attempt and preserve the shared connection. The installed client's independent transport failure and timeout policy remains unchanged.
- Q: When you close a shared Project view from one Session, which Sessions should require `R` before showing it again? → A: Only that Session. Other Sessions retain their own layout intent and may reuse or recreate the shared view.
- Q: Should a completed Project view appear when its Session is still displayed but your focus is elsewhere? → A: Yes. If the same Session remains current, show its Project view beside the terminal without changing the selected window.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Preserve existing work unless enabled (Priority: P1)

The user chooses which hosts receive remote Project views. Existing local and remote workflows remain unchanged for hosts without opt-in.

**Why this priority**: Other feature work is active. Optional project access must not become an attachment prerequisite.

**Independent Test**: Configure one enabled host and one disabled host. Exercise attachment, navigation, refresh, restoration, detach, and Stop, including environments without optional packages.

**Acceptance Scenarios**:

1. **Given** a fresh configuration, **When** a remote Agent attaches, **Then** the existing terminal-only behavior continues without RPC health checks or Project views.
2. **Given** opt-in for one host, **When** another host attaches, **Then** the other host retains disabled behavior.
3. **Given** missing optional packages, **When** disabled integration loads or attaches a Session, **Then** existing supported workflows remain available.
4. **Given** either preference value, **When** a local Session opens, **Then** this feature does not alter its commands, layout, or status-view customization.
5. **Given** an existing Session, **When** its host becomes opted in, **Then** the setting change alone does not connect or rearrange windows.
6. **Given** an enabled host, **When** Project views become disabled, **Then** future automatic preparation stops and existing buffers remain intact.
7. **Given** a host without attachment approval, **When** its Project-view preference is enabled, **Then** that preference does not authorize connection to the host.
8. **Given** Project views enabled and cleanup disabled, **When** the user detaches, **Then** the feature leaves Project-view buffers open.

---

### User Story 2 - Get a Project view on first managed display (Priority: P1)

The user opens an attached Session's managed layout. The feature shows project status beside the terminal without a separate Project-view command.

**Why this priority**: Remote attachment should feel like the local managed workflow, rather than require separate browsing steps.

**Independent Test**: Open the first managed layout for a healthy remote Git project. Repeat with a non-Git directory and a customized local status view.

**Acceptance Scenarios**:

1. **Given** an enabled host with healthy prerequisites, **When** a Session first enters its managed layout, **Then** its Project view appears beside the terminal.
2. **Given** the default status choice and available Magit, **When** a Git Project view opens, **Then** Magit shows that remote Worktree through tramp-rpc.
3. **Given** an accessible non-Git directory, **When** the default Project view opens, **Then** Dired shows that remote directory.
4. **Given** an accessible directory and unavailable Magit, **When** the default Project view opens, **Then** Dired follows the existing local fallback behavior.
5. **Given** a customized local status view, **When** a remote Project view opens, **Then** the same customization and local fallback policy receive the remote project context.
6. **Given** a successful initial view, **When** the layout appears, **Then** the manager remains visible and the selected window stays selected. Terminal-focused actions retain terminal focus. Manager-focused actions retain manager focus.
7. **Given** identical directory text on two hosts, **When** either Project view opens, **Then** its contents belong to the selected host, not the other host or local machine.
8. **Given** two Sessions in different subdirectories of one remote Worktree, **When** each first displays its managed layout, **Then** both use the same Project-view buffer.
9. **Given** two different Worktrees on one host, **When** their Project views open, **Then** the views remain distinct.
10. **Given** two non-Git Sessions, **When** their directories differ, **Then** their Dired views remain distinct. Exact host and directory identify each view.

---

### User Story 3 - Preserve bulk attachment and later layout restoration (Priority: P1)

The user attaches many Sessions without opening every remote project. Each Session prepares its Project view when first displayed through the manager.

**Why this priority**: Bulk attachment currently creates Sessions without choosing or displaying a final target. That behavior must remain unchanged.

**Independent Test**: Bulk-attach three remote Sessions. Display each through the manager, revisit one, and manually close another Project view.

**Acceptance Scenarios**:

1. **Given** three eligible Sessions on an enabled host, **When** bulk attachment completes, **Then** no Project-view health checks or preparation start solely from that bulk action.
2. **Given** a bulk-attached Session without a prepared view, **When** the user first opens its managed layout, **Then** health-gated Project-view preparation starts automatically.
3. **Given** another attached Session that the user never displays, **When** other Sessions receive Project views, **Then** the undisplayed Session does not start project access.
4. **Given** an existing prepared view, **When** the user leaves and returns to its Session, **Then** the saved layout returns without an automatic remote refresh.
5. **Given** a manually closed Project-view buffer, **When** the user revisits its Session, **Then** the terminal remains alone until the user invokes `R` — Reset layout.
6. **Given** a manually closed view, **When** the user invokes manager `R` — Reset layout, **Then** the default layout and health-gated Project view return without restarting the Agent.
7. **Given** a disconnected Session, **When** the user explicitly reattaches and displays its managed layout, **Then** a new preparation attempt may refresh its surviving Project view.
8. **Given** a view manually closed before reattach, **When** reattach succeeds, **Then** recreating the view still requires manager `R` — Reset layout.
9. **Given** an existing shared view, **When** another Session first prepares that Worktree's view, **Then** the feature reuses and refreshes the buffer without creating a duplicate.
10. **Given** Sessions A and B sharing a view, **When** the user dismisses it from A's layout, **Then** only A requires `R` to show it again. B retains its own layout intent.
11. **Given** the user kills the shared buffer from A, **When** B next enters managed display with a saved layout that includes that view, **Then** B may prepare a replacement. A still requires `R`.
12. **Given** an initial attempt that finished while the user was away, **When** the user returns, **Then** absence of a previous display alone does not count as manual closure.

---

### User Story 4 - Diagnose project access without blocking the terminal (Priority: P1)

The user keeps the attached terminal usable while optional project access proceeds. Failures identify the affected host and offer a corrective action.

**Why this priority**: A working SSH terminal does not prove that the RPC client, server, or selected status view works.

**Independent Test**: Exercise missing client, incompatible server, denied access, slow health checks, and slow status preparation while interacting with the terminal.

**Acceptance Scenarios**:

1. **Given** a missing or unsupported local RPC client, **When** Project-view preparation starts, **Then** the feature reports setup guidance before any remote health request.
2. **Given** an installed client and missing remote server, **When** the health check runs, **Then** the feature reports server setup guidance without undoing attachment.
3. **Given** a server binary that cannot answer a compatible request, **When** health is checked, **Then** binary presence does not qualify as success.
4. **Given** a previously healthy connection, **When** a new preparation attempt checks health, **Then** an actual response from the intended server must support success.
5. **Given** a missing prerequisite, **When** preparation fails, **Then** the feature does not download, build, install, update, or deploy software.
6. **Given** a stalled health check, **When** thirty seconds elapse, **Then** the feature reports its host and abandons only that attempt. It preserves the terminal and does not close the shared RPC connection.
7. **Given** successful health checks and slow status preparation, **When** preparation exceeds thirty seconds, **Then** the terminal remains usable and preparation remains cancellable.
8. **Given** a missing or inaccessible directory, **When** neither the configured status view nor its normal local fallback can open it, **Then** the terminal remains alone with guidance.
9. **Given** healthy RPC but an unavailable preferred status dependency, **When** the local fallback can open the directory, **Then** that fallback may provide the Project view.
10. **Given** unhealthy RPC, **When** preparation fails, **Then** the feature does not start Dired to bypass the failed health gate.
11. **Given** a repaired prerequisite, **When** the user invokes manager `R` — Reset layout, **Then** health is checked again without reattaching or restarting the Agent.
12. **Given** a failed attempt, **When** navigation or ordinary manager refresh occurs, **Then** no automatic retry or repeated failure notice occurs.

---

### User Story 5 - Keep pending results separate from session control (Priority: P2)

The user can change focus, detach, or disable project access while a Project view is pending. Valid results may update the current Session's view without taking focus. Old results cannot replace another Session's layout.

**Why this priority**: Optional repository work must not interfere with Session ownership or other work.

**Independent Test**: Delay health and status operations separately. Change focus or attachment state before each operation completes.

**Acceptance Scenarios**:

1. **Given** a pending Project view, **When** the user selects another Session, **Then** completion does not change that Session's layout or take focus.
2. **Given** a pending attempt, **When** its Session detaches or receives a newer attachment, **Then** the old result cannot restore or modify that Session's layout.
3. **Given** a pending attempt, **When** Project views become disabled or the host loses approval, **Then** completion cannot display a new Project view.
4. **Given** pending health or status preparation, **When** the user invokes Cancel Project-view preparation for that Session, **Then** no further preparation starts and late results cannot change the layout. The terminal and shared RPC connection remain available.
5. **Given** one host's failed project access, **When** another local or remote Session is used, **Then** its state and usability remain unchanged.
6. **Given** repeated explicit requests for one Session, **When** an older request finishes, **Then** only the current request may apply its result.
7. **Given** a pending attempt, **When** the user switches Sessions, **Then** the attempt may finish without display. Switching alone is not cancellation.
8. **Given** another RPC user on the host, **When** this feature cancels or reaches its health deadline, **Then** it does not disconnect that user. Independent transport failures still follow the installed client's policy.
9. **Given** the same Session remains current with its terminal visible, **When** preparation finishes while focus is in the manager or another window, **Then** the Project view appears beside the terminal without changing the selected window.

---

### User Story 6 - Optionally close only owned Project views on explicit detach (Priority: P2)

The user separately enables Project-view cleanup for a host. Explicit manager detach may close eligible views without touching editing buffers or shared connections.

**Why this priority**: Cleanup should remove automatically created views without claiming ownership of unrelated work.

**Independent Test**: Compare explicit manager detach with terminal closure and network failure. Include shared, modified, reused, and custom buffers.

**Acceptance Scenarios**:

1. **Given** cleanup disabled for a host, **When** explicit manager detach occurs, **Then** all Project-view buffers remain open.
2. **Given** cleanup enabled and an unmodified Magit or Dired view created by this feature, **When** its last attached Session explicitly detaches, **Then** the feature closes that view.
3. **Given** two attached Sessions sharing a Worktree, **When** one explicitly detaches, **Then** the shared Project view remains open for the other.
4. **Given** a view that existed before this feature used it, **When** explicit detach occurs, **Then** the feature preserves that reused buffer.
5. **Given** source files opened independently or from a Project view, **When** explicit detach occurs, **Then** every source-file buffer remains open.
6. **Given** a modified Project-view buffer, **When** cleanup runs, **Then** the feature preserves it and reports that it remains open without saving or prompting.
7. **Given** a custom status buffer with uncertain ownership, **When** cleanup runs, **Then** the feature preserves that buffer.
8. **Given** cleanup enabled, **When** a terminal buffer closes, the network fails, or Emacs exits, **Then** this feature performs no additional buffer cleanup.
9. **Given** cleanup enabled, **When** explicit Stop runs, **Then** existing Stop behavior remains unchanged and this feature adds no Project-view cleanup.
10. **Given** cleanup enabled, **When** explicit manager detach runs, **Then** cleanup neither queries remote paths nor disconnects shared RPC connections.
11. **Given** matching directory names on different hosts, **When** one Session detaches, **Then** views belonging to the other host remain untouched.

### Edge Cases

- A remote directory contains spaces or shell punctuation. Treat its text as data, never as a command.
- The same path exists locally and remotely. Project views use the exact Configured host and never inspect a matching local checkout.
- Session directories differ within one Worktree. Worktree identity, not Session-directory equality, determines view sharing.
- Worktree identity is unknown. Do not guess sharing from directory names or ancestor text alone.
- A non-Git directory has no Worktree identity. Use its exact host and directory for Dired-view identity.
- A repository vanishes after health succeeds. Preserve the terminal and report the status-view failure or normal local fallback result.
- A server is installed but cannot execute or answer compatible requests. Report unhealthy RPC rather than successful deployment.
- A stale local cache describes a once-working connection. The health result still requires actual remote evidence for the current attempt.
- An attachment fails before a terminal becomes available. No automatic Project-view preparation follows that failed attachment.
- Focus moves from the terminal to the manager or another window while the same Session remains current. Its valid Project view may appear without taking focus. Switching to another Session prevents automatic display of the old Session's result.
- A previously failed or manually closed view is revisited from the affected Session. The revisit is not a new first-display attempt and does not cause automatic retry.
- A user has remote VC exclusions or custom project caches. Preserve those settings and follow the configured status behavior without promising advertised speedups.
- Session A's terminal-only layout reflects its manual closure of a shared view. B may still display or recreate that view without changing A's layout.
- Cleanup encounters an unknown buffer owner or unknown Worktree relationship. Preserve the buffer instead of resolving paths remotely.
- One Session detaches while another attachment of the same Session is pending. Old cleanup must not claim the newer attachment's view.

## Requirements *(mandatory)*

### Functional Requirements

#### Opt-in and local parity

- **FR-001**: Provide separate per-host choices for automatic Project views and Project-view cleanup. Both MUST default to disabled. (Stories 1, 6)
- **FR-002**: With both host choices disabled, retain existing behavior without additional package loading, health checks, Project-view work, or cleanup. Evaluate each opt-in independently. (Stories 1, 6)
- **FR-003**: Missing optional dependencies MUST NOT prevent existing supported Session workflows or raise the package's baseline requirements. (Stories 1, 4)
- **FR-004**: Preserve existing local behavior, Session identity, Agent configuration, terminal transport, metadata refresh, persistence, and Stop confirmation. (Stories 1, 5, 6)
- **FR-005**: Preference changes, startup, ordinary refresh, rendering, and saved-state restoration MUST NOT independently start remote project access. (Stories 1, 3)
- **FR-006**: Use the installed tramp-rpc package and its normally selected server binary. Preserve package ownership, source selection, SSH security, and saved or global deployment settings. Enforce this feature's no-provisioning rule only for its own preparation attempts. (Stories 1, 4)
- **FR-007**: Follow constitution principle VI and the existing local managed-view workflow. Each required remote difference MUST have a stated remote constraint. (Stories 1–5)

#### Health and status preparation

- **FR-008**: Before remote health requests, check that the installed RPC client loads with supported dependencies. Report missing local prerequisites at the point of use. (Story 4)
- **FR-009**: Health success MUST require an actual compatible response from the intended server during the current attempt. Installation records and cached status alone are insufficient. (Story 4)
- **FR-010**: Check remote directory accessibility before claiming a usable Project view. Git availability is a status-view dependency, not a universal RPC health requirement. (Stories 2, 4)
- **FR-011**: Preparation, including health checks and reconnects, MUST NOT install, download, build, deploy, or update software on either machine. Preserve the installed client's server selection while preventing acquisition for this attempt. Provide guidance for separate user-directed setup without altering other RPC users' deployment behavior. (Story 4)
- **FR-012**: Bound the health phase to thirty seconds from that phase's start. At its deadline, report the host and abandon only this attempt. The feature MUST NOT retire the shared RPC connection or detach the terminal. The installed client's independent transport failure and timeout policy remains unchanged. (Stories 4, 5)
- **FR-013**: Provide a Cancel Project-view preparation action for the selected Session in the manager's action menu. Cancellation MUST schedule no new RPC requests or status work for that attempt. Already running requests may finish, but their results MUST NOT update its Project view or layout. Preserve the shared RPC connection. Cancellation MUST NOT retry, detach, or change host preferences. Status preparation remains nonblocking and has no new fixed thirty-second deadline. (Stories 4, 5)
- **FR-014**: Health failure MUST stop Project-view preparation without a substitute remote access attempt. Preserve the terminal and give a corrective action. (Story 4)
- **FR-015**: Follow the configured local status view and its normal fallback policy after successful health checks. Missing Magit alone MUST NOT block Dired fallback. (Stories 2, 4)
- **FR-016**: If neither the configured status view nor its normal local fallback can open the directory, retain the terminal-only view and report guidance. (Story 4)
- **FR-017**: Use existing manager `R` — Reset layout as the explicit Project-view open/retry action for an attached Session on an enabled host. It MUST restore the default layout and start a fresh health-gated attempt without restarting or reattaching the Agent. A repeated request supersedes the pending attempt. Preserve local and disabled-host reset behavior, and retain `o` for its existing project selection and Session start/resume workflow. Failure MUST NOT trigger automatic retry. (Stories 3–5)
- **FR-018**: Health and status preparation MUST NOT block terminal interaction or unrelated Sessions. Scheduling a blocking operation later does not satisfy this requirement. (Stories 4, 5)
- **FR-019**: Use only currently approved destinations. Project-view preferences MUST NOT provision credentials, grant host approval, or weaken authentication. (Stories 1, 5)

#### View creation, sharing, and restoration

- **FR-020**: For an enabled host, first managed display of an attached Session MUST prepare its Project view without a separate user command. (Stories 2, 3)
- **FR-021**: Bulk attachment MUST retain its current no-display behavior. Do not health-check or prepare projects until their Sessions first enter managed display. (Story 3)
- **FR-022**: The default Project view MUST use Magit for a Git project when available and Dired for an accessible non-Git directory. Honor local customization and fallback. (Stories 2, 4)
- **FR-023**: Display the Project view beside the current Session's visible terminal with the manager retained. Completion MUST preserve the selected window, whether it is the terminal, manager, or another window. Use the local default status and terminal positions without replacing unrelated content. Asynchronous arrival is the remote difference, not a new focus policy. (Stories 2, 5)
- **FR-024**: Share a Project-view buffer across Sessions on the same exact host and Worktree, including different subdirectories. Each Session retains independent layout and manual-close state. Keep different hosts and Worktrees distinct. (Stories 2, 3)
- **FR-025**: For non-Git directories, identify a Dired view by exact host and directory. Do not infer a common Worktree or merge ancestor directories. (Story 2)
- **FR-026**: Keep Session-directory metadata unchanged. Resolve view identity only during permitted project access, without interpreting remote directories as local paths. (Stories 1, 2)
- **FR-027**: During a new permitted preparation attempt, refresh or populate the selected status view, reusing an existing matching buffer when possible. (Stories 2, 3)
- **FR-028**: When the saved Project-view buffer survives, later navigation MUST restore the existing layout without automatic remote refresh. If another Session killed that buffer, the current Session may prepare a replacement on managed display when its own layout still requests the view. The user retains explicit status refresh controls. (Story 3)
- **FR-029**: Explicitly dismissing the Project-view window or killing its buffer from a Session MUST suppress automatic display only for that Session. Navigation, reattach, and another Session's view creation MUST preserve that suppression until manager `R` — Reset layout. Merely switching Sessions or never displaying a pending result MUST NOT count as manual closure. (Story 3)
- **FR-030**: Explicit reattach followed by managed display may prepare or refresh a view when that Session's layout still requests it. The view may survive or need recreation after another Session's buffer closure or eligible cleanup. The current Session's own manual closure always takes precedence. (Story 3)
- **FR-031**: Preserve user VC, status-view, and project-cache settings. Do not rewrite them to enable remote access or advertise unverified acceleration. (Stories 1, 2, 4)

#### Request ownership and cleanup

- **FR-032**: Associate each attempt with its Session, current attachment, and display intent. Explicit cancellation, supersession by `R`, detach, host disablement, and loss of host approval MUST invalidate that attempt's results. Switching Sessions alone MUST NOT cancel it. Independent client transport failures may still end the connection. (Story 5)
- **FR-033**: Display intent remains valid when the attempt's Session is still the frame's current managed Session and its terminal remains visible. The selected window need not be the terminal. Valid completion may add the Project view without selecting a window. Completion MUST NOT replace another Session's layout, override manual closure, or produce duplicate current views. (Story 5)
- **FR-034**: Cleanup MUST require its separate host opt-in and explicit manager detach. Terminal closure, network loss, Emacs exit, and Stop MUST retain existing cleanup behavior. (Story 6)
- **FR-035**: Cleanup MUST consider only automatically created Magit/Dired Project-view buffers owned by this feature. Preserve reused buffers and custom buffers with uncertain ownership. (Story 6)
- **FR-036**: Source-file buffers MUST remain outside automatic cleanup, including files opened through an owned Project view. (Story 6)
- **FR-037**: Preserve Project views while another attached Session uses their host and Worktree or non-Git view identity. Do not infer exclusive ownership from one Session's directory. (Story 6)
- **FR-038**: Preserve modified Project-view buffers and report retained buffers. Detach MUST NOT save files or prompt for remote saves as part of cleanup. (Story 6)
- **FR-039**: Cleanup MUST use already known ownership and host/project information. Do not discover or resolve remote paths during cleanup. Preserve uncertain cases. (Story 6)
- **FR-040**: Cleanup MUST NOT disconnect shared RPC connections or affect other hosts, newer attachments, or unrelated Sessions. (Stories 5, 6)

### Key Entities *(include if feature involves data)*

- **Session**: The existing Emacs-side Agent attachment, with its own identity, terminal, host, directory metadata, and managed layout.
- **Configured host**: An existing user-approved remote destination. Project-view and cleanup preferences do not replace attachment approval.
- **Worktree**: One working directory of a Git repository. Sessions in different subdirectories may belong to the same Worktree.
- **Project view**: The shared status or directory buffer for one exact host and Worktree, or one exact non-Git host and directory.
- **Project-view preferences**: Two independent disabled-by-default choices for each host: automatic Project views and cleanup on explicit manager detach.
- **Health result**: Current evidence of usable local RPC prerequisites and a compatible response from the intended remote server, or a corrective failure reason.
- **Preparation attempt**: One health-gated effort to create or refresh a Project view for a Session's current attachment. Its display intent depends on the current managed Session and visible terminal, not keyboard focus.
- **Owned Project view**: An eligible Magit/Dired buffer created by this feature. Reusing an existing buffer does not grant cleanup ownership.
- **Manually closed view**: A per-Session choice made by explicitly dismissing that Session's Project-view window or killing its buffer from that Session. Other Sessions' display choices remain independent.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Across disabled-host attachment, navigation, refresh, restoration, and detach, this feature causes zero additional remote project requests or layout changes.
- **SC-002**: At healthy first managed display, users see a Project view beside the terminal without a separate user command. Both terminal-focused and manager-focused entry paths preserve their selected window.
- **SC-003**: Every stalled health check reports its host within thirty seconds without a feature-induced shared-connection shutdown. Slow status preparation remains cancellable without interrupting terminal input.
- **SC-004**: Two Sessions in different subdirectories of one Worktree share one view. Different hosts and Worktrees always retain distinct views.
- **SC-005**: Missing-client, missing-server, incompatible-server, and denied-access scenarios yield corrective guidance with zero automatic software installation.
- **SC-006**: Accessible non-Git directories and missing preferred status software use the normal directory-view fallback rather than falsely reporting broken remote transport.
- **SC-007**: Bulk-attaching three Sessions starts zero project checks. Each receives its view on first managed display, with no preparation for undisplayed Sessions.
- **SC-008**: Returning to a surviving prepared view makes zero automatic refresh requests. After manual closure in Session A, A creates or displays zero replacement views until Reset layout. A sibling Session B may independently reuse or recreate its requested view.
- **SC-009**: After prerequisite repair, one manager Reset layout action restores access without restarting or reattaching the Agent.
- **SC-010**: Same-Session completion changes keyboard focus zero times. Across Session changes, detach, replacement attachment, cancellation, disablement, and host removal, zero stale results replace the current layout.
- **SC-011**: With cleanup enabled, explicit detach closes eligible unmodified Project views only after their last attached Session detaches.
- **SC-012**: Cleanup preserves every source-file buffer, reused buffer, modified view, uncertain custom buffer, and view still shared by an attached Session.
- **SC-013**: Terminal closure, network loss, Stop, and editor exit cause zero additional Project-view closures from this feature. Cleanup makes zero remote path requests or shared-connection shutdowns.

## Assumptions

- The user authorized this feature's specification, checklist, and planning artifacts. Runtime implementation, live configuration changes, deployment, branch switching, and commits remain unauthorized.
- The user explicitly selected `specs/005-remote-rpc-magit` in `.specify/feature.json` before planning. Other feature documents remain outside this planning update.
- The installed `use-package` tramp-rpc client is authoritative. The local source checkout is reference material, not a runtime or build-source override.
- Per-host preferences follow the existing user-configuration workflow. No new interactive preferences interface is required by this specification.
- Project-view and cleanup preferences apply to exact Configured host identities. SSH aliases are not automatically reconciled.
- Local Emacs needs a usable RPC client and whichever dependencies its chosen status view requires. Magit is not mandatory when local fallback uses Dired.
- The remote host needs a compatible server and accessible directory. Git is needed for Git status, not for a usable non-Git directory view.
- Starting an RPC session and reading project data are permitted during a requested preparation attempt. Software provisioning and automatic repository mutation are not health-check actions.
- The existing local status-view customization remains authoritative, including its normal fallback behavior. Unknown custom buffer ownership never grants cleanup permission.
- First managed display means the user's initial manager-driven presentation of an attached Session, not bulk attachment or background refresh.
- Manual-close state belongs to the remembered Session, not the shared buffer or Worktree. It survives that Session's reattach without adding new cross-restart history.
- Thirty seconds bounds only the health phase. Initial status preparation has no additional fixed deadline but must remain nonblocking and cancellable.
- The feature's cancellation and health deadline abandon its own work. They do not promise to keep a genuinely failed transport alive or alter the installed client's independent timeout policy.
- Planning must prove nonblocking preparation, no acquisition during the entire attempt, and cancellation without feature-induced shared-connection retirement. No implementation technique is assumed proven.
- Planning must prove closure detection for the current Session using observable user actions and layout state. A never-displayed pending result or ordinary Session switch is not a close action. Test window dismissal and shared-buffer killing separately.
- Remote VC exclusions and custom caches remain user settings. Implementation must verify explicit remote status behavior without assuming benchmark results.
- Cleanup covers only eligible Project-view buffers, not arbitrary buffers under a project directory. It never tracks files opened from those views.
- Existing attachment and grouped-view specifications remain unchanged. Host validation, terminal lifecycle, metadata policy, and Agent behavior remain their responsibility.
- Remote MCP, tunnels, selection synchronization, transport replacement, automatic host discovery, and a new Git interface remain outside scope.
