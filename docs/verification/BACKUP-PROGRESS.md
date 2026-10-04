# Measured backup progress — 4 October 2026

The active backup footer now uses an explicit native linear `ProgressView` with a
percentage, processed/expected bytes, completed item count, current original and
separate newly transferred bytes. The destination caption reflects the active phase.
The footer remains available when navigating to Backup History.

## Accounting and completion

- Progress is verified original bytes plus received bytes awaiting verification.
  Moving a resource into the verified counter clears its current counter atomically;
  entering verification, changing files and requesting Stop retain measured progress.
- Reused originals contribute only after verification and add no transferred bytes.
- Unknown totals use native indeterminate progress; known totals begin at zero.
  Counts and fractions are bounded, addition avoids overflow and percentages round
  down so floating-point rounding cannot prematurely produce a 100% label.
- A source success callback alone does not fill missing byte callbacks. That fill
  occurs only after staged-file size and SHA-256 verification succeeds. A truncated
  or oversized file with no progress callback therefore cannot invent transferred bytes.
- 100% data is distinct from completion: verification and saving history retain an
  explicit phase label and activity indicator. `Backup Complete` is shown only once
  the controller settles. Stop remains available and disables while stopping.
- The native meter disables implicit value animation so its fill follows the same
  snapshot as the numeric percentage. No elapsed-time estimate or synthetic progress
  is used for real backups.

## Native UI checks

The normal sandboxed Debug app was inspected at standard and compact widths with
app-local light/dark appearance (system preferences were not changed). Debug examples
exercise the same production view and explicitly identify themselves as illustrative.

| State | Observed result |
| --- | --- |
| Copying | 33%, native fraction 0.3369565, 6.2 of 18.4 GB, 63 of 247 items; aligned text and visible Stop. |
| Verification | Full bar and 100%, with `Verifying Originals…`, activity and 246 of 247 completed items. |
| Stopping | Retains the 33% meter; `Stopping Backup…` and disabled Stop. |
| Preparation | Indeterminate meter without an invented percentage or byte total. |
| Finalization | Full meter with `Finishing Backup…`, not a completion announcement. |
| Backup History | Persistent footer remains visible while the history list scrolls behind the native bottom surface. |
| Accessibility | Native progress value plus percentage, byte and item descriptions are exposed. Full VoiceOver interaction was not tested. |

These examples validate layout and semantics, not physical transfer acceptance.

## Physical checks and automated verification

- **338 core tests** and **125 hosted app tests** pass. New coverage exercises
  transfer/verification boundaries, atomic byte ownership, reused originals, stale
  callbacks, Stop, pending persistence, size mismatch, unknown/invalid totals and
  integer/percentage boundaries. The hosted suite also checks bar visibility in History.
- XcodeGen, normal Debug and Release builds, strict SwiftLint, whitespace and both
  app signature checks pass. No compiler warnings were introduced. Hosted tests emit
  the existing macOS `linkd.autoShortcut` service diagnostics without test failure.
  The normal Debug build removes test-host PlugIns before physical device use.
- A connected physical iPhone exposed 2,071 items. Two single-video backups completed:
  185,587,821 bytes and 1,134,066,336 bytes. Independent size/SHA-256 reads matched
  their persisted records. The final build repeated the larger transfer after removal
  of only its previous test copy and again completed with an identical hash.
- The real footer showed zero/start, current filename, byte total and enabled Stop;
  the first transfer also exposed the verification/100% state. Destination text followed
  the active phase. Transfers completed before a reliable intermediate percentage was
  captured. Smooth intermediate physical callback cadence is therefore **not claimed**;
  deterministic callback tests and native examples verify the arithmetic and partial bar.
- Before these checks the selected destination contained no files. Both test copies were
  verified against an exact path/size/hash manifest and removed after testing, reclaiming
  1,319,654,157 bytes on the final cleanup. No phone original was changed or deleted.
  The destination is empty again and this task left no unresolved journal. Two older
  unresolved journal entries from the 13:14 and 13:21 sessions remain untouched.
- The phone became unavailable after the successful final transfer and before the
  post-cleanup `Check Saved Originals` command. That command was disabled; the cached
  two-item backup badge will be reevaluated on the next connection. History is retained.
  The app is left in All Photos, normal live mode, standard size and System appearance.

Logs: `/tmp/cloakroll-backup-progress-size-full-core.log`,
`/tmp/cloakroll-progress-app-tests-final.log`, `/tmp/cloakroll-progress-build-final.log`,
and `/tmp/cloakroll-progress-release-final.log`. The local cleanup manifest is
`/tmp/cloakroll-progress-copies.json`; private media and device identifiers are not
checked into the repository.

Physical interruption during this particular UI pass, full VoiceOver, increased contrast
and macOS 14 runtime behavior were not revalidated. No broader phase gate is promoted.
