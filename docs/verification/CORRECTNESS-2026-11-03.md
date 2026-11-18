# Correctness audit — 3 November 2026

Follow-up audit of the next-beta backup, continuation, saved-library and notification paths.
Changes remain on `dev` in draft PR #13. Physical testing remains the final acceptance stage.

## Confirmed defects and fixes

- **Same-connection retry:** the persistent-continuation gate rejected a retry if the phone or
  item had session-only identity. Continuation now accepts that evidence only on the original
  source session, with exact runtime asset/resource addresses, canonical evidence, digests and
  reuse eligibility. Reconnect still requires a persistent phone and unambiguous reusable
  identities. Destination, organization, original selection and single-continuation checks remain.
- **Saved-library source stability:** selection used the latest attempt UUID, so a new attempt
  could silently move the selection to the first phone/folder after Refresh. Source identity now
  uses the device/destination pair; the latest attempt remains separately available. Health's
  folder check still refreshes when its latest attempt changes. Starting a page load also clears
  the old next-page cursor, so failed loads cannot offer a cursor from an earlier query.
- **Notification ordering:** an older permission response could overwrite a newer response;
  an obsolete enable request could still prompt after disabling; and a late authorization error
  could replace the current settings state. Permission reads and preference changes now reject
  stale results. Delivery rechecks the relevant enabled preference after awaiting permission,
  without losing an in-flight reminder when only the outcome preference changes. Errors from
  superseded delivery/configuration operations are discarded.

The existing journaled publication, exact destination identity, saved-file rehashing, no-overwrite
publication and incomplete-transfer boundaries remain intact. No fallback matches by filename.

## Verification

The new core regressions and first three notification race tests were run against the old
implementation and failed with the expected defects before the fixes were applied.

- **418 core tests passed**, including the new source-identity and session-only continuation
  regressions plus existing identity, corruption, migration, filesystem, recovery and cancellation
  suites. The continuation regression checks both persistent and session-only phones, rejects a
  new connection and changed runtime asset addresses, and preserves the continuation link.
- **244 hosted app tests passed**: **662 total Swift tests**. A new integration test uses the real
  identity builder, database and generated files to fail a Live Photo's motion component, retry
  on the same session-only phone, transfer only the missing 2 bytes, preserve the 3-byte still,
  retain the failed original history entry and release every destination lease.
- Five deterministic notification ordering tests control suspended permission/authorization
  operations. They cover newer-result ownership, obsolete prompts/errors, disabling during an
  outcome's permission check and retaining reminders during an unrelated preference change.
- Strict SwiftLint passed across 166 source files, and `git diff --check` passed.
- Normal arm64 Debug and Release builds and the read-only Release bundle checker passed.

Logs are ignored local files under `apps/macos/build/bug-audit-*`. The earlier generated-data
native UI evidence remains in [the feature audit](NEXT-BETA-2026-11-03.md); this pass adds
automated regression evidence and does not claim a new hardware or OS-delivery check.

Real iPhone/reconnect, removable-drive/full-disk, sleep/wake, real notification delivery,
VoiceOver, sustained performance and distribution gates remain open in
[FEATURE-TODO.md](../FEATURE-TODO.md). These checks establish the tested fixes, not the absence
of every possible runtime defect. No release, installed-app replacement or production deployment
is performed by this audit.
