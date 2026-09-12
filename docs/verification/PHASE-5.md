# Phase 5 — original backup queue

Date: 12 September 2026. The original-backup phase passes its bounded physical acceptance checks.
Full-library stress, reconnect identity, and external-volume reliability checks remain separate gates.

## Implemented boundaries

- Headless `BackupEngine` actor serializes selected logical assets and every original component.
  An injected source operation keeps ImageCaptureCore objects outside the engine. A concurrent
  run is rejected before starting; a started run returns its terminal state and verified records,
  including any valid components saved before a later failure.
- Public value snapshots distinguish preparing, downloading, verifying, completed, failed,
  cancelling and cancelled. They report actual transferred bytes separately from verified bytes,
  resource counts and complete-asset counts. Byte progress is published at approximately 10 Hz;
  phase changes and terminal snapshots publish immediately. Filesystem work and streaming hashes
  run off the main actor. The app consumes complete snapshots through its main-actor controller.
- The native folder picker and bookmark store provide destination access. The caller retains its
  scoped destination lease until `run` returns, including cancellation and filesystem cleanup.
  An unavailable destination fails without silently choosing another folder.
- Paths use a Gregorian calendar and a time zone captured when the engine is created: `yyyy/MM`.
  Missing or invalid capture dates use `Date Unknown`. Filename sanitization preserves normalized
  Unicode and extensions while removing path separators/control characters and bounding component
  length. Names never become arbitrary directory paths.
- A unique marked staging directory is created inside the selected destination, keeping staging
  and publication on the same volume. Descriptor-relative child traversal rejects symlinks.
  The returned download URL must match the exact expected staged file. Only regular, single-link
  files are accepted; symlinks, hard links and FIFOs are rejected.
- Every source component requires a positive catalog size. The size reported from the current
  framework file when downloading starts must match it, and the staged file must contain exactly
  that many bytes. SHA-256 is streamed with a 256 KiB buffer. Size, device/inode and modification
  evidence are checked around hashing and again before publication; the final named file is
  checked afterward. File synchronization failures prevent verified success.
- Finalization uses exclusive rename with collision suffixes. An existing unrelated file is never
  overwritten. HEIC/MOV, RAW/rendered and sidecar resources retain explicit asset/resource/path
  mappings. Collisions may produce different suffixes for companions; a complete asset is not a
  single atomic filesystem transaction. If a later companion fails, previously finalized files
  remain valid records and the asset remains incomplete.
- The adapter explicitly requests original media, disables overwrite and source deletion, and
  downloads listed sidecars as separate resources. It accepts one actual original operation at
  a time. This phase adds no networking, conversion, iPhone deletion or private API.
- The backup action's count and byte label use `visibleNewCount` / `visibleNewBytes`, computed
  during background catalog projection after both the active filter and filename search.
  Uncertain and failed items remain eligible; companion bytes count toward the logical asset.
  Full-catalog sidebar totals remain independent of the current view.

## Cancellation and verification lifetime

Both `engine.cancel()` and cancellation of the task awaiting `run` cancel the worker. The source
adapter requests cancellation but keeps the operation suspended until ImageCaptureCore's physical
completion callback settles. The engine therefore remains cancelling, retaining the source slot,
staging directory and caller's destination lease throughout that interval. It does not report
cancelled or delete a file while the framework may still be writing it. Stale session callbacks
cannot produce a verified result for the current session.

Detached filesystem work also remains awaited after cancellation. Cleanup removes only the known
partial filename, known owner marker and empty owned directories. Unexpected staging contents
remain untouched. A callback that never settles keeps the operation and its scope alive; no timeout
pretends that the underlying USB writer has stopped.

Verification proves that a finalized local file had the expected positive size and a recorded local
digest. Apple supplies no source digest for comparison here. `fsync` surfaces deferred file-write
errors; neither it nor these tests establishes physical power-loss durability.

## Session-only retry evidence

Verified records are in memory for the current source session and destination. Each includes the
source device, asset/resource mapping, full structured source metadata signature, destination root
device/inode identity, relative path, byte count and SHA-256. The app can seed a later run with those
records, including verified components from a partial failure.

Every candidate is reopened through the destination descriptors and checked for size and digest
before reuse. Changed local bytes are preserved, and a new download receives an exclusive filename.
Changed source session, device, metadata or destination prevents reuse. Filename equality and
thumbnail reconnect identities never establish backup status.

There is no persistent backup database in Phase 5. Relaunch/reconnect history, durable incremental
matching, migrations and crash reconciliation belong to Phase 6 and later reliability validation.
The saved originals remain on disk, but this phase does not infer their verified status after losing
the session's in-memory evidence.

## Automated verification

- **204 core tests pass:** 24 BackupEngine, 70 DeviceCapture, 55 MediaCatalog, 24 MediaModels and
  31 ThumbnailPipeline. The final package run produced no compiler warnings or errors.
- Engine coverage includes every companion and its digest, partial-asset failure, zero/changed
  source sizes, short/long local files, unavailable destinations and partial disk-write failure.
- Deterministic cancellation tests hold the source callback open and prove the run/staging remain
  alive until settlement, for both explicit engine cancellation and caller-task cancellation.
  They also check busy rejection and bounded monotonic progress without premature verification.
- Filesystem tests cover Gregorian/time-zone boundaries, unknown dates, Unicode and traversal,
  byte-limited filenames, simultaneous same-name finalization, unchanged unrelated files, returned
  external paths, symlinks, hard links, FIFOs, unknown staging files and same-inode post-hash changes.
- Retry tests check partial reuse, complete-selection revalidation without source calls, changed
  local bytes, source-session/device/metadata changes and a different destination.
- Catalog regression tests cover every filter combined with search, uncertain/failed eligibility,
  companion-byte totals, zero matches, initializer compatibility and saturated byte sums.
- **41 hosted app tests pass**, including destination bookmarks/scopes, partial Live Photo retry,
  source/destination/metadata isolation, cancellation retaining its lease until the fake physical
  callback, and late progress not replacing a terminal result. The host disables device discovery.
- The final normal Debug build passes without compiler warnings. Strict SwiftLint, whitespace and
  signature checks pass. Actual entitlements are sandbox, USB, Photos library, user-selected folder
  read/write, app-scoped bookmarks and Debug get-task-allow; hosted-test permissions were removed.
- Two runtime delegate tests verify the exact Objective-C progress selector, optional protocol
  dispatch, full 64-bit counts and rejection of an unrelated file. Apple guarantees no update cadence.
- Logs: `/tmp/cloakroll-phase5-core-tests.log`, `/tmp/cloakroll-phase5-app-tests.log`,
  `/tmp/cloakroll-phase5-normal-build.log`. These local outputs are not repository artifacts.

## Physical acceptance

Normal sandboxed builds used the attached iPhone's 1,893-item USB catalog, at the compact
860-point window width. The native picker selected a dedicated local verification folder.
The final build reopened that choice without another picker and successfully acquired its bookmark.

| Action | Observed result |
| --- | --- |
| Selected photo + Live Photo | 2 logical items / 3 originals: JPEG, HEIC and MOV, 6,701,142 bytes. |
| Repeat the same selection in one connection | Same 3 originals reverified; no additional USB source calls or files. Independent hashes remained identical. |
| Selected standalone video | 1 MOV, 130,015,238 bytes; readable 3840×2160 HEVC with audio, 10.2367 seconds. |
| All new items in RAW view | Action accurately showed 2 items / 22.6 MB. Both DNG files copied through the saved bookmark, totaling 22,590,822 bytes. |
| Stop a 1.77 GB video | Physical operation started at 17:39:53.479 and settled at 17:39:56.725. UI reported 0 of 1 backed up; no large final file or staging directory remained. Retry became available after projection settled. |
| Same photo after app relaunch | Existing JPEG preserved; a separate suffix copy was created. Both JPEG hashes are equal and every initial file's hash is unchanged. |

After these checks the dedicated folder contains **7 files / 161,040,577 bytes**, including the
intentional collision copy. All paths use Year/Month folders. ImageIO decoded previews from all
five image files (two JPEG copies, one HEIC and two DNG), with zero failures. FFprobe read both
MOV containers, including the Live Photo motion component. There are no staging directories.
The real phone's source media was not changed or deleted.

Actual original operations had at most one outstanding request and returned to zero. A cancelled
resource never received a backed-up badge. The initial large-file observation received no byte
update before the first UI capture; the UI now uses native indeterminate activity until measured
bytes arrive, then native progress. No elapsed-time estimate fabricates transfer bytes.

The compact light-appearance UI was inspected for idle, selection, completed and stopped states,
filtered totals, Info availability, destination sidebar and Backup Settings. Removed a redundant
Change action from the bottom bar, corrected singular labels, retained system safe-area glass,
and checked the Settings folder picker attaches to its key window. Cancelling it preserved the
chosen destination. Existing Small/Medium/Large controls and the clean sidebar remain unchanged.
No personal filenames, identifiers, media or screenshots are committed.

This is a bounded real import, not a claimed 31.11 GB whole-phone backup. Full-library throughput,
physical unplug during transfer, external volume removal/full disk, crash recovery and fresh
post-reconnect items remain Phase 6/7/9 checks. The earlier Phase 4 reconnect-cache check remains
pending and is not closed by these original-file tests.

## Remaining limits

Only media exposed by the current public USB catalog can be selected. Missing iCloud originals,
unknown sizes and unavailable resources are not treated as successful backups. External-filesystem
rename or write failures remain failures; no unsafe overwrite fallback is used. macOS 14 API
availability is compiled, while the current test machine runs macOS 27. Physical external-volume,
older-OS, process-crash and power-loss behavior are not established by the headless test suite.
