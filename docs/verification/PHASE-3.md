# Phase 3 — real media catalog

Status: complete. Physical catalog and thumbnail acceptance passed on 12 September 2026.
The implementation-stage notes below retain their original pending status as historical evidence;
the final hardware check is recorded at the end.

## Metadata stage

- Camera-owned objects stay inside the main-actor adapter. Resource handles have a fresh session
  namespace, and filenames/PTP handles never become persistent asset identities.
- Incremental add/remove/rename callbacks accumulate before a coalesced, replaceable full snapshot
  is published. Newest-only buffering therefore cannot discard resource deltas. Small jobs and
  large batches yield; complete-catalog readiness is separate from session readiness.
- Complete enumeration reconciles folders, media files, sidecars and paired RAW resources. It reads
  already supplied file metadata, without requesting per-file metadata or original bytes.
- A headless assembler classifies via UTI/public RAW evidence and conservatively groups related
  originals. Same names or generic group/related UUIDs do not establish Live Photos. Ambiguous groups
  remain separate, and sidecars attach only to an unambiguous owner.
- Background app assembly serializes work and retains the latest pending full snapshot. Retired
  sessions/revisions cannot replace current data. Sort/search edits use the latest loaded source.
  Incremental arrivals do not reset scrolling; query changes do. Disconnection retains metadata.
- Scan progress and USB/iCloud scope are explicit. A completed scan describes device-exposed media,
  not complete iPhone/iCloud coverage. A closed session remains unavailable until retry opens a new one.

## Metadata-stage verification

- **99 core tests pass:** 24 model, 39 catalog and 36 device tests.
- **9 hosted app tests pass**, including catalog revisions, retired sessions, disconnect retention,
  current queries during rapid snapshots, and scrolling reset semantics.
- Normal Debug build passes without compiler warnings/errors; strict lint and diff whitespace check pass.
- Normal app signature verifies. Entitlements remain sandbox, USB, Photos library and Debug
  get-task-allow only; no test-host file access exceptions or network entitlement.
- Source review confirmed no original download API or thumbnail API invocation in this stage.
- The physical iPhone remains visible in IORegistry, but the rebuilt app has not yet received its
  discovery callback. User unlock/reconnect requested; no real catalog count or classification is
  claimed from mock test logs. Keep the normal app open for that validation.

## Lazy thumbnail stage

- Visible grid cells and Info request public thumbnail data only. The adapter permits thumbnail
  dispatch only for explicitly pending requests; catalog enumeration does not authorize it.
- One app-owned capture context limits actual outstanding framework calls to two, including calls
  from retired browser instances. Queued demand is bounded at 128; cancelled queued requests never
  launch. Active cancellation releases the caller but retains the physical slot until its callback.
- Session/resource validation runs before enqueue and again at launch. Retired or cancelled results
  cannot publish into the current cell. Missing data remains an honest placeholder.
- ImageIO decodes off the main actor, respects orientation and bounds each decoded thumbnail to
  512 pixels. Cell disappearance cancels demand and clears its decoded image. Queue saturation can
  retry with a cancellable delay. Caching, priority and prefetch remain Phase 4.

## Thumbnail-stage verification — 12 September 2026

- **111 core tests pass:** 24 model, 39 catalog and 48 device tests. Added checks cover two-call
  concurrency, bounded queues, cancellation races, retired sessions, synchronous/duplicate callbacks,
  failed data and explicit request permissions.
- **12 hosted app tests pass**, including three decoder tests for bounded dimensions, orientation
  and invalid input. Invalid-image diagnostics come from the deliberate corrupt-input test.
- Strict lint and diff whitespace checks pass. The normal Debug build after hosted tests passes
  without compiler warnings/errors; signature and normal sandbox entitlements verify.
- Independent thumbnail implementation review found no blocking issue.
- Final compact-window sample regression confirms video duration/status badges, selection and Info.
  The broader light/dark, slider and keyboard audit remains recorded in `UI-REFINEMENT.md`.
- No original-download API is invoked. Real device catalog counts, relationships and thumbnails
  are still unverified; simulated callbacks and sample illustrations do not close the hardware gate.
- Final normal launch at 14:48 (process 88016) shows the connect-iPhone empty state. IORegistry
  still lists an attached iPhone; app logs show discovery started but no device callback. The normal
  app is left open, awaiting the already requested physical unlock/reconnect.

Known physical-validation question: if ImageCaptureCore never completes an outstanding request
after unplugging, that slot deliberately remains occupied. Releasing it on a timer would falsely
claim that underlying I/O ended. Measure this behavior during physical interruption checks.

Next: unlock/reconnect the attached iPhone and verify its actual library, metadata, thumbnails and
responsive scrolling in the normal sandboxed app. Do not advance to Phase 4 before that gate passes.

## Physical acceptance — 12 September 2026, 15:27–15:35

The normal sandboxed app (process 89605, committed build `63d0eec`) received the physical phone
after unlock/reconnect. Logs recorded restricted → ready at 15:27:47, physical disconnection at
15:27:56, and rediscovery → ready at 15:28:00. Error -9943 before readiness is the SDK's
`ICReturnDeviceIsPasscodeLocked`; the run recovered without changing entitlements.

- The live UI displayed **1,881 logical media items**: 1,773 still-image items, 108 videos,
  1,143 Live Photo groups and two RAW items. Live Photos and RAW are subsets of still images.
- Real JPEG/HEIC, Live Photo, video and RAW thumbnails appeared. Newly visible video thumbnails
  arrived while scrolling; some requests initially showed placeholders. Cache/revisit behavior is
  part of Phase 4, not a measured performance claim in this gate.
- Info for an actual Live Photo showed two related original resources (HEIC plus MOV). A video
  showed 3840 × 2160 dimensions and a ten-second duration. Both RAW items displayed thumbnails.
- Filename search reduced the RAW collection to the matching item; clearing search restored both.
  Choosing Oldest First reversed their date ordering. Info, filter changes and scrolling responded.
- No original-download API was used. No source media was changed or deleted. No personal images
  or filenames are stored in this evidence file.

Catalog logs reported 3,614 resources before unplugging and a later sequence of 0, 2,127 and
3,602 after reconnect. The current log labels every snapshot whose state is complete as “complete”;
these lines do not establish separate readiness callbacks or complete coverage of the phone.
Counts describe the media exposed by this session only, and do not prove iCloud/Hidden-album
coverage or cross-session resource completeness.

Gate passed: physical device → metadata catalog → classified grid → lazy thumbnails/Info has
been exercised. Phase 4 may proceed after the current UI/performance refinement is committed.
