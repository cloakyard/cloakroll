# CloakRoll implementation plan

Started 12 September 2026. Product: **Your camera roll, safely on your Mac.**

## Working agreement

CloakDrop (`../cloakdrop`) is read-only. Work proceeds through the gates below in order.
Every phase records its build, relevant tests, manual evidence and remaining limitations here.
A passing mock test never substitutes for a real iPhone acceptance check. Do not advance past
a hardware gate without that evidence. No source media is modified or deleted, at any phase.

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
| 5 Backup | Folder picker/bookmarks, Year/Month paths, original-component queue, staging, progress and no-overwrite collision policy. Selected/all real photos and videos copied. | Planned |
| 6 Incremental | GRDB schema/migrations, device/destination-scoped matching, session history, new/backed-up/recent filters. Reconnect old library + newly captured items checked. | Planned |
| 7 Reliability | Size and digest evidence, disconnect/full disk/retry/cancel/relaunch tests and real interruptions. No incomplete success or unrelated file overwrite. | Planned |
| 8 Polish | Onboarding, info/search/sort/context menus/shortcuts, cloud availability copy, external volume UX, accessibility and final icon. Compare all screens to CloakDrop. | Planned |
| 9 Performance | Generated 10k/50k/100k catalogs; timed catalog/matching/startup, bounded thumbnails, measured main-thread/scrolling and database behavior. | Planned |
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
