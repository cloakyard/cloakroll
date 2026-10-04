# CloakRoll implementation plan

Started 12 September 2026. Product: **Your camera roll, safely on your Mac.**

## Working agreement

CloakDrop (`../cloakdrop`) is read-only. Work proceeds through the gates below in order.
Every phase records its build, relevant tests, manual evidence and remaining limitations here.
A passing mock test never substitutes for a real iPhone acceptance check. Following the user's
12 September request to continue the next phases after committing current work, implementation
may proceed while an explicitly recorded hardware check is pending. A phase is not accepted or
called complete until its actual evidence is recorded. No source media is modified or deleted.

## Phase 0 discovery

Reference files were inspected under `../cloakdrop`:

| Concern | Reference | CloakRoll decision |
| --- | --- | --- |
| Structure | `AGENTS.md`, `apps/macos/project.yml` | Keep the native app under `apps/macos`; generated, ignored Xcode project; no speculative website. |
| Architecture | `apps/macos/ARCHITECTURE.md`, `App/App/AppModel.swift` | Thin SwiftUI shell, explicit environment construction, observable main-actor bridge, headless local package. |
| Dependencies | `Packages/DownloaderCore/Package.swift` | Foundation/system frameworks initially; GRDB has a clear purpose in Phase 6. Do not import download helpers. |
| Persistence | `Sources/DownloadPersistence/GRDBDownloadStore.swift` | GRDB migrations, indexed identity/status columns, transactional completion. Use normalized components for multi-file assets. |
| Events | `App/App/AppModel.swift`, `AppModelState.swift` | Separate catalog snapshots from frequent progress. Delegate callback objects never become view models. |
| Surfaces | `App/Shared/DesignTokens.swift` | Native system backgrounds, 12-point panel and 6-point inline radius; tighter media cells. |
| Sidebar | `App/Features/Sidebar/SidebarView.swift` | Native source-list selection and keyboard focus; 200/224/300-point widths. |
| Window | `App/App/CloakDropApp.swift`, `App/Features/RootView.swift` | One main window, Settings scene; large library surface instead of permanent downloader inspector. |
| Settings | `App/Features/Settings/SettingsView.swift` | Native grouped forms, small useful sections; no decorative toggles. |
| Empty states | `App/Shared/EmptyStateView.swift` | Quiet symbol, concise reason and actionable next step; no oversized cards. |
| Icon | `assets/README.md`, `App/Resources/AppIcon.icon`, `scripts/generate_app_icon.swift` | Preserve family shield weight, introduce a layered photo motif and purple. Keep editable artwork separate from exports. Phase 1 icon remains a prototype. |
| Quality | `.swiftlint.yml`, package `Tests`, documentation and `AGENTS.md` | Swift 6 strict concurrency, focused Swift Testing suites, warning-free app builds, strict lint, recorded verification limits. |
| Release | `project.yml`, `scripts/dmg`, `.github` | Hardened runtime and ad-hoc local build first. No existing CI workflow to copy. Developer ID/notarization require actual credentials and release verification. |

Do not copy CloakDrop's networking, web browser, segmented downloads, menu-bar ambient systems,
download actions, helper executables, or permanent inspector. The macOS 14 baseline provides
Observation, SwiftUI split navigation and Settings. Following the user's Liquid Glass refinement
request, use newer system UI APIs behind availability checks with native macOS 14 fallbacks.
Purple is semantic `AppAccent`, with separate light/dark asset values; source-list selection stays native.

## Planned architecture and directory structure

```text
assets/icon/                         editable icon source and design notes
apps/macos/
  project.yml                        XcodeGen source of truth
  App/
    App/                             scene, environment, AppModel
    Features/Library/                sections, lazy grid, selection, info
    Features/Sidebar/                device, library, backup, destination
    Features/Backup/                 action/progress area
    Features/Settings/               native grouped forms
    Shared/                          semantic tokens, formatters, status UI
    Resources/                       asset catalog, entitlements, Info.plist
  Packages/CloakRollCore/
    Sources/MediaModels/              immutable Sendable domain and protocol boundaries
    Sources/MediaCatalog/             catalog projection and mock fixtures
    Sources/DeviceCapture/            Phase 2, framework-owned serial adapter
    Sources/ThumbnailPipeline/        Phase 4, bounded async caches
    Sources/BackupEngine/             Phase 5, queue and transfer state machine
    Sources/BackupPersistence/        Phase 6, GRDB implementation
    Tests/                           corresponding focused suites
  scripts/                           reproducible generation and verification
docs/                                phase evidence, development and API research
```

Only create modules when their phase starts. Core imports no SwiftUI. UI formatting, symbols,
colors and `NSImage` presentation belong to the app. Use immutable values at concurrency seams,
and actors for catalog projections, cache ownership and backup coordination. The ImageCaptureCore
adapter owns framework object handles on their required execution context; no USB waits or large
sorts occur synchronously during a view update.

## Data flow

1. A device browser emits normalized discovery/session events to AppModel.
2. The adapter enumerates metadata into `MediaResource` values; related resources form a `MediaAsset`.
3. A catalog service classifies, sorts, groups and matches metadata away from the UI actor.
4. AppModel publishes a prepared snapshot; the grid constructs only visible cells.
5. A thumbnail provider serves visible requests, then prefetch, using bounded memory/disk caches.
6. A user chooses a folder; destination access is scoped for the entire queued operation.
7. BackupEngine transfers **each original component** to same-volume staging, verifies it, finalizes
   without overwrite, and only then commits a verified record through BackupStoring.
8. Catalog backup status derives from verified records for the selected device **and destination**.

## Identity and database design

Never identify a photo by filename alone. Keep device identity, per-resource source identity,
size/date/type evidence and related-resource identity explicit. A missing stable device ID is
session-scoped and must not silently match history from another phone. A PTP handle is not a
persistent identity. macOS 15+ ImageCaptureCore fingerprints are optional stronger evidence;
macOS 14 requires conservative metadata matching. Ambiguous matches remain uncertain/new
until stronger evidence is available. A local hash is evidence about the downloaded bytes,
not proof of equality with a source hash the framework has not supplied.

Use GRDB/SQLite in Phase 6, keeping the dependency pinned via Package.resolved. Tables:

- `device`: stable key, display name, first/last seen; session-only devices flagged explicitly.
- `asset` / `resource`: device-scoped asset identity and all original companion files, optional
  source fingerprint, metadata signature, size/type/date; indexed by device + identity evidence.
- `destination`: local identifier and bookmark reference, without using a volume's display name as identity.
- `backup_record`: resource + destination, relative path, expected/actual bytes, local digest,
  verification method, started/completed timestamps, status and session. Unique verified identity
  within a destination; incomplete rows remain retryable.
- `backup_session`: device/destination, status, counts and measured transferred bytes.

Use transactional state changes and migrations. Record downloaded and verified separately.
Finalize the filesystem before database success; reconcile a crash between these steps by checking
the staged/final file against saved evidence rather than overwriting or trusting its name.
Do not claim physical power-loss durability from a process-restart test.

## Risks and explicit decisions

- Wired exposure can omit iCloud originals. Present only what the API exposes; no cloud completeness claim.
- Authorization APIs have platform-specific availability. See `docs/APPLE_APIS.md`; macOS does not use
  the iOS contents/control authorization request methods.
- Trust, lock and device errors must be distinguishable only to the extent Apple's public API permits.
- Same-stem HEIC/MOV files alone are insufficient proof of a Live Photo. Prefer framework pairing evidence.
- USB calls can serialize or outlive cancellation. Bound outstanding work and ignore stale session results.
- External volumes/bookmarks may disappear; never fall back silently to a different directory.
- Full-file originals must be preserved; do not request conversion or delete-after-download.
- 100,000-item performance needs measured projection/database/cache/scroll evidence in Phase 9.
- Developer ID signing, notarization, physical iPhone tests and older-OS runtime tests require their environments.

## Phase gates and status

| Phase | Deliverable and acceptance gate | Status |
| --- | --- | --- |
| 0 Discovery | Reference inspection, architecture, validated public APIs and coherent implementation plan. | Complete |
| 1 Foundation | macOS 14 app + package, mock library, native sidebar/grid/settings, purple tokens, prototype icon. Build, tests, lint; manually inspect 1,000+ assets, light/dark and empty states. | Complete |
| 2 Detection | Public ImageCaptureCore adapter, serial lifecycle, normalized device/trust/lock/unavailable states. Real unplug → plug → disconnect → reconnect evidence required. No downloads. | Complete |
| 3 Catalog | Real metadata and related resources, photos/videos/RAW/Live Photo evidence, sorting, lazy API thumbnails. Real library visible without downloading originals. | Complete |
| 4 Thumbnails | Bounded memory/disk cache, versioned invalidation + eviction, visible priority, prefetch and cancellation. Rapid scrolling/reconnect memory and USB concurrency checks. | In progress |
| 5 Backup | Folder picker/bookmarks, Year/Month paths, original-component queue, staging, progress and no-overwrite collision policy. Selected/all real photos and videos copied. | Complete (bounded physical import) |
| 6 Incremental | GRDB schema/migrations, device/destination-scoped matching, session history, new/backed-up/recent filters. Reconnect old library + newly captured items checked. | In progress |
| 7 Reliability | Size and digest evidence, disconnect/full disk/retry/cancel/relaunch tests and real interruptions. No incomplete success or unrelated file overwrite. | In progress |
| 8 Polish | Onboarding, info/search/sort/context menus/shortcuts, cloud availability copy, external volume UX, accessibility and final icon. Compare all screens to CloakDrop. | In progress |
| 9 Performance | Generated 10k/50k/100k catalogs; timed catalog/matching/startup, bounded thumbnails, measured main-thread/scrolling and database behavior. | In progress |
| 10 Release | Privacy/entitlement/sandbox review, Release build/lint/tests, docs/screenshots, signing/notarization with verified identity. | Planned |

## Feature backlog — restore to a new iPhone

Requested future feature: choose an existing Mac/external-drive backup folder, preview its photos
and videos, select items, and copy them into a new iPhone's Photos library. **Backlog only; no
committed phase, no V1 gate, and no iOS companion app planned.** The user's requirement is that
no extra app be installed on the iPhone; if one is required, this feature remains in backlog.

[Restore feasibility and conditional design](RESTORE-TO-IPHONE.md) records the official API
research, native Finder/Photos alternatives, inventory/selection design, conservative duplicate
handling, resource fidelity and interruption requirements. ImageCaptureCore's historical upload
method is deprecated because sandbox restrictions prohibit direct device writes. Finder offers
an external manual synchronization workflow, but no public CloakRoll-controlled additive restore
path was validated. PhotoKit on the phone would require the excluded companion app.

Promote this item only after the core backup work and a supported public, sandbox-compatible,
**no-extra-iPhone-app** path has been verified on physical hardware for additive import, original
resource handling, measured progress, and safe reconciliation of duplicate/unknown outcomes.
No automatic destructive sync, iPhone deletion, private protocols, or source-backup modification.
The current phase table and its acceptance gates remain unchanged.

## Test map

Phase 1 covers deterministic fixtures, date boundaries/unknown dates, filtering, stable ordering,
selection semantics and large mock projection. Phase 3 adds identity/classification/Live Photo/RAW
pairing tests. Phases 5–7 add path sanitization/collisions, all backup state transitions, failed source
and destination, no overwrite, interruption/retry, database migration, fresh/reopened store, multiple
devices/destinations and verification failure. Hardware matrices stay separate from simulated tests.

## Progress evidence

### 4 October 2026 — destination status refinement

Grouped the destination name and status under one native folder Label. A compact, secondary
“Access checked” caption aligns beneath the name; the redundant sidebar-sized success icon
is removed. Checking uses a mini progress indicator, while failures show an inline warning,
“Needs attention” and the specific error in help/accessibility. The wording describes the
last folder-access check, not backup verification or continuously monitored availability.
Actual macOS 27 UI checks cover unchecked/available accessibility text, the connected-phone
sidebar in light/dark, and the shared status in Backup settings. State/error semantics were
reviewed without forcing a real folder failure. Debug build, strict lint, whitespace check
and all 333 core tests pass; no new tests for this presentation-only change. Logs:
`/tmp/cloakroll-destination-design-build.log` and `/tmp/cloakroll-destination-design-core-tests.log`.

### 4 October 2026 — camera metadata and native Info scrolling

Media Info now requests actual camera EXIF only when opened for a still image. The native
Camera group shows supplied camera/lens, ISO, aperture, shutter speed, focal lengths and
exposure bias, with quiet missing-data handling and explicit retry on request failure.
One physical metadata operation is permitted; caller cancellation, timeout and session
retirement cannot release its physical ownership early or publish stale values. The scrollbar
now sits at the sheet's right edge with margins applied only to content. Verified real Live
Photo EXIF and a PNG without camera facts; reviewed edge scrolling in light/dark with 30
long filenames. All 333 core and 112 hosted app tests, Debug/Release builds and strict lint
pass. See `verification/MEDIA-INFO.md`; existing broader hardware gates remain open.

### 4 October 2026 — Media Info redesign

Replaced the tall, single-column Info sheet with a contained full-image preview and a scrollable
details column. Added aligned metadata, destination-scoped backup status, native original-file
rows, full selectable filenames and Escape dismissal. Checked a real Live Photo from the
connected iPhone, dark video sample, compact window, 30 long Unicode original filenames,
missing metadata/preview, accessibility labels and Return/Escape. Debug build, strict lint
and all 305 core tests pass. See `verification/MEDIA-INFO.md`. Camera EXIF is the next requested
addition and is not yet included in this UI milestone.

### 4 October 2026 — landscape identity and native macOS 27 app icon

Replaced the shield prototype with a photo window, original sweeping mountain facets and an
apricot sun. The editable Icon Composer document now compiles into the app's native layered
icon, with Xcode-generated older-system representations. Default/Dark About assets and six
appearance previews share the same source. Small sizes and all six styles were inspected;
the actual About screen was checked in light and dark on macOS 27.0.1. Clean Debug and Release
builds, all 305 core tests, strict lint, whitespace and signature checks pass. Phase 8's other
acceptance gates remain open. See `verification/ICON-REFINEMENT.md` for evidence and limits.

### 4 October 2026 — explicit local verification and final test cleanup

Library → Check Saved Originals now refreshes local backup evidence without reconnecting or
downloading. It handles missing files and retry after access failure, with safe operation-state
gating. Switching phones dismisses an idle old-phone summary while keeping active interruption
outcomes. Actual connected-phone verification cleared two stale badges after the final six
test files were removed. The destination is now empty and historical session records remain.
Final 305 core and 96 hosted app tests, normal build, lint, whitespace and signature checks pass.
See `verification/MULTIPLE-IPHONES.md` and `verification/OCTOBER-4-HARDWARE.md`.

### 4 October 2026 — multiple iPhones and separate backup folders

Added native selection for multiple discovered phones, safe source retirement and stale-event
rejection. New originals use stable per-device folders containing Year/Month paths; legacy
files remain eligible for fresh verification without moves. Same-name phones, renaming,
missing originals, queued callbacks and mixed-device rejection are tested. All 305 core and
93 hosted app tests pass; normal build, lint and signature checks pass. Two physical phones
were used sequentially: their originals went into distinct verified folders, a mixed old/new
selection transferred only new components, and its repeat transferred zero bytes. See
`verification/MULTIPLE-IPHONES.md`. Simultaneous picker and active cable-removal gates remain open.

### 4 October 2026 — requested cleanup and real incremental/Stop checks

Removed sixteen explicitly requested previous test backups after matching the full private
baseline, reclaiming 3,286,761,691 bytes. History remains available. The normal app exposed
5,140 items on the connected phone. A deleted local photo was copied again; its immediate
repeat verified the saved original with zero transfer. Native Command-period stopped an actual
231 MB USB download before publication, waited for the terminal callback, and recorded zero
verified items. Try Again succeeded and independent hashes passed. A subsequent actual
Quit-during-transfer also waited for the cancellation callback, persisted zero verified items
and exited; the new large test video was removed again to reclaim space. See
`verification/OCTOBER-4-HARDWARE.md`. Cable-removal and simultaneous-device gates remain open.

- Initial workspace was empty, without Git history. Xcode 27.0, Swift 6.4, XcodeGen and SwiftLint are available.
- USB inventory at discovery showed host buses only; no attached iPhone. Hardware verification remains pending.
- No product feature code was written during discovery.

### Phase 0 — complete

Architecture/reference audit and Apple documentation + SDK checks completed. An isolated API probe typechecked for macOS 14; no device calls executed. Original presentation must be explicitly selected, fingerprint is macOS 15+, and macOS cannot call iOS browser authorization APIs. Gate passed: no unresolved compile-time assumption blocks basic enumeration.

### Phase 1 — complete

Native shell, headless models/catalog, 1,200-item sample library, selection, search/sort/grouping, Info, Settings, purple tokens and prototype icon implemented. Warning-free Debug build, strict lint and 33 core tests pass. Native light/dark and keyboard/scroll/empty-state checks passed after fixes. See `verification/PHASE-1.md` for exact evidence and limits. No device API was called in this phase. Next: Phase 2 physical discovery.

### Phase 2 — in progress

Public USB camera adapter, stable-identity normalization, connection reducer and app integration implemented. Core initially passed 50 tests; app integration passed 4 hosted tests. Real hardware discovery identified the attached iPhone and revealed an access-restriction recovery bug, now being corrected before the gate. No original or thumbnail requests have been made. Restore-to-iPhone is independently documented as backlog only.

Phase 2 follow-up: 56 core and 4 hosted app tests now pass; warning-free normal build and strict lint pass. Real restricted → ready recovery observed and corrected. Normal sandbox entitlements verified after rebuilding without test-host additions. Physical ready → disconnect → reconnect gate remains pending; see `verification/PHASE-2.md`. Phase 3 has not started.

### Phase 2 — complete; UI refinement gate added

A normal sandboxed app process recorded physical ready → disconnected → rediscovered/restricted
→ ready between 13:57 and 13:59 on 12 September. The live UI confirms Connected. All 56 core and
4 hosted app tests pass; normal build is warning-free. See `verification/PHASE-2.md`.

Before Phase 3, complete the user's explicit UI quality pass: replace the cramped thumbnail-size
slider, audit hierarchy/spacing/unsupported actions, verify keyboard/accessibility and minimum
window width in light/dark appearance. Commit this refinement as its own stage. Git was initialized
at project creation; continue committing each verified stage and recording actual evidence.

### UI refinement gate — complete

Native View Options popover/shared continuous sizing control, accessible endpoint names and
keyboard focus, cleaner sidebar/action hierarchy and Settings help are implemented. The audit
also fixed a pinned-header overlap after filter/sort changes. Default and compact (860-point) layouts,
light/dark, 100,000-item count widths, slider range/keyboard, Info and empty states were inspected.
All 56 core and 4 hosted app tests, strict lint and a normal warning-free build pass. See
`verification/UI-REFINEMENT.md` for the exact evidence and accessibility/runtime limitations.
Next: Phase 3 metadata first, then lazy public thumbnails, with separate stage commits.

### Phase 3 — metadata stage implemented; physical acceptance pending

Session-scoped camera registry, coalesced full catalog snapshots, conservative classification and
related-resource assembly, background presentation preparation and scan/coverage UI are implemented.
99 core and 9 hosted app tests pass. Normal sandbox build, strict lint and signature checks pass.
The physical phone is attached in IORegistry; its rebuilt-app discovery/catalog check awaits unlock
and reconnect. See `verification/PHASE-3.md`. No original or thumbnail calls in this metadata stage.
Next within this phase: lazy thumbnail integration and physical catalog acceptance; do not advance
to Phase 4 until the real library and scrolling gate passes.

### Phase 3 — lazy thumbnail stage implemented; physical acceptance pending

Visible cells and Info now request public thumbnails, with two actual outstanding framework calls
across browser replacements, a bounded queue, cancellation/session rejection and bounded ImageIO
decoding off the main actor. 111 core and 12 hosted app tests pass. Strict lint, normal build and
signature checks pass; independent review found no blocker. Final compact sample UI regression
passes. See `verification/PHASE-3.md` for exact evidence and callback-lifetime limitations.

The actual iPhone library and thumbnails still need unlock/reconnect validation. Leave the normal
app open for this gate; Phase 4 caching/prefetch and all backup transfer phases remain planned.

### Liquid Glass UI audit — complete

The user requested a second audit focused on native appearance and slider tracking. Thumbnail
sizing now uses an unmodified system slider directly in the toolbar; sort/group options use a
native menu. Removed forced focus and custom key handling, replaced custom Info chrome with
the system sheet structure, and adopted the macOS 26+ native bottom-bar API with macOS 14–15
fallbacks. Improved badge contrast and added increased-contrast accent variants.

Actual pointer drag, track click, endpoints, menu keyboard isolation, Info dismissal, compact and
standard layouts, light/dark appearance previews, Settings, search and scrolling were checked.
111 core and 12 hosted app tests, final normal build, strict lint and signature verification pass.
See `verification/UI-LIQUID-GLASS.md` for evidence and untested accessibility/runtime combinations.
The sample preview is left open for UI review; the Phase 3 physical library gate remains pending.

### Phase 3 — physical acceptance complete

The normal app displayed 1,881 real USB-exposed media items after physical unlock/reconnect.
Real photo, Live Photo, video and RAW thumbnails, related originals, video dimensions/duration,
filename search, sorting and scrolling were inspected. Disconnection and recovery were observed.
No original files were downloaded. See `verification/PHASE-3.md` for aggregate evidence and
coverage limits. Commit the requested fixed-size UI and catalog responsiveness stage next,
then proceed to Phase 4 thumbnail caching and scheduling.

### Fixed-size UI and catalog responsiveness — complete

Removed the slider and its endpoint icons; Small/Medium/Large presets are available in the native
View Options menu and Settings, with Medium as default. Removed the sidebar privacy tagline and
reserved footer space. Real thumbnail layouts were inspected at compact and standard widths.

Catalog projection now cooperatively cancels obsolete work and reuses calendar intervals while
grouping. An isolated optimized 100,000-item projection improved from a 199.665 ms median to
161.196 ms with identical output. 113 core and 12 hosted app tests, normal build, strict lint and
signature verification pass. See `verification/UI-PRESETS-PERFORMANCE.md` for exact scope.
Committed as `b26ad76` before Phase 4 caching work began.


### Phase 4 — implementation validated; final hardware gate pending

Shared encoded/decoded caches, viewport scheduling, bounded prefetch, independent cancellation,
LRU eviction, corruption handling and conservative reconnect preview matching are implemented.
156 core and 22 hosted app tests, final normal build, strict lint and signature checks pass.
Real library scrolling demonstrated two actual outstanding framework calls and decoded cache
costs staying below 64 MiB while evicting older images. Info reused the existing grid bitmap.

The final direct-value visibility refinement still needs its hardware follow-up, and physical
reconnect preview reuse is pending unlock/reconnect of the attached phone. See
`verification/PHASE-4.md` for exact evidence, RSS/footprint measurements and limitations.
Phase 5 original downloads remain planned; public download APIs were researched only.


### Phase 5 — started after the user's continuation request

Current work was already committed as `0568c76`; the working tree was clean before Phase 5.
Implement original-component backup, a native folder picker with scoped bookmarks, Year/Month
paths, a serial queue, measured progress, isolated staging, exact-size checks, streamed local
SHA-256 and exclusive finalization. Begin with selected items, then all available items.
Keep Phase 4's outstanding physical checks visible; do not treat implementation as acceptance.

### Phase 5 — complete for bounded physical imports

Native folder selection/bookmarks, original-component copies, Year/Month staging/finalization,
measured progress, stop/retry, truthful component/asset completion and no-overwrite collisions are
implemented. 204 core and 41 hosted app tests, strict lint, the normal sandbox build and signature
checks pass. Real photo, Live Photo, 4K HEVC video and RAW copies succeeded; repeated selection
reverified without copying, and stopping a large video left no false success or staged file.

The UI audit corrected filtered action totals, removed a duplicate folder action and refined
singular labels and indeterminate progress before byte callbacks. See `verification/PHASE-5.md`
for aggregate evidence and limits. History is still connection-scoped in memory; next is Phase 6
persistent history and conservative device/destination-scoped matching. Full-library stress,
physical unplug/cache reconnect, external volumes and crash recovery remain explicit future checks.

### Phase 6 — implemented; physical incremental acceptance pending

Pinned GRDB persistence, versioned migrations, per-resource transactions, conservative complete-
catalog identity, fresh local verification and native history-checking/session presentation are
implemented. 245 core and 48 hosted app tests pass, as do strict lint, normal sandbox build and
signature checks. Independent matching review found no blocker. The normal compact disconnected
window and updated Settings were inspected. See `verification/PHASE-6.md` for evidence and limits.

The reliability review also added a root-relative final-path check: moving or replacing a
Year/Month folder during publication now fails without returning incorrect verified evidence,
while preserving both the published file and any replacement. The deterministic regression,
full core suite and final normal build pass.

USB inventory now shows no iPhone; reconnect and a new capture were requested. Real persistent
backup/relaunch/new-item acceptance is pending and is not replaced by the automated fixture
reopen tests. Phase 7 must close the documented publication-to-database crash gap; existing
unrecorded originals are preserved and conservatively copied again rather than trusted by name.

### Phase 7 — started 3 October 2026

The repository was clean at `acaa98f` before the user's continuation request. Add durable staging
and publication intents, then reconcile exact published originals after interruption using fresh
local file identity, size and digest evidence. Never adopt a filename or identical-content
replacement inode alone. Preserve uncertain files and truthful partial session status. Retain
the pending Phase 4/6 hardware gates while implementing and verifying this reliability stage.

In parallel, audit the next native product screens against current Apple design guidance and
CloakDrop's read-only reference. Implement product refinements as a separate committed stage
after the reliability baseline builds and passes its relevant tests.

The physical Phase 6 follow-up copied three logical items/four originals (30,736,406 bytes),
restored all three statuses after app relaunch and repeated with zero transferred bytes and
unchanged destination hashes. The new-capture/cable-reconnect gate remains pending; see the
3 October appendix in `verification/PHASE-6.md`.

### Phase 7 — implemented; physical interruption checks pending

Durable staging/publication intents, exact final-file recovery, atomic record/counter resolution,
partial preservation and actionable storage errors are implemented. 266 core and 53 hosted app
tests pass. Independent review found and fixed fractional-timestamp replay precision. Abrupt
generated-fixture process exits before transfer, before publication and after publication reopen
without false completion; published originals recover once. Strict lint, normal build and
signature checks pass. See `verification/PHASE-7.md` for exact scope and preserved-staging limits.

The phone is USB-visible but its library has not yet appeared in the new normal build after the
requested reconnect. Keep physical cable/new-capture, transfer interruption, external drive and
power-loss checks open. Proceed to the separately committed native product refinement stage,
without calling these pending hardware gates complete.

### Phase 8 — native history and interaction stage verified; broader polish pending

After the Phase 7 commit `415a134`, added offline Backup History with native disclosure rows,
verified/transfer counts, safe destination context, loading/error/retry states and bounded recent
sessions. Native menu/context commands, Find, view-option parity and remembered browsing/Settings
choices are implemented. 62 hosted app tests, strict lint, a warning-free normal build and actual
signature checks pass. See `verification/PHASE-8.md` for exact evidence and Apple design references.

The normal app displayed the two real completed sessions offline, including the zero-transfer
repeat. Search text selection, size/Settings persistence, history refresh and command availability
were exercised. Compact light and standard expanded light/dark layouts passed after correcting
history-note wrapping and separator alignment. Full VoiceOver, system accessibility variants,
macOS 14 runtime checks, final icon and remaining product/hardware polish are pending. Phase 8 is
not yet accepted or complete.


### Phase 9 — scale measurements and targeted improvements started

The native history and preferences stage was committed as `cee5bdc` before performance edits.
Generated Release probes now cover 10k, 50k and 100k catalogs. Measurements identified expensive
hexadecimal formatting, a missing logical-asset completion index and whole-history candidate
materialization. Optimize those paths while preserving exact identities and every relevant
historical ambiguity check. See `verification/PHASE-9.md` for method, results and remaining gates.


### Phase 9 — measured metadata/history stage verified; app/hardware stress pending

Exact digest encoding, indexed logical completion, bounded candidate reads and the empty-history
fast path are implemented. All 284 core and 62 hosted app tests, strict lint, normal build and
signature checks pass. Independent review preserved Swift Unicode identity comparison and every
relevant historical conflict. A reproducible generated Release probe is checked in under
`apps/macos/scripts/PerformanceProbe`.

At 100k items, measured identity preparation improved from 9.086 to 3.769 seconds, full candidate
lookup from 3.752 to 2.256 seconds, and whole-probe peak RSS from 1,264 to 760 MiB. The separate
empty-destination check is now 0.246 ms. See `verification/PHASE-9.md` for all three sizes, exact
methods and limits. These are headless generated metadata results; physical media throughput,
instrumented main-thread/scroll latency and sustained real-media cache memory remain pending.

### 3 October — second-device hardware validation checkpoint

The normal a007e84 app imported a Live Photo and two videos from a second physical phone;
four original files passed independent size/SHA-256 checks. The Live Photo repeat transferred
zero bytes. The eleven pre-existing destination files remained unchanged, with no unresolved
journal entries. A genuinely new capture appeared Not Backed Up while three tested logical
items remained Backed Up (2,067 total). See `verification/PHASE-7.md`. Transfer interruption,
instrumented physical reconnect and sustained cache/memory acceptance remain pending; the
videos completed before Stop could be exercised. No phase gate is promoted by these limits.

Next bounded implementation stage: optional native connection/USB-availability help, accessible
media actions, offline backup-folder readiness/retry, and cooperative cancellation during large
backup registration. Preserve native system surfaces and macOS 14 fallbacks.

Preparation cancellation refinement is implemented and passes all 287 core tests. Registration
now cooperates with Stop during metadata validation, with no database rows or source calls on
pre-cancelled requests. Physical source ownership and interruption gates remain unchanged; see
`verification/PHASE-7.md`. UI help and destination checks are being verified as the next stage.

### 3 October — contextual help and destination readiness stage verified

Optional native connection/USB-availability help, shared media context/accessibility actions,
Command-period Stop, and offline folder checks/retry are implemented. The native Settings
layout was refined to fit its existing window; light/dark UI and direct accessibility Info action
were inspected. Cached readiness remains advisory, and overlapping bookmark refreshes cannot
be changed by a stale folder check. Successful retry also unblocks failed library history.

All 287 core and 76 hosted app tests pass. The final normal Debug build, strict lint, whitespace
and signature checks pass with no compiler warnings or new entitlements/dependencies. See
`verification/PHASE-8.md` for actual UI evidence and limits. Phases 4/6/7/8/9 retain their explicit
remaining acceptance checks; no full phase is promoted based on software tests or sample media.
Next: physical transfer interruption/retry and instrumented reconnect/cache checks when the
iPhone is exposed, external-volume failure checks, then remaining accessibility/icon/release work.

### 3 October — interruption recovery refinement verified; physical gates remain open

Added coordinator/engine and persistent app regressions for the user's unplug-during-backup
scenario: physical callback ownership, partial Live Photo completion, late success/progress,
fresh-session retry, and deferred Quit. Fixed concurrent real bookmark refresh and exact lease
handoff ownership. Failed preparation retains its summary/selection; source-caused cancellation
is distinct from user Stop, with current-session retry or reconnect/reselection guidance.
Progress and Stop remain reachable from Backup History. Native interruption help is implemented.

All 288 core and 86 hosted app tests pass. The normal Debug build, strict lint, whitespace and
signature checks pass. Light/dark help, scrolling, keyboard dismissal, offline history and saved
folder checks were inspected; see `verification/PHASE-7.md` and `verification/PHASE-8.md`.
The phone was exposed at the start, but the final normal app receives no camera discovery callback
despite USB inventory seeing the phone. No physical transfer was initiated in this stage. All
sixteen existing destination files remain unchanged and no new session/journal entry was created.
Physical unplug/Stop/Quit, external-drive failure, reconnect/cache and remaining UI/runtime gates
remain explicitly open; no full phase was promoted based on controlled callbacks.

### 4 October — measured backup progress refinement

The native bottom bar now shows measured byte progress, a percentage, completed items,
the current original and transferred bytes. Verification, Stop and final history saving
retain explicit active states; data reaching 100% does not announce completion. The
destination caption follows the phase. Atomic counter handoff avoids double counting,
and missing download callbacks are filled only after local size/hash verification.

All 338 core and 125 hosted app tests pass, as do normal Debug/Release builds, strict
lint and signature checks. Light/dark and compact native layouts were inspected.
Two physical video imports and a final repeat passed size/SHA-256 checks; intermediate
physical percentages were too brief to capture reliably. Test copies were removed and
history preserved. See `verification/BACKUP-PROGRESS.md` for evidence, the post-cleanup
device-unavailable limitation and remaining acceptance checks. No full phase is promoted.

### 4 October — Liquid Glass backup surface; thumbnail lookahead in progress

The bottom backup controls now use one floating native regular-glass surface on
macOS 26+, with a system-material fallback. Standard/compact light/dark inspection,
bottom content clearance, normal build, strict lint and signature checks pass; see
`verification/PHASE-8.md`. Thumbnail audit found two remaining sources of scroll
pop-in: lookahead depends on lazy cell creation and currently warms only encoded
data. The next bounded stage moves lookahead to catalog rows and prepares decoded
images while preserving visible priority and existing cache/source limits.

### 4 October — decoded thumbnail lookahead verified

Section-aware lookahead now prepares two rows below and one above the viewport,
independently of lazy cell creation. A single speculative worker warms the bounded
decoded cache, cancels obsolete demand and preserves visible priority and session
ownership. Indexing shares catalog storage and runs off the main actor.

All 338 core and 139 hosted app tests pass, along with Debug/Release builds, strict
lint and signature checks. On the physical 2,071-item iPhone library, the initial
viewport had 20 decoded images ready instead of 12 with the same 20 source loads.
A controlled jump loaded exactly the nearby 24 images and then settled with cache
usage below its existing limit. See `verification/PHASE-4.md` for measurements and
limitations; no frame-rate, whole-process memory or full-phase acceptance claim is made.
