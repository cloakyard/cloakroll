# Code and lifecycle cleanup — 3 November 2026

Follow-up to the five-feature implementation, requested to continue development without dead
or dangling code. Work remains on `dev`; PR #13 stays a draft pending physical acceptance.

## Scope and changes

- Removed the unreachable pre–macOS 26 branches from the backup bar and pinned section header,
  plus an unreferenced design token and unnecessary imports. Supported macOS 26+ presentation
  keeps the same glass surfaces.
- Removed `DeviceLifecycle.removed`, which had no production caller. Lifecycle tests now exercise
  `reset`, the retirement path the browser actually uses; stale-callback coverage remains.
- Removed the obsolete, unjournaled `BackupFileStore.verifyAndFinalize` method from shipped code.
  Its low-level fixture convenience now lives only in the filesystem tests under a fixture name.
  Production still uses the engine's journaled verification/publication sequence.
- Live thumbnail logging now uses the same metrics accessor as tests. Coordinator-only inspection
  counters are Debug-only; production aggregate diagnostics remain available.
- Added View-menu destinations for Backup Health and Saved Originals. Show Backup History now
  works from either new screen; the history-refresh command is enabled only on the history screen.
- Saved-original opening now owns a cancellable operation and generation. Leaving the browser,
  changing its query, paging or replacing the operation suppresses late preview/Finder/error
  results. A pending physical read retains its folder lease until it settles. Quick Look retains
  its own lease for its presentation lifetime. Clearing the selected source also retires old
  loading/folder state instead of leaving stale folder controls behind.
- Generated-preview windows now have separate source streams, folders and databases. Closing
  the preview stops its model; its streams finish, and canceled seeding does not start another job.
  Every restarted source is a fresh stream owner.

## Static audit

Reviewed app/core source references, new feature entry points, async ownership and all Astro
component imports. All six website components, navigation entry point and styles are referenced;
no website source changes were needed.

Ran SwiftLint's compiler-backed unused-import and unused-declaration analysis against a clean
arm64 Debug build. The initial scan reported 32 candidates, including live serialized constants,
test diagnostics and explicit framework imports. Candidates were checked against callers and
Swift's synthesized/framework behavior rather than automatically deleted. Explicit framework
imports of OSLog are retained for the live logging code: SourceKit attributes Logger to the
re-exported `os` module. A trial requiring every transitive import was rejected because it also
demanded SDK implementation modules. The final import rule uses the standard transitive behavior
with this explicit OSLog exception. The unused CoreGraphics import was removed.

The durable schema-version, representation and connection-scope constants in backup/thumbnail
identity encoding must remain: removing them would change matching keys. The four Debug
coordinator counters are exercised by cancellation/queue-limit tests. Neither category is dead
code. Framework callbacks and Quick Look coordinator ownership likewise remain intact.

## Verification

- 416 core tests passed, including unchanged identity/migration, no-overwrite, recovery and
  lifecycle boundaries.
- 238 hosted app tests passed (654 total Swift tests). Six added tests cover independent preview
  environments, finished source streams, preview lease ownership, late read cancellation/failure,
  replacement by a new folder and error/retry behavior. Parameterized cancellation exercises both
  preview and Finder actions with late success and late failure.
- Strict SwiftLint passed on 166 source files.
- Astro check passed on 17 files: zero errors, warnings or hints.

- Normal Debug and arm64 Release builds passed. The read-only Release checker passed bundle,
  signature, reviewed entitlements, hardened runtime, icons, licenses and privacy manifests.
- Native View-menu inspection confirmed History remains enabled from Saved Originals and that
  each new destination is reachable. A generated original rendered in Quick Look and Escape
  dismissed it. Clearing the source removed stale folder controls. Closing/reopening the generated
  window successfully started a fresh source and reached the expected incomplete-backup state.

The final declaration scan contains 11 reviewed findings: seven synthesized encoded constants
and four Debug counters used by tests, with no remaining actionable declaration candidates.
The final configured unused-import scan passed with zero violations across all 166 files.
Logs are ignored local files under `apps/macos/build/cleanup-*`.

This audit cannot prove the absence of every possible runtime defect. It does not substitute
for real USB, removable-drive, OS notification, VoiceOver, sustained performance or distribution
acceptance. Those gates remain in [FEATURE-TODO.md](../FEATURE-TODO.md), with device testing last.
