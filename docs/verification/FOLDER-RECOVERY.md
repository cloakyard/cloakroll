# Folder-owned backup recovery

Implemented 5 October 2026 after the user approved one-time USB verification for
older folders without app history or recovery records. This recovers Mac backup
history; it does not write to an iPhone or require an iPhone app.

## Behavior

Backup History → Rebuild History opens a native sheet with a folder picker and two
methods. Saved recovery records work without an iPhone. Existing local database
records for the actual filesystem root are verified and exported automatically, so
older known backups gain portable recovery evidence. Merely selecting a similarly
named folder or a copied root is insufficient for exporting old database records.

The USB method additionally enumerates regular, non-hidden saved files recursively.
Sizes narrow the candidates; complete original downloads and fresh full-file SHA-256
comparisons establish matches. Filenames alone are never evidence. Renamed identical
files remain in place. A complete verified temporary download is removed after its
comparison; unmatched saved files are untouched. Missing resources are copied later
through the normal backup command, not during the recovery scan.

New persistent backups publish immutable versioned JSON receipts in the hidden
`.cloakroll-recovery` directory before finalizing originals. Incrementally reused
originals also gain receipts. A format marker and exclusive atomic publication avoid
overwriting unrelated metadata; receipt write failure prevents success from being
announced. Interrupted metadata temporaries are ignored. A receipt remains an intent:
recovery freshly checks local size/SHA-256 and safe paths before importing it.

Recovery can explicitly adopt copied folders after byte verification. Database import
is transactional, carries cancellation into GRDB's queue and deduplicates repeated
imports for the destination/root/receipt. Rebuilt sessions say **Recovered**, with the
recovery date and zero newly saved transfer bytes; they do not invent a historical
backup completion time. Logical items are complete only with every registered original.
Multiple iPhones retain separate identities even when device names and filenames repeat.

The native sheet has edge-aligned scrolling, standard radio buttons, measured file
counts, Command-period Stop and Escape dismissal when settled. Recovery participates
in the app's exclusive source/destination ownership and deferred-Quit path. Late source
callbacks cannot release the folder lease early or publish cancelled matches. A final
local scan follows USB comparison before history is imported.

## Automated evidence

376 core tests and 162 hosted app tests pass. Added coverage includes:

- Empty-database reconstruction from a copied root, reopened history, repeat import,
  reconnect matching and normal incremental backup with zero source calls.
- Missing and changed Live Photo companions: no complete-item claim, only missing
  component transfer, and preservation of changed unrelated bytes.
- Separate iPhones with identical names; root-scoped preparation of older evidence;
  aborted database transaction and pre-cancelled import leaving no recovered history.
- Invalid receipts, missing companion membership, escaping paths, symlinks, hard links,
  absent published files and conflicting valid content all remaining unverified.
- Media-only recovery with a renamed matching photo, rejection of same-name/same-size
  different bytes, no second USB read of a verified indexed file, preserved saved inode,
  temporary-copy cleanup, Stop and a late physical callback.
- App-owned automatic receipts, reconstruction into an isolated fresh database, repeated
  recovery without duplicate rows, stale folder choice, balanced scope ownership,
  cancellation while folder work is suspended, and blocking a new backup during recovery.

Core logs: `/tmp/cloakroll-recovery-core.log`. Hosted logs:
`/tmp/cloakroll-recovery-app-tests.log`. These are local development evidence, not
physical interruption or power-loss acceptance.

## Physical evidence

Normal sandboxed Debug build, macOS 27.0.1, Sumit's connected iPhone exposing 2,073
logical items. Actual app data was preserved; no uninstall or deletion of its database.

1. Selected the previous bounded acceptance destination containing six originals /
   five logical items / 2,912,814,777 bytes. Reselection initially showed zero backed-up
   items because the destination selection had a new UUID. Rebuild checked all six,
   prepared portable receipts, and produced a Recovered session containing five items.
   The live library changed to five Backed Up / 2,068 Not Backed Up.
2. Created a separate validation folder with four existing originals / three items /
   10,350,931 bytes and no receipts or database records for that root. Renamed the PNG
   to `Renamed Photo.PNG` before scanning. USB recovery verified four originals and
   restored three live backed-up items; no saved-media duplicate or staging folder
   remained after the comparisons.
3. Selected those three recovered items and ran the normal backup command. Session
   `D54E7D40-6915-4862-A6B7-D7F4910398EA` completed with four verified resources,
   10,350,931 verified bytes and **0 transferred bytes**. The validation folder still
   contained exactly four media files, including the renamed photo.

Indexed recovery session: `B382BE09-DC29-420E-99C9-3D7AFE6F6AC6`.
Media-only recovery session: `88D1B6C5-E6FE-4271-89E3-3FE13C2222AD`.
Original test-file baseline is recorded in `/tmp/cloakroll-recovery-before.json`.

## Limits and remaining checks

The selected folder must be writable for preparing receipts and temporary USB originals.
Keep the entire folder, including hidden recovery records, when moving a backup. The
scan is bounded to 200,000 entries, 32 nested media directories, 256 KiB per receipt
and 512 MiB total receipt data. Unsupported, malformed or ambiguous evidence is not
adopted. Session-only or ambiguous device identities remain conservative on reconnect.

Stopping during an incomplete USB read may preserve an isolated hidden staged file;
CloakRoll does not delete an unverified or replaced file by filename. Completed receipt
work survives Stop and can be checked again. There is no claim of filesystem-wide
snapshot isolation if another application edits a backup concurrently; the normal
incremental matcher freshly verifies files again before showing backed-up status.

Empty-database loss, two-device recovery, cancellation and unsafe-file scenarios were
controlled automated checks; the bounded real-media checks above do not replace a
physical cable pull during recovery, external-volume failure, power-loss durability,
100k-item recovery measurements, full VoiceOver or older-OS runtime acceptance. The
broader release gates in `../RELEASE.md` remain open.
