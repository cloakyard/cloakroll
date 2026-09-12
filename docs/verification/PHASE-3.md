# Phase 3 — real media catalog

Status: in progress. Metadata implementation is built and tested; physical catalog acceptance and
lazy thumbnails remain pending. Phase 4 has not started.

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

## Verification to date

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

Next within Phase 3: lazy public thumbnail requests with a small outstanding-request bound, then
real-device grid/metadata/scrolling validation. Disk cache and prefetch remain Phase 4.
