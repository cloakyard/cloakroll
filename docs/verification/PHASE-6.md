# Phase 6 — persistent incremental backup evidence

Date: 12 September 2026. Implementation and automated verification are complete for the current
baseline; physical reconnect acceptance remains in progress.

## Implemented boundaries

- Added the headless `BackupPersistence` package target and pinned GRDB **7.11.1** exactly in
  `Package.swift` and `Package.resolved`, revision `b83108d10f42680d78f23fe4d4d80fc88dab3212`.
  The dependency is used for local SQLite; this adds no network service to the product.
- One application-owned `BackupStore` actor opens the caller-supplied database URL. Directory
  creation, opening and migration run off the main actor; reads and transactional writes use
  GRDB's asynchronous queue APIs. The app coalesces lazy opens and retains that store.
- The app's database is `Application Support/CloakRoll/Backups.sqlite` inside its sandbox.
  The baseline migration creates `device`, `destination`, `asset`, `resource`, `backup_session`,
  `session_resource` and `backup_record`, with foreign keys and indexed identity/destination
  lookups. Bookmark access remains owned by the app's destination store.
- Each selected session registers its complete expected component list before original transfers
  start. Verified resource insertion and session counters commit together. Repeated identical
  callbacks are idempotent; a conflicting callback cannot replace the earlier record. A terminal
  completed session requires every registered component and complete asset to have durable records.
- Database opening changes only nonterminal running sessions to interrupted, retaining their
  committed verified components. Completed, failed and cancelled history remains intact.
  Migrations do not reset or delete the database on a schema change. Invalid database contents
  produce a friendly error and are not replaced with an empty store.
- Recent session values expose status, device display name, destination identifier, timestamps,
  logical/resource counts and separate verified/transferred bytes. Backup Settings displays recent
  sessions; history-checking state prevents a premature backup action while candidates are checked.

## Identity and local verification

`BackupIdentityIndex` uses the complete catalog of original resources. Reusable asset identity
includes all component metadata, the primary component, logical type and relationships expressed
without PTP handles. Resource identity includes the complete asset digest as well as its own
component metadata, so changing a companion invalidates every component's match. Identity values
carry canonical structured JSON, SHA-256 lookup digests and explicit reuse eligibility.

Persistent device identity and sufficiently complete, unique metadata are required for reuse across
connections. Missing, inconsistent or ambiguous evidence remains scoped to the exact source session
and runtime addresses. PTP handles and filenames alone never establish persistent identity. These
original-backup identities are separate from disposable thumbnail cache identities.

Candidate lookup always uses the same device key and destination UUID, then compares both the full
asset and full resource canonical values; a matching digest alone is insufficient. Duplicate current
identities are excluded. Historical records with conflicting local digest, size or destination-root
evidence are ambiguous and cannot suppress a download. Session-only candidates require the exact
source session. Equal-content historical paths may yield a candidate for fresh local checking.

A stored candidate is **not** a backed-up status. The app first rebases a proved metadata match to
the current runtime resource IDs/session and full source signature. `BackupVerification` then opens
the chosen destination through its descriptor-based read-only access and freshly checks every
candidate's safe relative path, destination identity, exact positive size and local SHA-256. It
creates no staging and makes no source calls. A logical item becomes backed up only when every
component passes. Missing, changed or mismatched files remain eligible; existing files are preserved.

Checking, rebasing and hashing run off the main actor. Destination access stays open for the entire
check. Generation/cancellation checks prevent an older device, destination or catalog result from
publishing current status. A changed companion invalidates retained same-session status as well.

## Commit ordering and cancellation

The original-transfer order is: stage → verify local bytes → exclusively finalize → await the
resource database transaction → complete the logical asset. The engine retains the finalized local
record before invoking its `onVerified` callback. That callback runs in an independently owned,
awaited task, so UI cancellation after finalization does not abandon a required database write.
The final session write is also awaited before the app reports its terminal outcome.

A resource write failure leaves its original file and local retry evidence intact, returns failure,
and cannot complete its asset. A final session write failure leaves the durable component records
intact without inventing a completed session. Physical source cancellation still waits for the
actual ImageCaptureCore callback before releasing its source slot, staging or destination lease,
as established in Phase 5.

## Automated verification

- **245 core tests pass:** 17 BackupPersistence, 31 BackupEngine, 72 MediaCatalog,
  70 DeviceCapture, 24 MediaModels and 31 ThumbnailPipeline. The package run produced no compiler
  warnings or errors. Strict SwiftLint and whitespace validation passed at this baseline.
- Persistence tests cover fresh/nested database creation, migration applied once, reopen recovery,
  preserved terminal sessions, resource uniqueness, partial-asset failure and late callbacks.
- Transaction failure tests inject SQLite failures after record insertion and during final session
  completion. They verify rollback of the resource/counters together and no false completed state.
  A malformed existing database remains byte-for-byte unchanged after opening fails.
- Matching tests cover changed devices/destinations/companions, session-only scope, runtime address
  rebasing, exact canonical comparison despite a colliding lookup digest, duplicate current assets
  and conflicting historical content. Record validation checks source session, device, asset,
  filename, expected size, path, digest and registered source signature.
- A package integration test finalizes real temporary fixture files through BackupEngine, commits
  their records, reopens the store, matches new runtime addresses and freshly verifies the local
  files. Altering one local file to different bytes of the same length removes complete-asset
  status while preserving that file and the valid companion.
- Identity tests exercise complete-catalog requirements, handle changes, full companion context,
  relationship changes and conservative fallback. Engine tests verify the awaited persistence
  callback and read-only local checking, including cancellation and invalid candidate evidence.
- **48 hosted app tests in eight suites pass**, including the final added history case. Hosted
  fixtures disable physical discovery and do not establish a real reconnect acceptance result.
- A final reliability review found that moving or replacing a Year/Month folder during publication
  could leave a valid open file descriptor but an incorrect saved relative path. Finalization now
  reopens the whole path from the held destination root and compares the exact published file
  identity, size and modification time before returning evidence. The regression moves the folder
  immediately after publication, optionally replacing it with identical bytes in another inode;
  both cases fail without returning verified evidence and preserve all published/replacement files.
  The full core suite and normal build were rerun after this correction.
- Logs: `/tmp/cloakroll-phase6-core-tests-final.log` and `/tmp/cloakroll-phase6-app-tests-final.log`.
  These local logs are not repository artifacts. The normal rebuild passed without warnings;
  strict lint, whitespace and actual signature checks passed. The normal app has sandbox, USB,
  app-scoped bookmarks, user-selected read/write and Photos-library entitlements, plus Debug
  inspection. It has no hosted-test service/file additions or network entitlement.
- Independent identity-to-store matching review found no blocker. The newest equivalent saved
  path is checked; if it disappears while an older equivalent survives, a conservative redundant
  copy is possible. This limitation cannot mark missing bytes backed up.

## Physical acceptance — pending evidence

The current USB inventory no longer reports an attached iPhone. Reconnection and a newly captured
item were requested; physical acceptance remains pending. Phase 5's existing copies do not by
themselves demonstrate persistent reconnect matching. Record
aggregate evidence below; do not commit personal names, identifiers, media or database contents.

- [x] Record the normal build, final hosted suite, strict lint and actual sandbox entitlements.
- [ ] Record a real original backup committed to persistent history, with exact logical/component
      counts and independently checked destination contents.
- [ ] Quit/relaunch or reconnect, reopen the chosen destination and freshly verify those originals;
      record recovered status and source-call/file-count deltas.
- [ ] Capture new media after the older backup and confirm it remains new alongside the verified
      older items; check new/backed-up/recent filters and their action totals.
- [ ] Inspect checking/progress/error/retry states and Backup Settings history in the final native UI.
- [ ] Record any pending physical interruption, external-volume and large-library checks separately.

The normal compact disconnected window and native General/Backup Settings were visually checked
in light appearance. Medium remains the default native size choice; the backup explanation fits
without clipping. Populated session history and live checking/error states remain part of the
hardware follow-up. No personal media screenshots or database contents were saved in the repository.

## Phase 7 journal and crash-recovery gap

Phase 6 records verified success **after** filesystem publication. It does not yet write a durable
prepublication journal describing the intended staged/final file and its verification evidence.
A process crash or database failure between exclusive finalization and the resource transaction
can therefore leave a preserved original with no durable verified record. A later run must not
trust that file's name or infer that an incomplete asset is backed up; it may create an exclusive
suffix copy. No existing original is overwritten to hide this gap.

Phase 7 must add and validate the prepublication journal and reconciliation of staged/final files,
including actual interruption/relaunch tests and unknown-content handling. Startup's interrupted
session recovery only reflects records already committed to SQLite; it does not reconcile or
delete unrecorded files. Process-restart tests and SQLite synchronization settings do not establish
physical power-loss durability.

The next implementation should record owned staging before transfer, then persist exact staged
file identity, size, digest and proposed exclusive final path before each rename attempt. Hashing
and publication need a separate awaitable journal boundary, with fresh evidence after the await.
Recovery must inspect only the journaled paths and compare file identity as well as content, so
a crash before rename cannot adopt an unrelated same-content collision target. Resolving the
intent and inserting the verified record belong in one transaction. Preserve ownership markers
when cleanup leaves unexpected contents; current leftovers are preserved but cannot be safely
reconciled from their directory name alone.

## Remaining limits

Identity correspondence is conservative metadata evidence, not a comparison with a source content
hash supplied by Apple. The public USB catalog may omit iCloud originals or other unavailable
resources. A normal database cannot turn missing/ambiguous source metadata into a stable identity.
macOS 14 API availability is compiled; the current runtime is macOS 27. Full-library performance,
physical external-volume removal/full disk, process-crash reconciliation and older-OS runtime
behavior remain their explicit later gates.
