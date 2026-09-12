# CloakRoll architecture

CloakRoll is a native, local-first macOS 14+ wired photo/video backup utility, part of Cloakyard.
It browses available originals without becoming a photo library replacement. See `docs/PLAN.md`
for phase status and acceptance evidence; planned capabilities are not claims about shipped behavior.

## Boundaries follow ownership

The SwiftUI app is a thin presentation shell around an `@MainActor @Observable` AppModel. This
follows CloakDrop's proven bridge pattern, but a media browser needs prepared catalog sections
and selection state instead of download rows and a permanently open inspector. UI-facing models
stay small; catalog projection, transfer state and persistence have independent owners.

The local `CloakRollCore` package contains `MediaModels`, `MediaCatalog`, `DeviceCapture` and `ThumbnailPipeline`. Additional modules
arrive in their implementation phases. None imports SwiftUI. Values crossing tasks are Sendable.
Views issue intents and display state; they do not transfer files, sort a whole library in `body`,
or manipulate ImageCaptureCore objects.

```text
SwiftUI views → AppModel → catalog projection / device / thumbnail / backup protocols
                              ↓                    ↓
                       immutable snapshots    async events

DeviceCapture → MediaModels ← MediaCatalog
ThumbnailPipeline → thumbnail provider
BackupEngine → MediaDownloading + BackupStoring + destination access
BackupPersistence → GRDB / SQLite
```

## Domain representation preserves originals

A logical media asset contains one or more original resources. A Live Photo can have an image
and motion component; RAW pairing must preserve both RAW and rendered companions. Selection
and counts use logical assets, while transfer and verification account for every resource.
Missing capture times stay unknown rather than being fabricated. Display grouping has no
connection to DCIM storage folders and never claims to reflect iPhone Photos albums.

One identity component will own deterministic matching. Device identity scopes every source
identity; destination identity scopes backup status. Stable API evidence is preferred, metadata
is a conservative fallback, and ambiguous matches cannot silently become verified backups.
Names, PTP handles and local-only digests cannot independently establish cross-session identity.

## Concurrency and bounded work

Catalog filtering/grouping runs asynchronously and publishes a complete immutable projection.
A generation token prevents stale search or device results replacing newer state. Large catalogs
use month/year grouping rather than eagerly constructing thousands of daily sections.

The framework adapter owns its browser, device and camera handles on one serial execution
context. Asynchronous delegate APIs do the USB work; immutable events cross into the rest of
the app. Cancellation and removal invalidate session generations before accepting later results.

`CameraCatalog` accumulates all resource callbacks before publishing coalesced full snapshots.
Its newest-only stream may skip intermediate envelopes without losing resource deltas. Explicit
complete-catalog readiness is separate from connection readiness. `LiveCatalogLoader` assembles
the latest pending snapshot off the main actor, serializing expensive preparation and rejecting
retired sessions/revisions. Query edits reset scrolling; incoming metadata alone does not.

`CatalogAssembler` scopes relationships by device and requires unambiguous evidence for pairs.
Every resource is retained once, including ambiguous/orphaned sidecars. A still-image primary
resource gives RAW pairs and Live Photos stable selection and preview identity as companions
arrive. These session resource IDs address device requests; they are not persistent backup keys.

Thumbnail requests are lazy and viewport-driven. A macOS 14-compatible geometry observer reduces
cell positions to visible, nearby prefetch, or no demand; scrolling does not publish every pixel.
The grid and Info share one controller, an encoded pipeline actor, and a serial decoded-image actor.
Visible consumers outrank queued prefetch. At most two logical source loads run, including at most
one prefetch-only load, with 64 queued requests. Consumers of the same key share source work and
can cancel independently. Cancelled active work retains its slot until the loading closure returns.

One `DeviceCaptureContext` separately retains two **actual framework request** slots across browser
replacements. Cancelling a caller does not release a slot until the ImageCaptureCore callback arrives.
This second boundary is necessary because Swift cancellation does not cancel a physical operation.
A synchronous delegate gate permits only explicitly launched requests. DEBUG diagnostics count
actual framework calls and their high-water mark; they do not measure wire-level USB traffic.

Encoded memory is bounded to 32 MiB / 512 entries, disk to 256 MiB / 2,000 entries, and decoded
bitmaps to 64 MiB / 256 entries. Individual encoded payloads cannot exceed 16 MiB. LRU eviction
uses actual encoded byte counts or bitmap bytes-per-row × height. Decoding is serial off the main
actor, with ImageIO orientation handling and a 512-pixel bound. Nearby prefetch stores encoded data
without decoding it. Views hold only their displayed bitmap and release it after leaving the visible
band; these references, framework memory and temporary buffers are outside the cache-byte totals.

Source requests always use connection-scoped keys. Disposable previews may be reused across a
reconnect in the same app process only when a persistent device identity and a complete catalog
provide a unique structured metadata signature (device, context, name, bytes, dates, type and other
available source evidence). Ambiguous or incomplete signatures remain session-only. Metadata
changes invalidate the preview. This is not a backup identity or content-verification claim.

Connection transitions retire consumers and discard late results. Session-only cache entries are
removed; eligible preview entries remain within the same combined budgets. Disk entries have
hashed names, a versioned envelope, exact key/length checks and a payload digest. Corruption or IO
failure becomes a cache miss. Startup purges prior owned runtime namespaces; cross-app-launch
preview reuse is not implemented. No original is requested to render the grid or Info sheet.

## Backup truth is conservative

Backups use a user-chosen, security-scoped destination. A scoped-access lease lives until all
work using that folder ends. Folder names are generated and sanitized independently of UI dates.
Each resource transfers to a unique same-volume staging area, with original format options.
Only transfer success plus expected size/evidence checks allow no-overwrite finalization.
Database completion follows filesystem finalization and records the verification method.

Interrupted records remain incomplete and retryable. Reconciliation must check saved evidence
before reusing a file found after a crash. Existing unrelated files are never overwritten.
A logical asset is backed up only when every required component has a verified record at the
selected destination. Missing/unavailable destinations are visible and never silently replaced.

GRDB is planned because CloakDrop already uses it for tested migrations and transactional
SQLite access. Indexed normalized identities support device/destination isolation and large
incremental scans. JSON payloads may hold optional metadata, but matching-critical columns stay
explicit and indexed. The store remains behind a protocol for failure-injection tests.

## Native presentation and privacy

Keep CloakDrop's native source list, system typography/surfaces and 12/6-point radius scale.
The purple `AppAccent` has light/dark variants; selection, progress and status include shape/text
as well as color. Motion respects accessibility preferences. The media grid is dense and lazy;
details appear on demand. Standard Settings, toolbar controls and keyboard conventions remain native.

No account, telemetry, cloud processing or network entitlement is needed for core operation.
No delete, mutation, conversion or two-way synchronization API is exposed. Debug sample catalogs
are explicitly labeled and never create real backup records. Logs use OSLog categories with
private metadata redacted; bookmark bytes and photo content must never be logged.

iCloud-optimized devices may not expose every original. Detectable hints may inform the user,
but successful backup of enumerated items is never presented as a complete iCloud Photos backup.
Actual Photos album synchronization remains outside V1. No iOS companion app is planned.

## Restore to a new iPhone — backlog boundary

The requested reverse workflow starts with a selected local backup folder and would add selected
original media to a new iPhone. It is **backlog only**, outside the committed phases, until a
supported public approach works without an extra app on the iPhone. The current capture adapter
must remain read/import only; its presence is not a restore transport.

ImageCaptureCore's generic upload API is deprecated because sandbox restrictions prohibit direct
device writes. PhotoKit resource creation addresses the library available to the running app;
using it on the phone would require the excluded companion. Native Finder synchronization is an
external user-managed workflow, not a validated app-controlled additive restore API. No new
transport, PhotoKit writer, iOS target, network entitlement or persistence module is introduced.
See [the sourced restore assessment](docs/RESTORE-TO-IPHONE.md).

If the no-extra-app feasibility gate is ever met, restore needs independent operation/target
identity, immutable backup inventory, whole-asset resource grouping, and durable completion
evidence. Backup success must never imply successful phone restoration. Source bytes stay intact;
target additions require explicit selection, and an unknown target commit cannot be retried
silently or rolled back through deletion. Those are conditional requirements, not current behavior.
