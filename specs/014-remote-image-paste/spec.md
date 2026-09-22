# Feature Specification: Remote Image Paste

**Feature Branch**: `main` (unchanged)

**Created**: 2026-09-18

**Status**: Draft

**Input**: User request: make an image on the local clipboard reach an Agent that runs on another host, so that pasting an image into a remote Session matches the local workflow. Use the terminal's paste-event clipboard standard as the transport. A local Agent that reads the local clipboard itself must keep working.

## Clarifications

### Session 2026-09-18

- Q: Does this feature deliver the terminal-side clipboard capability as well as the package-side wiring? → A: Both, sequenced. The plan states the terminal-side capability first, then the package wiring and its degradation path. Acceptance tests run once both halves land.
- Q: When the terminal can serve the clipboard image, should a local Session keep the Agent's own clipboard read, or switch to the terminal path? → A: Keep the current local read. The terminal path serves remote Sessions only. Local and remote match in outcome, and the visible result, not the mechanism, is the parity requirement.
- Q: Does the transfer use the clipboard image as it stands when the user presses the gesture, or as it stands when the Agent asks for it? → A: Read on request. The local clipboard is read when the Agent asks, so a remote paste has the same timing as today's local paste, and no snapshot is kept.
- Q: For a large screenshot, should the transfer send the image exactly as the clipboard holds it, or reduce it to fit a budget? → A: Send unchanged. The Agent's existing attachment rules apply, exactly as for a local paste. No package-side resize and no package-side cap.
- Q: When the local terminal copy is not the copy that feeds input to the Agent, should the package try to recover the delivery itself, or only explain the condition? → A: Explain only. The Session names the condition and the one action that restores delivery, sends nothing, and leaves terminal ownership untouched.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Paste an image into a remote Agent (Priority: P1)

The user copies a screenshot on the local machine, focuses the Session buffer of an Agent that runs on another host, and presses the paste-image gesture. The Agent receives the image as an attachment and can describe or use it in the same way as a locally started Agent.

**Why this priority**: This is the requested benefit. Today the gesture makes the remote Agent read a clipboard that does not exist on its host, so nothing arrives.

**Independent Test**: Copy a screenshot, paste it into a remote Session, and confirm the Agent reports and displays an image attachment with the expected dimensions. Repeat on a local Session for comparison.

**Acceptance Scenarios**:

1. **Given** a Session whose Agent runs on an approved remote host and a local clipboard that holds an image, **When** the user presses the paste-image gesture in that Session buffer, **Then** the Agent receives an image attachment and acknowledges it in the next turn.
2. **Given** the same Session and a local clipboard that holds text only, **When** the user presses the same gesture, **Then** the text reaches the Agent exactly as it does today.
3. **Given** a local Session and a clipboard that holds an image, **When** the user presses the gesture, **Then** the image attachment still arrives through the current direct read, unchanged (no regression).
4. **Given** a Session in an Agent that does not accept images, **When** the user presses the gesture with an image on the clipboard, **Then** the gesture keeps its current behavior for that Agent and adds no image attachment.

---

### User Story 2 - Receive the image without a workspace side effect (Priority: P1)

The user expects the transfer to use the Session's own terminal connection. The image does not appear as an unexpected file on the remote host, and no cleanup step is required afterwards.

**Why this priority**: A transfer that leaves files behind or asks the user to clean up would be a different feature with a different cost and privacy profile.

**Independent Test**: Paste an image into a remote Session, then search the remote host for new files created around the transfer. Confirm that none carry the image, and that the Session's working directory is unchanged.

**Acceptance Scenarios**:

1. **Given** a remote Session, **When** the user pastes an image, **Then** no new file containing that image exists on the remote host.
2. **Given** a remote Session on a host the user has not approved, **When** the user starts or attaches the Session, **Then** the existing host-approval and attachment rules are unchanged.
3. **Given** a finished transfer, **When** the user continues working, **Then** no cleanup command, no prompt, and no additional confirmation is required.

---

### User Story 3 - Understand a paste that cannot be delivered (Priority: P2)

When the image cannot reach the Agent, the user learns why in the Session and keeps a usable Session. The package never substitutes a different operation, and never reports success for an image that did not arrive.

**Why this priority**: Silent failure wastes the user's time. A silent substitute (for example, pasting a file path instead of the image) misleads the Agent about what the user sent.

**Independent Test**: Reproduce each unsupported condition, press the gesture, and confirm that an explanation appears, that no image or substitute object is sent, and that the Session keeps accepting input.

**Acceptance Scenarios**:

1. **Given** a terminal that lacks the paste-event capability, **When** the user pastes an image into a remote Session, **Then** the Session explains that the terminal cannot deliver clipboard images and names the supported alternative.
2. **Given** a local terminal copy that is not the copy delivering input to the Agent, **When** the user pastes an image, **Then** the Session names that condition and the one action that restores delivery, sends nothing, and changes no terminal ownership.
3. **Given** a remote host that becomes unreachable during the transfer, **When** the transfer fails, **Then** no partial image is attached and the Session reports the failure.
4. **Given** an unreadable or empty image on the clipboard, **When** the user pastes it, **Then** the Session reports the condition and attaches nothing.

---

### Edge Cases

- **EC-01 — Clipboard holds several representations**: An image and text can be present at once. The Agent's own preference decides which representation arrives, exactly as for a local paste.
- **EC-02 — Large screenshot**: A full-screen or retina screenshot can exceed several megabytes. The transfer sends the image unchanged, and the Agent's existing size rules decide the outcome, exactly as for a local paste. The package adds no size cap of its own.
- **EC-03 — Clipboard changes mid-transfer**: The user copies something else while the transfer is in flight. The transfer reflects the clipboard state at the moment the Agent reads it, exactly as today's local paste does. It never mixes two images and never attaches a partial image.
- **EC-04 — Multiple Sessions, multiple Emacsen**: Several Sessions can exist, local and remote, in one Emacs and in several. A gesture in one Session never attaches an image to another.
- **EC-05 — Terminal without native support**: An older terminal backend, or a Ghostel build without the capability, keeps its current behavior and explains the limitation at the point of use.
- **EC-06 — No GUI clipboard**: An Emacs process without access to a graphical selection (terminal Emacs, remote Emacs) has no image to serve. The Session explains the condition instead of attaching something else.
- **EC-07 — Text paste paths stay intact**: Multi-line collapse, large-paste handling, bracketed paste, and raw text paste keep their current behavior.
- **EC-08 — Session identity**: The gesture applies to the focused Session only, including after an Emacs restart that reattaches an existing Agent.
- **EC-09 — Repeated gestures**: Two consecutive pastes of different images deliver two distinct attachments in order.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A paste-image gesture in a Session buffer MUST deliver the locally copied image to the Agent of that Session when both the terminal and the Agent support image transfer, regardless of the host that runs the Agent.
- **FR-002**: The gesture MUST preserve current behavior for every other payload: text clipboards, Agents that do not accept images, and Sessions whose terminal cannot transfer images.
- **FR-003**: The transferred image MUST arrive as the Agent's ordinary image attachment, with the same attachment semantics, ordering, and size limits as an image pasted into a local Session.
- **FR-004**: Every gesture MUST produce exactly one explicit outcome: an attached image, a preserved text paste, or a user-visible explanation. The feature MUST NOT fail silently and MUST NOT report an attachment that did not reach the Agent.
- **FR-005**: The feature MUST NOT substitute a different operation for the image. It MUST NOT paste a local path, a remote path, or a file created for the transfer, and it MUST NOT write the image to the Agent's host disk.
- **FR-006**: The feature MUST read the local clipboard only in response to a paste gesture in a Session. It MUST NOT read the clipboard in the background, at startup, or for another Session's gesture.
- **FR-007**: The read authorization created by a gesture MUST cover that gesture only. It MUST NOT authorize later reads, reads by another program, or reads of a different clipboard location.
- **FR-008**: The image bytes MUST be served from the local machine that holds the clipboard, so the Agent's host needs no clipboard of its own.
- **FR-009**: When the terminal cannot deliver clipboard images, or the local terminal copy is not the copy delivering input to the Agent, the Session MUST state the condition and the one action that restores delivery, and MUST send nothing. The Session MUST stay usable, MUST NOT attempt to take over input ownership from another client, and MUST NOT change its terminal, its target, or its Agent.
- **FR-010**: A transfer that cannot complete, or that exceeds the time budget, MUST attach nothing and MUST report the failure. A partially transferred image MUST NOT be attached.
- **FR-011**: Remote Sessions MUST match local Sessions for the gesture, the resulting attachment, ordering, size limits, the acknowledgement, and the visible outcome. Parity applies to the visible result, not to the mechanism. Any required difference MUST be explicit in the user-visible behavior. *(Principle VI)*
- **FR-012**: The feature MUST NOT change host approval, authentication, host-key checking, connection limits, session ownership, or start, attach, reattach, detach, and Stop behavior.
- **FR-013**: The feature MUST NOT add a required dependency. When the terminal's native support is absent, the package and its test suite MUST still load, byte-compile, and pass. *(Principle III)*
- **FR-014**: The feature MUST NOT change text paste behavior, including multi-line collapse, large-paste handling, bracketed paste, raw text paste, and the existing keybinding precedence. *(Principle II)*
- **FR-015**: The image that reaches the Agent MUST remain usable for the Agent's vision features: the Agent can read its dimensions and discuss its contents.
- **FR-016**: A local Session MUST keep its current direct clipboard read as its primary path. The terminal-mediated path MUST serve a Session whose Agent cannot read the local clipboard, so the feature adds a path and does not replace the local mechanism.
- **FR-017**: The feature MUST NOT resize, recompress, transcode, or cap the image. The image bytes MUST reach the Agent unchanged, and the Agent's existing attachment rules MUST decide the accepted size and format, exactly as for a local paste.

### Key Entities *(include if feature involves data)*

- **Paste-image gesture**: The user's command in a Session buffer that sends the clipboard's image to that Session's Agent.
- **Local clipboard image**: The image representation held by the graphical session on the user's machine, with its size and format.
- **Clipboard-serving terminal**: The terminal backend that owns the Session's process and answers the Agent's request for the clipboard data. It is the only component that can read the local clipboard on the Agent's behalf.
- **Read authorization**: The short-lived permission that allows one paste gesture's data read, and nothing else.
- **Session**: One Agent attached through one terminal buffer, local or on an approved remote host.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In five consecutive attempts on a supported remote Session, a pasted screenshot reaches the Agent as an image attachment on the first gesture, with the same dimensions the local workflow reports.
- **SC-002**: A screenshot of at least 5 MB completes the gesture within 10 seconds and yields a usable image attachment.
- **SC-003**: Across all unsupported conditions (old terminal backend, non-leading terminal copy, unreachable host, empty clipboard, non-image Agent), 100% of gestures produce either the current text behavior or an explicit explanation, and zero gestures produce a silent no-op or a substituted object.
- **SC-004**: After the feature, the existing paste test suite passes unchanged, including text paste, non-image Agents, and keybinding precedence.
- **SC-005**: Paste gestures in one Session never attach an image to another Session: ten gestures alternating between two Sessions attach exactly ten images, five to each.
- **SC-006**: No clipboard read occurs without a paste gesture in a Session: a tracked session with zero gestures records zero reads.
- **SC-007**: A user who has never used the feature completes a remote image paste within 60 seconds of reading the Session's own guidance, without leaving the Session buffer.

## Assumptions

- The Agents that gain the behavior are those that implement the client side of the paste-event standard. That set is one Agent today (Oh My Pi). Agents that do not accept images, and Agents without a client-side implementation, keep their current text paste.
- The terminal-side clipboard capability is in scope for this feature and is sequenced before the package-side wiring. The package MUST degrade explicitly while the capability is absent, and MUST keep working against a terminal build that lacks it.
- Local Sessions keep the direct clipboard read as their primary path. The terminal-mediated path serves Sessions whose Agent cannot read the local clipboard, so the feature adds a path and does not replace the local mechanism.
- The transfer uses the Session's existing terminal connection. No new network path, port forward, or service is introduced.
- The transport is the terminal's paste-event clipboard standard (the OSC 5522 clipboard protocol and its
  paste-event private mode), which the Agent side already implements for at least one supported Agent.
  Its wire details belong to the plan, not to this specification.
- Emacs runs with access to a graphical selection when the user pastes an image. Terminal-only Emacs explains the limitation.
- Session multiplexer client rules are unchanged. When the local terminal copy cannot deliver input to the Agent, the feature reports the condition instead of reworking the multiplexer.
- Out of scope: screenshots captured by the package, OCR, image editing, image annotation, new keybindings, file-based transfer of the image, and any change to how Agents store or send images afterwards.

## Dependencies

- The supported terminal backend provides the paste-event clipboard capability, including mode reporting, a one-time read authorization, and chunked data transfer. This feature delivers that capability. An older backend build keeps today's behavior and is explained at the point of use.
- At least one Agent implements the client side of the same standard.
- The Session multiplexer must forward the terminal's response bytes to the Agent when the local terminal copy is the input leader.
