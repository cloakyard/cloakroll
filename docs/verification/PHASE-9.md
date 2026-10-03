# Phase 9 — measured catalog and history performance

Date: 3 October 2026. Work began from the clean Phase 8 commit `cee5bdc`.
Headless scale measurements are separate from app scrolling and physical iPhone acceptance.

## Measurement method

Release executable on Mac14,6 with 32 GiB RAM, macOS 27.0.1 and Xcode 27. The generated
catalog contains 25% Live Photos: 10k/50k/100k logical items have 12.5k/62.5k/125k original
resource records. Each size runs in a fresh process. Projection, identity and populated
candidate-query figures are medians of three runs. Registration and the group of 100 completion
lookups are single measurements. Timings include the public async API calls.
Generated dates increase by 61 seconds in input order, benefiting projection sorting. This
controlled workload is not a worst-case projection test; projection code did not change here.

After public session registration, one SQL transaction seeds synthetic history in an isolated
temporary database. There is one historical row per resource. This deliberately excludes media
transfer, verification, per-original commits and fsync costs. These rows are not real verified
originals. The harness checks result counts; correctness is established by separate tests.

Peak RSS is whole-process `getrusage`, including fixture construction, identity, registration,
history seeding and matching, reported through the production completion-lookup group. It excludes
the temporary harness's trailing hypothetical-index experiment. It is not the app's memory, the candidate operation's incremental
allocation, a thumbnail-cache plateau or a USB measurement. Repeated real backup sessions may
contain more historical rows than this fixture.

The reproducible harness is under `apps/macos/scripts/PerformanceProbe`. Its README explains
commands, accepted sizes, JSON output and limits. The initial temporary harness used the same
fixture and operations; it additionally tried a hypothetical index after the baseline completion
measurement. That exploratory index step is omitted from the checked-in harness.

## Baseline

| Logical items | Projection median | Identity median | Session registration | All candidates median | Peak RSS |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 10,000 | 7.23 ms | 0.886 s | 1.642 s | 0.335 s | 163 MiB |
| 50,000 | 30.39 ms | 4.499 s | 8.510 s | 1.824 s | 644 MiB |
| 100,000 | 59.67 ms | 9.086 s | 16.909 s | 3.752 s | 1,264 MiB |

At 100k, requesting just one asset still took 2.689 s because the reader materialized all
device/destination history. One hundred logical-asset completion lookups took 2.717 s; an
exploratory fixture-only composite index reduced that group to 4.86 ms. A two-second identity
sample found per-byte Foundation hexadecimal formatting as a substantial CPU hotspot.

## Final measurements

All result-count assertions passed with the final code, after the full test suite and normal app
build. Timed runs were sequential with the app quit and no concurrent builds.

| Logical items | Projection median | Identity median | Session registration | All candidates median | Peak RSS |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 10,000 | 7.19 ms | 0.352 s | 0.868 s | 0.165 s | 142.4 MiB |
| 50,000 | 29.13 ms | 1.856 s | 4.411 s | 1.040 s | 426.9 MiB |
| 100,000 | 65.15 ms | 3.769 s | 8.862 s | 2.256 s | 759.7 MiB |

| Logical items | Empty destination check | One requested asset, median | 100 completion lookups |
| ---: | ---: | ---: | ---: |
| 10,000 | 0.209 ms | 0.209 ms | 5.322 ms |
| 50,000 | 0.240 ms | 0.218 ms | 5.550 ms |
| 100,000 | 0.246 ms | 0.232 ms | 5.473 ms |

At 100k, identity preparation took about 59% less time, full candidate lookup 40% less time, and
session registration 48% less time. Whole-probe peak RSS fell about 40%. The empty-destination
check fell from 655.46 ms to 0.246 ms. A one-asset query against the same history fell from
2.689 seconds to 0.232 milliseconds; this is the public subset-query workload, not a claim that
the app's whole-library verification takes that long. Fresh file hashing is outside these numbers.

Projection varied in both directions; its implementation was unchanged. These observations are
comparisons on one controlled machine/workload, not statistical guarantees or real USB throughput.
Final raw logs remain `/tmp/cloakroll-scale-{10000,50000,100000}.final.jsonl`; initial logs use the
same paths without `.final`. Intermediate `.after` runs preceded the empty-destination shortcut.

## Implemented changes

- Shared package-private lowercase hexadecimal encoding preserves digest inputs and exact output
  while removing per-byte Foundation formatter calls. Existing backup and disposable preview
  keys remain compatible; canonical encoding and SHA-256 are unchanged.
- Additive `v3_session_asset_lookup` migration indexes logical-asset completion by session and
  runtime asset. It changes neither stored evidence nor the completion transaction.
- Candidate queries seek indexed asset/resource digests in batches of 64, then compare both
  complete canonical identities using the existing Swift Unicode semantics. Every eligible
  matching historical row still contributes to ambiguity; older conflicting content or
  destination-root evidence cannot be hidden by a latest-only lookup. Reading uses one database
  snapshot and bounded per-batch cursor accumulation instead of materializing all destination
  history. The returned candidate array still scales with the current requested catalog.
- An indexed existence check returns immediately for a destination with no recorded originals.
  Publication recovery still runs first, and the public device-key validation remains unchanged.

## Correctness and build evidence

- **284 core tests pass** across all six targets, including hexadecimal compatibility, populated
  schema migration, completion/replay and candidate batching regressions.
- Encoding tests cover all byte values, empty input, leading zeros, SHA-256 known vectors,
  pre-change stored keys and Unicode/companion metadata. An independent temporary compatibility
  probe produced identical pre/post JSON for asset, resource, thumbnail and source-signature keys.
- Migration tests retain a verified component and its pending companion journal across a real
  populated-v2 upgrade, recover the companion once and reopen without changing historical status.
- Candidate tests cover empty/single/63/64/65-resource boundaries, duplicate current identities
  across batches, older hash/root conflicts among many newer copies, same-session eligibility,
  persistent reconnect, newest timestamp/row-ID ties, corrupted older matching records and Swift
  canonical Unicode equivalence. Query-plan tests check the actual indexed seeks and reject a
  backup-history scan or temporary sort.
- Independent review found and corrected the SQLite BINARY-vs-Swift Unicode comparison difference.
  No further blocking issue remained in the final review.
- **62 hosted app tests pass**. The final normal Debug build has no compiler warnings; strict
  SwiftLint, whitespace and signature checks pass. Actual normal-build entitlements are unchanged.
  Logs: `/tmp/cloakroll-phase9-core-tests-final.log`, `/tmp/cloakroll-phase9-app-tests.log` and
  `/tmp/cloakroll-phase9-normal-build.log`.
- The checked-in probe passes a clean, warning-free Release build and a 10k smoke run. Its
  resolved dependency remains GRDB 7.11.1 at the same pinned revision used by the core package.

## Manual observations and limits

The normal native app displayed a 100,000-item sample catalog, scrolled through eight pages and
returned visible cells without constructing a 100,000-element accessibility tree. Standard and
860-point compact layouts retained readable counts, native controls and the system bottom bar.
This is a functional UI observation, not a measured frame-rate or main-thread latency result.

The phone remained visible in USB inventory, but neither CloakRoll nor Apple's Image Capture
listed its photo library during the follow-up. No extra physical transfer or reconnect success
is claimed. Existing actual-backup evidence remains in Phases 5–7.

The final normal app migrated its existing local history to v3 and displayed the same two
completed physical-backup sessions. Read-only aggregate checks retained eight records, zero
journal entries, three completed items/four verified originals per session, and the original
30,736,406-byte versus zero-byte transfer totals. The new completion index was present. An
independent size/SHA-256 check matched all four unique originals referenced by those records.
The destination still contained 11 regular media files totaling 191,776,983 bytes. This verifies
saved history and local originals after migration; it does not replace source reconnect testing.

Remaining Phase 9 acceptance includes instrumented scrolling/main-thread timing, sustained app
memory measurements with real decoded media, thumbnail reuse after a physical reconnect, and
representative real-library throughput. Large session registration runs off the UI actor but can
delay Stop until its metadata preparation/registration transaction finishes; no new registration
cancellation behavior is claimed. The broader phase remains in progress.
