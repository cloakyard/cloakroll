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
