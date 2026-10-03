# Phase 7 — interruption and publication recovery

Date: 3 October 2026. Implementation and automated/process-boundary verification pass.
Physical interruption, external-volume and power-loss acceptance remain separate checks.

## What changed

The additive `v2_publication_journal` migration preserves Phase 6 history and adds a journal table.
An entry is created for each staged download; reusing a verified original needs no new staging
entry. The app awaits a committed staging intent before requesting an
original. After exact-size verification, streamed SHA-256 and file synchronization, it awaits a
publication intent before **each** exclusive rename attempt. Filename collisions update only the
proposed path; the source, verified bytes and exact file identity remain fixed.

The intent retains source/session/resource scope, owned staging path, destination-root identity,
final relative path, size, digest and filesystem device/inode/birth/modification/change evidence.
Publication checks the file and complete path again after the database await. Verified-record
insertion, session counters and journal resolution commit together. Cancellation does not abandon
an in-flight journal write or physical ImageCaptureCore callback; leases stay open until settlement.

On a later history check, the app examines unresolved intents from non-running sessions at the
selected destination. Recovery reads only the exact journaled paths with no-follow descriptor
access. A freshly hashed final original must match its recorded filesystem identity as well as
content; identical bytes in another inode do not prove that a rename succeeded. Saved pre-rename
change time is omitted for final-file identity because rename can change it; each fresh hash still
checks current change time for mutation. Reconciliation is
idempotent and preserves the old interrupted/failed/cancelled session outcome. Current catalog
matching and fresh local verification still precede a backed-up badge.

This stage recovers **published originals only**. Verified staged bytes and unverified partials
remain preserved, pending and unverified. It does not resume an incomplete byte stream or silently
publish a staged file after restart. Retrying may copy that component again. Empty owned staging
is removed; ordinary cleanup retains the ownership marker when partial or unknown content remains. Original-file
cleanup no longer deletes a pathname without verified file identity. This can leave hidden staging
directories until a future explicit, evidence-based cleanup workflow is implemented.

Marker cleanup checks its contents and identity before unlinking. That check and unlink are
separate POSIX calls, so it cannot promise atomic protection against a hostile concurrent marker
replacement. Original and partial media filenames are never unlinked by this cleanup.

Filesystem failures now distinguish full/quota-limited storage, read-only drives, lost destination
access and permission failures with actionable text. No new source mutation or deletion API,
conversion, network service, entitlement or third-party dependency was added.

## Automated evidence

- **266 core tests pass**, including 41 engine and 28 persistence tests. Migration tests retain
  existing Phase 6 records; injected SQLite failure rolls back record/counters/resolution together.
- **53 hosted app tests pass**. New integration cases verify staging-before-source, publication
  evidence retained after record failure, reopened/rebased recovery without a second source call,
  same-size tampering and same-content replacement rejection, failed-source state and stale
  history-generation isolation. The cancellation test now explicitly expects preserved unverified
  bytes plus the ownership marker and zero verified resources.
- Engine cases cover awaited/cancelled journal hooks, publication write failure, every collision
  attempt, mutation across the journal await, wrong roots/paths/markers, folder replacement,
  source failure, full-disk failure and unknown-content preservation.
- Independent review reproduced a fractional-Date replay failure caused by converting Foundation
  reference-epoch dates through SQLite Unix doubles. Existing-record equality now normalizes only
  stored timestamp precision; exact source signatures, paths, hash/size and journal file identity
  remain unchanged. Direct-callback and reopened-recovery replay regressions pass.
- Normal Debug build, strict lint, whitespace and signature verification pass without compiler
  warnings. Normal sandbox entitlements are USB, app-scoped bookmarks, user-selected read/write,
  Photos library and Debug inspection; no hosted-test additions remain.
- Logs are local only: `/tmp/cloakroll-phase7-core-tests-final.log`,
  `/tmp/cloakroll-phase7-app-tests.log`, `/tmp/cloakroll-phase7-normal-build.log`.

## Abrupt process-exit evidence

A separate temporary Swift executable linked the public package products and transferred a
1,024-byte generated fixture. It called `_exit` at three controlled boundaries; a new process
then reopened SQLite, inspected exact journaled paths, reconciled and revalidated new runtime
source IDs. No production crash hook or personal media was used.

| Exit boundary | First reopen | Second reopen |
| --- | --- | --- |
| Staging intent committed, before source | Interrupted; 0 verified; one unresolved entry | Same; no false success |
| Publication intent committed, before rename | Exact staged bytes identified; 0 verified; one unresolved entry | Same; no automatic publication |
| Rename completed, before record commit | One published original recovered; 1 verified / 1,024 bytes; no unresolved entry | Same single record; no duplicate count |

The old session remains interrupted even after its one resource is recovered. This demonstrates
actual child-process termination/reopening of the package workflow. It is **not** an app-level
USB interruption, kernel crash, external-drive removal or physical power-loss test.

## Hardware and UI follow-up

Phase 6's 3 October follow-up records the normal app's real three-item/four-original import,
relaunch recognition and zero-transfer repeat. The recovery build must additionally be observed
with the connected phone after migration. Deliberate unplug during transfer, external drive
removal/full disk and app interruption remain pending unless evidence is appended below.

No personal media, device identifier, database contents or screenshots belong in this document.

## 3 October 2026 — second-device physical follow-up

The normal a007e84 app (PID 29419) read a different physical phone exposing 2,066 logical
items / 3,993 original resources. Its initial Backed Up count was zero in the existing destination,
consistent with device-scoped history. One Live Photo copied two originals / 6,933,041 bytes.
Repeating that selection verified both with zero transferred bytes and no additional source calls.
Two bounded video selections copied 185,587,821 and 1,768,397,510 bytes respectively; each
completed and fresh independent SHA-256/size checks passed. The app reported three backed-up
logical items. All eight unique database-referenced originals passed independent verification,
all eleven pre-existing destination files remained byte-for-byte unchanged, and the destination
contained fifteen files / 2,152,695,355 bytes. No unresolved publication journal remained.

The videos completed before the automation returned an actionable Stop control; these are
successful import checks, **not cancellation acceptance**. Physical transfer interruption,
external-drive removal/full disk, and app termination during USB transfer remain pending.

After the user took a new photo, the same process observed 2,067 logical items / 3,994 resources:
2,064 Not Backed Up and three Backed Up. The new photo was visibly Not Backed Up. The user
reported a cable reconnect, but this observation window did not capture a disconnect/rediscovery
transition, so physical reconnect/cache-reuse acceptance is not claimed from that report alone.

Before the requested reconnect, thumbnail metrics were: 86 loads, zero active/queued/failed,
34 encoded hits, 6,057,405 encoded bytes / 86 entries, zero disk hits, 6,094,561 disk bytes /
86 entries, 164 decoded hits, 66 decodes and 49,526,976 decoded bytes / 66 entries. Framework
outstanding work reached at most two and settled to zero. This bounded viewport observation
does not establish a sustained memory plateau. Only aggregate evidence is retained here.

A final bounded 1,134,066,336-byte video also completed before its Stop menu command could
be activated. Four logical items / five original files are now backed up from this phone.
Independent verification passed for all nine unique database-referenced originals; all eleven
pre-existing destination files remain unchanged. The destination has sixteen files /
3,286,761,691 bytes and zero unresolved journal entries. History presents all seven completed
sessions, including prior-device sessions, while current library status stays scoped to this phone.

## Cooperative cancellation during preparation

Backup registration now checks cancellation before validation and at each full-catalog identity,
selected-asset and original-resource boundary, including its final return. The previous
uncancellable collection passes are replaced by checked loops. Registration preserves identity
uniqueness, exact component membership and existing validation. SQLite transaction interruption
and physical ImageCaptureCore ownership remain unchanged: a Stop request cannot release the
source slot or destination scope before physical work settles.

All **287 core tests pass**, including 42 persistence tests. The new suite's three tests/six cases
cover pre-cancelled public registration (CancellationError, all eight registration/evidence
tables empty and zero downstream source calls), deterministic actual task cancellation during
each preparation loop, and successful uncancelled registration of 100 originals. The internal
test seam introduces no public API or timing-based sleep. Compiler warnings/errors and
whitespace checks are clear. Logs: `/tmp/cloakroll-preparation-cancellation-core.log`.
This validates preparation cancellation, not an interrupted physical USB request.
