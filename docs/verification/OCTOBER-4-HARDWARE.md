# 4 October 2026 — cleanup, incremental and interruption checks

The normal sandboxed build at `8c04296`, process 72327, exposed a physical iPhone with
5,140 logical items (3,849 photos, 1,291 videos, including 2,797 Live Photos). The existing
history contained seven sessions across two persistent device identities. This is a single
currently connected phone; it does not establish simultaneous-device selection acceptance.

## Requested cleanup

The user explicitly requested removal of previous iPhone backups to reclaim space. All sixteen
files in the known CloakRoll verification destination matched the previously recorded size and
SHA-256 baseline. Exactly those files were removed: **3,286,761,691 bytes**. No extra or changed
files were found. Empty directories were pruned and the selected destination itself was retained.
Persistent history was retained to test missing-file handling. No source iPhone media was changed.
Private paths, filenames and hashes remain outside the repository.

## Incremental and missing-file evidence

A selected previously backed-up photo was backed up after its local file had been removed.
The app freshly checked the candidate and downloaded **533,294 bytes**. The new file independently
matched its recorded size and SHA-256. An immediate identical selected repeat completed with
one verified original / 533,294 verified bytes and **zero transferred bytes**, with no second
original-download request in the process log. Historical verification is not treated as proof
that a deleted local file still exists.

## Actual Stop and retry

Exactly one 231,289,653-byte video was selected. The native Command-period shortcut was sent
immediately after starting its backup. ImageCaptureCore logs show:

- 13:14:55.424: actual original download started, one outstanding operation.
- 13:14:55.464: stop requested; waiting for completion.
- 13:14:55.537: framework error `com.apple.ImageCaptureCore`, code `-9937`; operation settled,
  zero outstanding operations.

The UI displayed **Backup Stopped — 0 of 1 item backed up**, zero verified originals and a
usable Try Again action. SQLite recorded the session as cancelled with zero completed items,
verified resources, verified bytes and transferred bytes. No video was published and no staging
file remained. One unresolved staging journal intent remained; it is not a verified backup record.

Try Again completed one original / **231,289,653 bytes**, independently verified by file size and
SHA-256. The earlier cancelled intent remains conservative history and is not silently promoted
by a later transfer. This is actual Stop-during-transfer acceptance on this device/runtime; it
does not establish physical cable-removal, app-crash, external-drive or every interruption boundary.

## Remaining physical checks

Coordinated cable removal, new capture/reconnect, simultaneous phone selection and the new
per-device folder layout still require their own observations. No mock or generated-source
test substitutes for these checks. Small new test backups created after cleanup are accounted
for separately from the sixteen removed prior files.

## Actual Quit during transfer

After independently checking the completed 231,289,653-byte test video, it was removed to
reclaim the new test space and force another physical download. The same single item was
selected, its backup started, and native Command-Q sent immediately afterward.

- 13:21:19.753: actual original download started, one outstanding operation.
- 13:21:19.804: stop requested; waiting for completion.
- 13:21:19.868: ImageCaptureCore cancellation result `-9937`; original operation settled.
- 13:21:20.028: discovery stopped after the original callback had settled.

The app process exited. The saved session was cancelled with zero completed/verified items,
verified bytes and transferred bytes; no unfinished video was published. Only the 533,294-byte
photo remained in the test destination. This validates graceful Quit during an actual download,
not a forced crash or physical disconnect.
