# Ghostel Kitty Rendering: Profile and Optimization Options

Date: 2026-09-08

Status: Both the single-search Elisp change and native payload guard are active.
After the user restarted Emacs, a live native smoke check verified the guard.
The original analysis below describes the pre-change renderer.
See [implementation results](#implementation-results) and
[native guard verification](#native-guard-implementation-and-verification).

## Purpose

Evaluate three proposed optimizations for the Kitty graphics cost in the live
Emacs report `*CPU-Profiler-Report 2026-09-08 03:41:59*`:

1. Cache complete placement state and skip unchanged work.
2. Skip work when the buffer character-change tick is unchanged.
3. Cache placeholder grid dimensions per image ID.

This note records source findings, live probes, limitations, and a revised
ranking. The user requested documentation before implementation.

## Profile evidence

The report was expanded and read through `emacsclient`. The expanded text was
saved to `/tmp/cpu-profile-report.txt`. That temporary file is not a durable
repository artifact.

| Call-tree entry | Samples | Reported share |
| --- | ---: | ---: |
| `timer-event-handler` | 6,172 | 45% |
| Its `ghostel--redraw-now` descendant | 5,703 | 41% |
| Its `ghostel--redraw` descendant | 5,524 | 40% |
| Its `ghostel--kitty-display-virtual` descendant | 4,516 | 32% |
| `Automatic GC`, a separate top-level entry | 5,968 | 43% |
| `redisplay_internal`, a separate top-level entry | 1,114 | 8% |

The first four rows overlap. Their percentages must not be added.

Within the virtual-image callback, the report shows substantial time in
`line-end-position`, `search-forward`, and `forward-line`. This supports the
full-buffer scan diagnosis.

The CPU report does not attribute GC samples to particular allocations.
The earlier claim that Kitty caused the 43% GC cost was too strong.
`create-image` accounted for only eight samples in this branch.

[INFERENCE] Native image conversion and repeated Emacs image-data copies could
contribute to allocation pressure. An allocation profile or controlled comparison
must establish their contribution.

### Other corrections

- The live timer delay was `0.033`, with adaptive FPS enabled. This is not a
  measured redraw rate or a strict frame-rate limit.
- Interactive echo can trigger immediate redraw. Idle recovery can use a shorter
  delay. See [redraw scheduling][scheduling].
- A nil `ghostel--kitty-active` does not prove that virtual-placement callbacks
  have stopped. The callback can scan without finding any placeholders.
- The previously reported live buffer sizes were current observations, not sizes
  recorded during the profile capture.
- The CPU report does not identify which terminal buffer caused the samples.

## Current rendering path

[GhostelTerm.redraw][redraw] first calls the terminal renderer. After a successful
return, it calls `ghostel--kitty-clear`, then emits Kitty placements.

```text
Terminal renderer
  -> clear Kitty display properties
  -> iterate stored placements
     -> convert image data and copy it into an Emacs string
     -> ghostel--kitty-display-virtual(data, is-png)
        -> scan every buffer line to measure the grid
        -> create an image specification
        -> scan every buffer line to apply slices
```

[Renderer.redraw][renderer] can return success without repainting text. It also
publishes `ghostel--repainted-region`, or nil when no region was painted.
This is a useful existing signal for evaluating display invalidation.
It is not, by itself, a complete image or geometry validity signal.

[Image clearing][clear] removes Kitty display and line-height properties from the
viewport. It preserves materialized scrollback images, subject to orphan-fragment
cleanup.

[Virtual placement emission][emission] passes only image bytes and a PNG flag to
Elisp. The callback receives no image ID or placement ID. The virtual branch has
no placeholder-presence check before conversion and copying.

[Image conversion][conversion] normally creates PPM data from decoded pixels.
The virtual branch then calls `makeUnibyteString` before the Elisp callback.
An Elisp-only cache hit cannot avoid these upstream costs.

The [virtual-image callback][virtual] measures the maximum placeholder count per
row and the number of matching rows across the accessible buffer. It then applies
per-row slices in a second full-buffer traversal.

The IDE [launch configuration][launch] explicitly sets
`PI_FORCE_IMAGE_PROTOCOL=kitty` for graphical OMP sessions using Ghostel.
It sets `off` for the corresponding non-graphical case.
This enables the image path. It does not itself perform the expensive scans.

## Live probes

The probes called the real loaded `ghostel--kitty-display-virtual` through
`emacsclient`. Its reported source was the sibling Ghostel checkout's
`lisp/ghostel-kitty.el`.

Each probe used a temporary buffer and valid one-pixel PPM data. No existing
terminal buffer or persistent configuration changed.

### Clearing invalidates display without changing characters

The probe inserted two rows of three placeholders, displayed an image, recorded
both modification ticks, and called `ghostel--kitty-clear`.
It set `ghostel--term-rows` to two so the rows formed the viewport.

```text
Image displayed before clear:       yes
Image displayed after clear:        no
Character tick unchanged:           yes
Full modification tick unchanged:   no
```

A character-tick guard after clearing would skip required image restoration.
A full-tick guard can instead invalidate itself because clearing changes text
properties.

### Image content changes without character changes

The probe displayed red image data, then blue image data over unchanged
placeholders.

```text
Character tick unchanged:           yes
Display specification changed:     yes
New image data applied:             yes
```

The character tick alone cannot detect image-content changes.

### Grid dimensions change for identical image data

The probe displayed the same image over two three-placeholder rows. It then
added a five-placeholder row and called the callback with identical image data.

```text
Initial display width:              30 pixels
Display width after layout change:  50 pixels
Callback error:                     nil
```

The observed cell width was ten pixels. Image identity does not determine
placeholder grid dimensions.

### Direct callback timing

For each buffer size, the probe inserted ordinary text rows. One variant had no
placeholders. The other appended two rows of three placeholders.

Each result is the median of three batches of ten calls, using `benchmark-run`.
The probe bound `gc-cons-threshold` to `most-positive-fixnum` during measurement.

| Ordinary text rows | No placeholders, ms/call | Two placeholder rows, ms/call |
| ---: | ---: | ---: |
| 100 | 0.1127 | 0.1381 |
| 1,500 | 1.7109 | 2.0179 |
| 6,000 | 7.0693 | 8.3559 |

All callbacks reported no error. Cost grew with unrelated text, including when
no placeholders existed.

These are callback measurements, not full-frame measurements. They exclude
native conversion, image-string copying, and final screen display. They do not
measure GC cost or prove an end-to-end speedup for any proposed change.

## Existing invalidation support found during documentation

The bundled [ImageStorage source][storage] already provides a `generation`
stamp. Content mutations update it, including image add or replacement, placement
changes, and deletion. Scrolling and resizing do not update it.

The source also documents a `dirty` flag for content or geometry changes.
An unchanged generation therefore does not imply unchanged placement geometry.

Each stored image has a generation stamp. The add/replace path assigns a fresh
stamp even when the image ID and dimensions remain the same.
The bundled [C wrapper][c-wrapper] exposes storage and image generations.

These existing stamps materially reduce Option 1's identity-tracking cost.
A native implementation need not hash image bytes or invent image-ID lifetime
tracking to detect content changes.

This finding comes from the current bundled source. The live probes did not
establish whether the loaded native module contains these generation changes.
An implementation must verify its build baseline before relying on them.

The dependency source contains generation tests, including same-sized image
replacement and screen/reset cases. This research did not execute those tests.

## Option 1: Cache complete placement state

### Benefit

[INFERENCE] A valid no-op decision before clearing and emission could avoid both
scans, image reconstruction, native conversion, and image-string copying.
This has the largest potential benefit of the three original options.

A separate image-data cache can also help when display properties need
restoration but image content has not changed.

### Required design

The cache must coordinate with clearing. A cache hit inside the callback occurs
after clearing has already removed the image.

The terminal renderer can also replace text carrying image properties before
clearing runs. The no-op decision must account for that replacement.

Use the existing native signals rather than a custom identity scheme:

- Storage generation for image and placement content changes.
- Image generation for reusable converted image data.
- Renderer repaint state for buffer regions that need display restoration.
- Geometry state for font metrics, terminal size, viewport movement, and scrolling.
- Explicit invalidation for screen changes, full redraws, and scrollback eviction.

The exact guard remains a design to verify, not an implemented predicate.
`ghostel--repainted-region` is a better initial probe than either tick alone,
because it describes renderer work. Nil repaint state does not establish that
image state, geometry, or all cleanup requirements are unchanged.

Any retained converted data also needs clear ownership and release rules.
Raw image bytes can become invalid after storage mutation, as documented in
[ImageData lifetime comments][conversion].

### Workload limitation

[INFERENCE] A whole-buffer character tick would invalidate on unrelated streaming
output. It could produce few hits during the problem workload.

A conservative renderer-aware guard may have the same limitation when any
repaint requires restoration. Converted-image reuse can still save upstream work
on those frames. Selective region restoration requires further correctness work.

### Assessment

Viable and more attractive than the original evaluation suggested, because
native generation tracking already exists. It remains more complex than changing
the scan algorithm alone.

This is a strong candidate for unchanged-frame and repeated-conversion costs.
Keep image-data reuse separate from display-property restoration. Their
invalidation conditions differ.

## Option 2: Guard with the character-change tick

### Benefit

The comparison is cheap and requires little state.

### Correctness failures

Both failures occurred in live probes:

- Clearing removes the image without changing the character tick.
- New image content changes the display without changing the character tick.

Font metrics and placement state also exist outside the character tick.
Switching to `buffer-modified-tick` is not a complete fix. Property clearing
changes that tick, while native image changes still require separate tracking.

### Workload limitation

[INFERENCE] Unrelated streaming text invalidates the tick even when the image is
unchanged. The guard misses relevant non-text changes and reacts to irrelevant
text changes.

### Assessment

Reject as a standalone optimization. A tick may supplement a complete validity
check, but that makes it part of Option 1 rather than a separate solution.

## Option 3: Cache grid dimensions per image ID

### Benefit

[INFERENCE] A valid cached grid could avoid the first measurement pass.
It leaves the second buffer scan, display restoration, image creation, native
conversion, and image-string copying.

The profile does not establish an exact speedup from removing the first pass.
Nested sample percentages must not be added as independent costs.

### Correctness failures

The live probe changed the required grid width while image data remained
identical. Grid dimensions describe placeholder layout, not merely image content.

Image generation therefore does not solve layout invalidation either.
The current Elisp callback also lacks image identity.

A limited buffer-local cache of cell counts could safely use
`buffer-chars-modified-tick`, `point-min`, and `point-max` as its key.
The counts depend only on placeholders within that accessible text.
Property clearing would not invalidate it. Font changes affect pixel dimensions,
not the cached cell counts. Geometry changes require no separate invalidation
unless they change those inputs. This limited cache saves only the first pass.

Cached dimensions do not identify the row spans needed by the second pass.
Caching positions adds invalidation requirements for edits and scrollback eviction.

### Assessment

Do not add an image-ID-only grid cache. The limited text-keyed cell-count cache
is viable, but streaming text would invalidate it frequently.
Keeping dimensions and row spans within one callback avoids persistent state
and removes the second scan as well.

## Alternative: One search pass with per-call row records

The measured callback cost grows with ordinary text rows. A smaller change can
remove repeated Elisp work on those rows without persistent cache state:

1. Search directly for the next placeholder across the buffer.
2. Record each matching row's span and placeholder count.
3. Compute grid dimensions from those records.
4. Create the image only when matching rows exist.
5. Apply slices to the recorded spans.

[INFERENCE] This should reduce interpreter overhead on ordinary rows and remove
the second buffer traversal. The underlying buffer search still has a cost.
Temporary storage grows with matching rows.

This alternative keeps the existing clear-and-restore sequence. It does not
require a cross-language identity interface or cache eviction rules.
It does not save native conversion or copying before the callback.

Do not restrict the scan to the viewport without a separate geometry analysis.
Images that cross into scrollback need correct dimensions, slice offsets, and
preserved history. This proposal does not establish new multi-image placeholder
matching semantics either.

## Revised ranking

| Approach | Assessment |
| --- | --- |
| Single search pass with per-call row records | Preferred first experiment for the measured text-scan cost. Limited persistent-state risk. |
| Option 1 using existing generations and renderer/geometry state | Strong candidate for unchanged-frame and conversion costs. No custom content hashing needed. |
| Option 3: persistent grid cache | Conditional. Needs layout validity and removes only part of the work. |
| Option 2: tick-only guard | Reject alone. Live probes established correctness failures. |

The first two approaches address different costs and can coexist.
The user selected the single-search change for implementation.
Persistent caching remains unimplemented. Its value needs separate measurements
of conversion cost and cache hit rate.

## Broader verification matrix for cache changes

### Behavioral cases

- Unchanged redraw preserves the visible image.
- Image replacement updates pixels without placeholder text changes.
- Placement deletion removes old display properties.
- Text repaint restores affected image slices.
- Resize and font changes produce correct slice dimensions.
- Screen changes and full redraws do not reuse stale display state.
- Scrollback promotion and eviction preserve or remove the correct fragments.
- A virtual placement without matching placeholders avoids unnecessary scan work.
- Multiple placements do not reuse another placement's geometry or content.

### Performance and causal checks

1. Capture a representative full redraw with image output enabled.
2. Compare an equivalent fresh OMP process with `PI_FORCE_IMAGE_PROTOCOL=off`.
3. Measure callback time, redraw time, and conversion work separately.
4. Use allocation profiling to investigate the GC contribution.
5. Measure cache hit rate during active streaming, not only static redraws.

Existing processes retain their launch environment. Changing the parent environment
does not change their selected image protocol.

The protocol-off comparison is diagnostic, not a proposed permanent removal of
image support. This research did not run that comparison or start a fresh OMP
process. The later implementation changed and reloaded Elisp only.
It did not rebuild the native module.

## Implementation results

The callback now searches directly for placeholders, counts each matching row,
and records its start and end positions. It applies slices from those records.
It preserves maximum row width, row order, newline clamps, and narrowing.
No persistent cache or native interface change was added.

### Before and after

The same live callback benchmark ran immediately before the change and after
`load-file` loaded the edited Elisp. Both runs used interpreted Elisp.
Each result is the median of three batches of ten calls with GC suppressed.

| Ordinary rows | Placeholder rows | Before, ms/call | After, ms/call |
| ---: | ---: | ---: | ---: |
| 100 | 0 | 0.1173 | 0.0073 |
| 100 | 2 | 0.1471 | 0.0146 |
| 1,500 | 0 | 1.7174 | 0.0137 |
| 1,500 | 2 | 2.0603 | 0.0275 |
| 6,000 | 0 | 7.2625 | 0.0574 |
| 6,000 | 2 | 8.2960 | 0.0483 |

These measurements cover the callback only. They do not establish a whole-Emacs
speedup, a GC reduction, or reduced native image-conversion cost.
The smallest timings contain measurement noise.

### Verification completed

- Ghostel Kitty Elisp byte compilation passed with warnings treated as errors.
- All 29 non-native Kitty tests passed against the compiled implementation.
- New regression checks cover sparse unequal rows, narrowing, final lines without
  newlines, and absent placeholders.
- The absent-placeholder regression failed against the original function and
  passed against the new function.
- A throwaway differential check compared 100 deterministic layouts.
  Text properties, point, active state, and error state matched the old renderer.
- A live native smoke check sent a real Kitty virtual-image transmission through
  `ghostel--write-vt` and `ghostel--redraw`, without mocked image functions.
  Emacs decoded a 30-by-42-pixel image with a `(slice 0 0 30 21)` first slice.
  A repeated full redraw preserved the display specification without an error.
- Live direct probes still restored images after clearing and adjusted grid width
  from 30 to 50 pixels after a placeholder-layout change.
- The IDE's required `./scripts/compile-and-test.sh` passed:
  797 tests passed, nine skipped, and zero unexpected results.
  The script reported dependency-obsolescence and test-macro compilation warnings.

The native smoke check verified image decoding and buffer display state.
It did not include a screenshot or a full OMP workload profile.
The edited source is active in live Emacs. No Emacs restart was required.
The throwaway probes used temporary buffers or separate batch processes.
No probe file or persistent instrumentation remains.

## Follow-up: GC after the scan fix

The live CPU report `*CPU-Profiler-Report 2026-09-08 04:09:13*` showed:

| Entry | Samples | Reported share |
| --- | ---: | ---: |
| Automatic GC | 27,325 | 65% |
| Timer handler | 7,213 | 17% |
| Redisplay | 4,745 | 11% |
| Ghostel event filter | 2,375 | 5% |
| Virtual-image callback within the event-filter branch | 373 | 0% rounded |

The last row overlaps the event-filter row. Its share is below 1%.
The report confirms that GC is now the main sampled cost.
It does not prove that absolute GC time increased after the scan fix.

### Allocation capture limitations

A separate memory capture ran for approximately 23 seconds.
It recorded three collections totaling 0.727 seconds.
The live report remains available as
`*Memory-Profiler-Report 2026-09-08 04:10:48*`.

The raw log had approximately 1.69 GB of sample weight with an empty Lisp stack.
The rendered call tree omitted that bucket. Its visible percentages therefore
must not be treated as percentages of all recorded sample weight.
Large visible entries included a Magit wait loop and Savehist serialization.
Wait-loop attribution can include native event processing rather than the
waiting function's own data structures.

A later ten-second passive image-payload probe observed no virtual-image
callbacks. This quieter interval did not reproduce the reported workload.
The memory profile alone was insufficient to identify the allocation source.

### Direct redraw measurements

Temporary before-advice counted callback invocations and `length(data)`.
It did not replace or suppress the callback.
The probe also compared `memory-use-counts` around real native redraw calls.
It removed the advice with `unwind-protect`.

| Existing buffer | Virtual callbacks per redraw | Image payload bytes per redraw |
| --- | ---: | ---: |
| `*claude-code[claude-code-ide.el]*` | 12 | 19,090,013 |
| `*claude-code[claude-code-ide.el]*<2>` | 0 | 0 |

Three further consecutive redraws of the first buffer each copied exactly
19,090,013 image bytes. The string-character allocation counter increased by
approximately the same amount on each redraw.

That buffer contained zero U+10EEEE placeholders when inspected.
Its `ghostel--kitty-active` was nil and it had no recorded Kitty error.

This demonstrates redundant native image-payload copies before the Elisp
callback can discover that there is no image to display.
The retained virtual placements still reach [conversion and emission][emission].
The single-search change avoids scanning each ordinary line, but does not avoid
these upstream copies.

The live GC threshold was 100,000,000 bytes, with percentage 0.1.
One explicit collection took 0.224 seconds. It reported approximately 8.35 million
live cons cells, 775,000 strings, and 311 buffers.

[INFERENCE] Repeated 19 MB payload copies can create substantial GC pressure
during active redraw. Five redraws copy roughly 95 MB of image data alone.
This is a concrete allocation source, not proof that it accounts for every GC
sample in the earlier CPU report.

### Implemented change

The native guard now checks for virtual-image placeholders before conversion and
`makeUnibyteString`. It shares that check across placements within a redraw.
When no placeholders exist, it skips virtual-image payload emission.
Pinned placements and the existing clear-and-restore behavior remain unchanged.

Retained image data remains available for later reuse.
See [native guard verification](#native-guard-implementation-and-verification).

This targeted absence check is simpler than a complete persistent placement
cache and addresses the measured case directly. Image-data generation caching
remains a separate option for repeated redraws with visible images.

The initial diagnosis ended without source changes or agent restarts.
Implementation and activation followed, as recorded below.
The diagnostic profiler was stopped and temporary advice was removed.

## Native guard implementation and verification

The native placement loop now calls `ghostel--kitty-placeholders-p` lazily for
the first virtual placement in each redraw. It reuses that result for the
remaining virtual placements in the same redraw.

When no placeholders exist, the loop skips virtual placements before
`getImageData` and `makeUnibyteString`. It still processes pinned placements.
The predicate preserves point and searches the same accessible buffer region
as the virtual-image renderer.

No persistent cache, image deletion, or GC-threshold change was added.
The stored images remain available when the application writes placeholders later.

### Regression and build results

The new native regression transmits a 512-by-512 RGB virtual image, then
measures three redraws without placeholders.

- Before the native change, those redraws allocated 2,359,362 string characters.
  The allocation-bound assertion failed.
- With the rebuilt module, the regression passed. It also verified that the
  retained image rendered when a placeholder appeared, without retransmission.
  Overwriting the placeholder removed its display property.
- All 31 Kitty tests passed in a fresh batch Emacs using the rebuilt module.
- Zig 0.16.0 built the module with `ReleaseFast` and baseline CPU settings.
- The changed Elisp compiled with warnings treated as errors.
- The required IDE verification passed: 797 passed, nine skipped, zero unexpected.
  Its compilation reported existing test and dependency warnings.

### Separate graphical Emacs smoke check

A separate Emacs daemon loaded the staged native module and created a graphical
frame. The smoke check used the real native renderer and image decoder.
It did not mock image functions.

The synthetic terminal retained 12 virtual images of 512-by-512 pixels each.

| Observation | Result |
| --- | ---: |
| Redraws without placeholders | 20 |
| Placeholder-presence queries | 20 |
| Virtual-image callbacks | 0 |
| Image payload bytes copied | 0 |
| Total string-character allocation during those redraws | 140 |
| Retained-image callbacks after placeholders appeared | 12 |
| Decoded displayed image size | 21 by 28 pixels |
| Pinned-image callbacks with virtual placeholders absent | 1 |
| Recorded Kitty error | nil |

This proves the absent-image allocation path no longer copies pixel payloads.
It also exercises image reuse and pinned placement emission.
It does not measure whole-session GC reduction in the user's original workload.

### Installation and activation

The verified module and version sidecar were installed through
`ghostel--install-module-pair`. This replaces the module by rename rather than
overwriting the mapped library in place.
The installed module's SHA-256 matched the staged binary:

```text
a74d20d4c17898967a4b920374947d67b0f9a0b6d53cc2bffb3f6f92895a4ec0
```

At installation time, the main Emacs still had the old native module mapped.
Reloading Elisp alone could not activate the native guard.
The user subsequently restarted Emacs.

A smoke check in the restarted live Emacs sent a real virtual-image transmission.
Three redraws without placeholders produced zero virtual-image callbacks.
Adding placeholders then rendered the retained image without retransmission.
The real image decoder reported a 30-by-42-pixel image.
The probe used a temporary buffer and removed its advice afterward.

The native guard is now active in live Emacs. Restarting only an agent or
creating a new Ghostel buffer would not have loaded the rebuilt native module.
The earlier no-restart statement applied only to the Elisp single-search change.

The separate smoke-check Emacs was stopped. Temporary advice and the empty
staging directory were removed. Existing user agents were left running.

## Paired profiles after restart: 04:36:11

The user supplied matching CPU and memory reports:

- `*CPU-Profiler-Report 2026-09-08 04:36:11*`
- `*Memory-Profiler-Report 2026-09-08 04:36:11*`

Both reports were expanded and read through `emacsclient`.
No new profiler capture replaced the user's data.

### CPU findings

| Entry | Samples | Reported share |
| --- | ---: | ---: |
| Main queued plain-link detection branch | 8,091 | 37% |
| Its `file-exists-p` descendant | 5,081 | 23% |
| Top-level redisplay | 7,602 | 35% |
| Its frame-title preparation descendant | 1,116 | 5% |
| Its Spaceline modeline descendant | 975 | 4% |
| Timer-driven Ghostel redraw | 2,591 | 11% |
| Automatic GC | 1,749 | 8% |
| Top-level Ghostel event filter | 297 | 1% |

Descendants overlap their parent rows. The percentages must not be added.
Kitty no longer appears as a sampled callback hotspot in this report.

GC's reported share changed from 65% in the earlier capture to 8%.
The captures are not a controlled comparison. Their percentages do not establish
an absolute speedup or isolate the effects of restarting Emacs.

### Memory findings

The main queued link-detection branch accounts for 310,909,190 bytes of reported
sample weight, or 42% of the rendered report.

| Descendant within that branch | Reported sample weight |
| --- | ---: |
| Soft-wrap region assembly | 166,706,272 bytes |
| Its substring copies | 83,353,136 bytes |
| Its joined-string construction | 83,353,136 bytes |
| File-existence checks | 111,710,962 bytes |
| Their macOS filename normalization | 107,054,980 bytes |

The source [copies region pieces and joins them][link-join] before detection.
The [file-reference pass][link-detection] checks candidate paths with
`file-exists-p`. Its `seen` hash caches both positive and negative results, but
only for the current detector call.

The raw memory log contains 807 entries and no all-nil vector bucket.
Its total sample weight is 738,046,739, including an `Automatic GC` accounting
entry of 42,869. No discarded-sample entry was present.
The current `profiler-log-size` is 10,000.
These are profiler sample weights, not retained heap size or an allocation rate.

### Repeated-scan probe

A private copy of the current target terminal contained 228,531 characters.
The probe preserved text properties and used the real detector and filesystem.
Temporary advice counted file-existence checks without printing file paths.
No source terminal buffer changed.

| Scan of the same copy | Time | File checks | Missing results | Unique checked paths |
| --- | ---: | ---: | ---: | ---: |
| First | 20.34 ms | 171 | 149 | 166 |
| Second | 19.71 ms | 149 | 149 | 145 |

Existing successful links avoided further checks. Missing references still
caused filesystem work in the second scan.
This full-copy probe demonstrates repeated checks across detector calls.
It does not imply that each production timer scans the entire buffer.
The [queued detector][link-queue] processes chunks and expands their bounds to
logical lines.

### Next optimization target

Prioritize plain-link detection, not Kitty scans or a higher GC threshold.

- Reduce unnecessary text copies when soft-wrap joining is not required.
- Reduce repeated missing-path checks across unchanged scan work.
  Any cache design must handle files created later and directory changes.
- Preserve clickable URLs, file references, and native OSC 8 links.

Redisplay is the second large CPU category. Frame-title preparation includes
990 samples in `system-name`. That is a separate target after link detection.

No code or persistent configuration changed during this analysis.
The temporary filesystem advice was removed, and no profiler remains active.

## Latest CPU capture: 04:43:51

The report `*CPU-Profiler-Report 2026-09-08 04:43:51*` shifts the priority toward
redisplay and window anchoring.

| Work | CPU samples | Reported share |
| --- | ---: | ---: |
| Top-level redisplay | 8,042 | 52% |
| Its Spacemacs frame-title preparation | 1,110 | 7% |
| Its Spaceline modeline | 1,094 | 7% |
| Timer-driven Ghostel redraw | 2,784 | 18% |
| Its pixel-position measurement | 1,446 | 9% |
| Its native `ghostel--redraw` branch | 652 | 4% |
| Ghostel event filter | 1,157 | 7% |
| Its buffer-title identification update | 659 | 4% |
| Automatic GC | 1,023 | 6% |
| Queued plain-link detection | 514 | 3% |
| Its filesystem-existence checks | 371 | 2% |

Descendants overlap their parent rows. Most redisplay samples have no more
specific Lisp child, so this report does not resolve all native display costs.

The current runtime has URL detection disabled and file detection enabled in
the inspected Ghostel buffers. This observation does not establish the settings
throughout the capture or make the previous capture a controlled comparison.
No settings were changed during this inspection.

### Avoidable empty frame-title work

The current `dotspacemacs-frame-title-format` is an empty string.
However, `frame-title-format` still evaluates [spacemacs/title-prepare][frame-title].
That function unconditionally calls `system-name` while constructing its format
table. The profile attributes 954 samples, or 6%, to that call.

Calling the current title formatter returned an empty string, as configured.
Using an empty native `frame-title-format` would preserve that result without
evaluating the Spacemacs formatter. This is the smallest next candidate.
It has not been applied or measured as an end-to-end change.

### Other remaining work

The pixel-position cost follows `ghostel--anchor-window` through
`ghostel--balance-top-pad` and [ghostel--pixel-anchor][pixel-anchor] to
`window-text-pixel-size`. This is layout measurement, not Kitty payload copying.
Any reduction must preserve bottom anchoring and variable-height rows.

Ghostel's separate terminal-title path spends about 4% updating buffer
identification. Its format currently uses `%b` and `%t`, but the formatter also
[computes the unused `%d` directory value][buffer-title].

For this workload, investigate title formatting and pixel anchoring before
adding a persistent link-detection cache. GC remains a smaller cost.
Different report percentages do not establish absolute speed changes.

## Source references

Paths below refer to the sibling Ghostel checkout and this IDE checkout.
The bundled dependency path is specific to the inspected installation.
Line numbers describe the inspected source and can move after later edits.

[redraw]: ../../../ghostel/src/GhostelTerm.zig#L83
[renderer]: ../../../ghostel/src/Renderer.zig#L147
[clear]: ../../../ghostel/lisp/ghostel-kitty.el#L289
[virtual]: ../../../ghostel/lisp/ghostel-kitty.el#L235
[emission]: ../../../ghostel/src/kitty_graphics.zig#L15
[conversion]: ../../../ghostel/src/kitty_graphics.zig#L101
[scheduling]: ../../../ghostel/lisp/ghostel.el#L4283
[launch]: ../../claude-code-ide.el#L1830
[storage]: ../../../ghostel/zig-pkg/ghostty-1.3.2-dev-5UdBC-mtJAXcrDxuFuetC6X66XQXV8hw_7pevfmFcVKL/src/terminal/kitty/graphics_storage.zig#L74
[c-wrapper]: ../../../ghostel/zig-pkg/ghostty-1.3.2-dev-5UdBC-mtJAXcrDxuFuetC6X66XQXV8hw_7pevfmFcVKL/src/terminal/c/kitty_graphics.zig#L51
[link-join]: ../../../ghostel/lisp/ghostel-links.el#L334
[link-detection]: ../../../ghostel/lisp/ghostel-links.el#L502
[link-queue]: ../../../ghostel/lisp/ghostel-links.el#L785
[frame-title]: ../../../../../.emacs.d.spacemacs-32/core/core-dotspacemacs.el#L1092
[pixel-anchor]: ../../../ghostel/lisp/ghostel.el#L4461
[buffer-title]: ../../../ghostel/lisp/ghostel.el#L3458
