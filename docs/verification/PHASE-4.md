# Phase 4 — thumbnail pipeline

Date: 12 September 2026. Implementation and acceptance in progress.

## Implemented boundaries

- Shared encoded pipeline for grid and Info, independent consumer cancellation and coalescing.
- Two logical source slots, 64 queued requests, visible-first scheduling and at most one active
  prefetch-only request. DeviceCapture independently retains its two actual callback-lifetime slots.
- Encoded memory: 32 MiB / 512 items; disk: 256 MiB / 2,000 items; individual payload: 16 MiB.
  Decoded bitmap cache: 64 MiB / 256 items, counted by bitmap allocation and serially decoded.
- Actual viewport geometry becomes three demand bands. Prefetch covers one nearby row above and
  two below among instantiated lazy cells; far cells cancel their demand and release displayed images.
- Structured versioned keys include modification evidence. Unique complete-catalog metadata and
  persistent device identity can reuse disposable previews across reconnects in the same process.
  Session-only entries and retired results cannot be reused. Startup clears prior runtime namespaces.
- Owned disk namespace, bounded reads, atomic writes, key/length/digest validation and LRU eviction.
  IO failure leaves browsing available through the source and memory caches.
- Privacy-safe Debug metrics distinguish logical pipeline loads from actual framework operations.

## Automated verification

- 156 core tests pass: 31 thumbnail pipeline, 24 models, 52 catalog and 49 device capture.
- 22 hosted app tests pass, including bitmap costs/eviction, orientation, metadata keys,
  shared grid/Info decoding, independent cancellation, retired sessions and nil→same-UUID races.
- Final normal Debug build is warning-free; strict SwiftLint and whitespace checks pass.
- Normal sandbox signature verifies. Entitlements are sandbox, USB, photo-library access and
  Debug get-task-allow only; test-host additions were removed by the normal rebuild.
- Logs: `/tmp/cloakroll-phase4-core-tests.log`, `/tmp/cloakroll-phase4-app-tests.log`,
  `/tmp/cloakroll-phase4-normal-build.log`. These are local validation outputs, not repository artifacts.

## Physical acceptance

A normal sandboxed intermediate build (PID 94051) displayed all 1,893 logical items in the current
USB catalog. Compact 860-point layout, real photo/Live Photo thumbnails and Info were inspected.
Info reused its grid bitmap: source loads stayed at 8, decodes stayed at 6, and decoded hits rose
from 0 to 1. Rapid down/up scrolling showed placeholders resolving to the current viewport.

| Observation | Source loads | Decodes | Decoded bytes / items | Encoded bytes / items | RSS KiB |
| --- | ---: | ---: | --- | --- | ---: |
| Initial viewport | 8 | 6 | 4,521,984 / 6 | 426,336 / 8 | 176,288 |
| First long pass | 112 | 71 | 51,617,792 / 71 | 6,613,105 / 111 | 360,304 |
| Further scrolling | 197 | 127 | 66,830,336 / 92 | 12,096,548 / 196 | 481,056 |
| Later scrolling | 275 | 179 | 66,953,216 / 87 | 16,894,596 / 274 | 530,336 |

Decoded eviction is demonstrated by 179 decodes with only 87 retained entries and costs below
67,108,864 bytes. Actual ImageCaptureCore request high-water stayed at **2**, adapter queue
high-water at **1**, and logical work returned to active=0 / queued=0. One source returned
`ICReturnThumbnailNotAvailable` (-21000); no decode or disk-cache errors were observed.

Total process memory is separate from cache costs. Two heap snapshots showed physical footprint
355.7→404.0 MiB and a constant 98 ImageIO image-provider objects. SwiftUI layout/environment and
accessibility state grew during repeated full accessibility inspection; this is not proof of an
unbounded image cache or of a total-process plateau. The final code removes the per-cell visibility
environment override and passes that value directly to the thumbnail, preserving its pixels.
No quantified benefit is claimed for this small refinement before a comparable follow-up run.

At the initial final-build check, the refined build (PID 94498) was open, but macOS exposed no camera library despite
the phone remaining attached in IORegistry. Unlock was requested. Final scrolling/footprint and
physical unplug→reconnect cache reuse remain **pending**; Phase 5 has not started.
No original file was requested or downloaded during that stage.

### Follow-up during Phase 5

The same refined process subsequently displayed the 1,893-item library. At 17:24–17:29 on
12 September, rapid multi-page scrolling increased source loads from 8 to 105 and decodes from
6 to 59. At rest, decoded cost was 40,532,160 bytes / 59 entries; encoded cost was 6,027,862 bytes /
104 entries. There were 16 encoded hits and 4 decoded hits, zero decode/disk errors and one
unavailable source thumbnail. Actual framework high-water remained 2, queue high-water 1, and
all 105 requests settled. Initial RSS was 166,176 KiB; a comparable final footprint was not taken.

This confirms final-code real scrolling and bounded request behavior. It does not establish a
process-memory plateau or physical reconnect cache reuse, which remain pending. The user
authorized Phase 5 implementation while those checks stay recorded. Original-file acceptance
for that phase is recorded separately in `PHASE-5.md`.

## Limits

Preview metadata matching is not content identity and never marks an original backed up. Apple
may omit originals or thumbnails over USB. Cache costs exclude framework/rendering/transient
allocations; RSS evidence is separate. A request that never calls back after unplug retains its
actual source slot. macOS 14 API availability is compiled; this Mac runs macOS 27.0 (26A428).

## 4 October — prepare the next rows before cell creation

The prior geometry band only prefetched instantiated LazyVGrid cells and warmed
encoded data. A cell becoming visible still needed a bitmap decode. The grid now
indexes actual section rows independently of lazy cell construction, selecting two
rows below and one above the visible rows, capped at 32 speculative items. Section
breaks and partial rows are respected. Indexing runs off the main actor after a
catalog/layout change; row slices share immutable section storage instead of copying
every asset into another set of arrays. Scrolling only consults the visible IDs and
nearby row boundaries.

One speculative consumer warms both encoded data and the existing decoded cache.
Visible cells retain higher pipeline priority and share in-flight requests. Moving
away cancels obsolete consumers; entering a prefetched row preserves its shared
request. Filter/column/session changes replace the plan safely. Pause preserves
current geometry for unavailable-to-ready transitions, and cells report visibility
again when returning from another view. Retired and cancelled work cannot alter a
replacement worker or decode into a replacement session.

No cache budget, USB concurrency or physical callback-ownership rule changed:
32 MiB encoded memory, 256 MiB encoded disk, 64 MiB decoded memory, two logical
source slots and at most one prefetch-only source request. Offscreen cells retain
no extra displayed bitmap; the bounded shared decoded cache owns warmed images.

### Verification

- All **338 core tests** and **139 hosted app tests** pass. Fourteen new app tests
  cover uncreated rows, partial sections, resize, the 32-item cap, one worker,
  visible promotion, obsolete/late cancellation, pause/resume, filtering, warm
  bitmap reuse and retired/shared consumers. Independent read-only review found
  no remaining concrete correctness issue.
- XcodeGen, normal Debug and Release builds, strict lint, whitespace and both
  signatures pass. Normal Debug was rebuilt after testing to remove hosted-test
  PlugIns. Tests produce the existing system shortcut-service diagnostics and the
  expected invalid-image fixture decoder message; no compiler warnings were added.
- Physical iPhone library: 2,071 items on macOS 27.0.1 (26A434), Xcode 27.0
  (27A266a). The same standard window, four-column layout and first viewport were
  measured before and after the change using the normal app's Debug metrics.

| Initial viewport, before any scroll | Before | After |
| --- | ---: | ---: |
| Source loads / encoded entries | 20 / 20 | 20 / 20 |
| Decoded bitmaps ready | 12 | 20 |
| Decoded cache bytes | 8,650,752 | 14,942,208 |
| Active / queued work when sampled | 0 / 0 | 0 / 0 |
| Decode / disk failures | 0 / 0 | 0 / 0 |

The eight additional ready bitmaps correspond to two four-item upcoming rows.
The source-load count and encoded byte count (1,018,029) were unchanged. This is
direct readiness evidence, not a frame-time or zero-pop-in guarantee.

A later controlled scrollbar jump added exactly 24 source loads and 24 decodes,
matching 12 visible plus eight ahead and four behind. The counters then remained
unchanged across a separate stationary check 24 seconds later (196 total loads,
242 decodes, 1,341 decoded hits, active=0/queued=0). Decoded cache cost was
66,496,704 bytes / 90 entries, below its 67,108,864-byte limit; total decodes exceeding
retained entries demonstrates eviction. Decode and disk failures remained zero.
One earlier long automation interval was not isolated enough to attribute its
additional loads to a specific scroll input; it is excluded from that comparison.

Real thumbnails were visually inspected after scrolling, and navigation to History
and back to All Photos was exercised. The app is left in live All Photos at the top,
standard size and System appearance. No original-file backup or source mutation
was requested during these checks. Prior test-copy badges correctly cleared when
the phone reconnected to the empty verification folder.

This does not establish instrumented frame latency, a total-process memory plateau,
or guaranteed readiness when rapidly jumping past the lookahead window. Physical
disconnect during thumbnail work, system accessibility variants and macOS 14 runtime
were not repeated. Existing phase acceptance limitations remain explicit.

Logs: `/tmp/cloakroll-lookahead-core-tests.log`, `/tmp/cloakroll-lookahead-app-tests.log`,
`/tmp/cloakroll-lookahead-build.log`, `/tmp/cloakroll-lookahead-release.log`,
`/tmp/cloakroll-lookahead-baseline-metrics.log`, `/tmp/cloakroll-lookahead-first-viewport.log`,
`/tmp/cloakroll-lookahead-jump-metrics.log`, and `/tmp/cloakroll-lookahead-settled-metrics.log`.

## 4 October — display prepared images before the viewport boundary

The user still observed blank rows after the cache lookahead change. Investigation
found a separate presentation gap: MediaCell reduced nearby demand to `.none`,
clearing its image. A warm bitmap was only adopted after a visible geometry update
and asynchronous cache lookup. Cache readiness alone did not establish display readiness.

Instantiated nearby cells now request and display the bitmap with prefetch priority.
The same image survives both directions across the nearby/visible boundary without
being cleared or reloaded. Far-away/disappearing cells still release their reference;
changed keys and cancelled requests cannot install an old result. The existing
catalog lookahead still prepares images for cells not yet instantiated. Cache limits,
serial decoding and physical source limits are unchanged. Unlike the preceding
stage, nearby cells may retain references to shared bitmaps within the bounded
geometry band; cache accounting still excludes presentation/framework allocations.

Verification:

- **338 core tests and 146 hosted app tests pass.** Seven new test functions cover
  actual prefetch bitmap delivery into presentation, promotion, demotion, release,
  changed session/metadata, late completion and missing decode results.
- Normal Debug/Release builds, strict lint, whitespace and both signature checks
  pass, with no compiler warnings. The normal Debug app was rebuilt after testing.
- Physical 2,071-item iPhone library, standard 1,100 × 740 window, four columns:
  before the change, scrolling 0.24 pages from the top left the first September row
  blank beneath the glass bar. After the change, the same scroll position
  (AX fraction 0.001816021044479162) displayed that row beneath the glass. Moving
  another 0.1 pages down exposed the prepared images above the bar; returning
  0.1 pages up retained them. These were directly inspected native screenshots.
- At that point the pipeline had 24 source loads/decodes, 24 decoded entries using
  18,087,936 bytes, eight coalesced consumers, no active/queued work, and zero
  source/decode/disk failures. No original-file backup was initiated.

This confirms the reproduced boundary defect was removed at the sampled positions.
It is not a frame-time recording or a guarantee for large jumps beyond prepared
rows. Newly created visible cells and uncached USB thumbnails remain asynchronous.
Instrumented sustained scrolling, total-process memory and older-OS runtime gates
remain open. The phone temporarily disappeared from discovery after app restart,
then became available for the physical check; no mock was substituted.

Logs: `/tmp/cloakroll-presentation-core-tests.log`,
`/tmp/cloakroll-presentation-app-tests.log`, `/tmp/cloakroll-presentation-build.log`,
`/tmp/cloakroll-presentation-release.log`, `/tmp/cloakroll-presentation-metrics.log`.
