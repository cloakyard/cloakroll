# Saved-backup integrity check — 5 October 2026

## Scope and behavior

Expand a session in Backup History and choose **Check Saved Files…**. The selected
sidebar folder must be the original backup root. The check works from the local
history and files without an iPhone connection, compares every recorded component's
size and SHA-256, and reports current matches separately from the historical result.
A stopped or incomplete session only checks its committed originals. Zero records
means “No Saved Originals to Check,” never a successful complete backup.

The native sheet has a stable heading, completed-file progress, Stop, Check Again,
and Done. Counts are aligned, long issue lists scroll at the sheet edge, and the list
retains at most 100 paths while counting all unverified files. Read errors, missing
files, modified bytes and unsafe paths cannot become matches. A check never repairs
or downloads a file, changes the backup result, or claims source-library completeness.

## Identity and access

The history read is scoped to the exact session/destination and rejects running or
inconsistent records. Access uses a separately owned read-only security-scoped lease;
its lifetime includes cancellation cleanup. Successful read access does not mark a
read-only destination writable. Stale bookmark refresh and folder selection races
retain the existing guards.

Rechoosing an older folder currently assigns a new selection UUID. The checker accepts
an explicitly selected root even when that UUID differs from the historical one,
but requires the recorded filesystem identity before reading any original. It never
matches by display name or path alone. Copies on another root/volume are deliberately
rejected, even if bytes are identical. Remembering all previously selected destination
identities for incremental backup remains a separate limitation; this feature does
not change incremental matching or silently merge destination histories.

## Automated verification

All **363 core tests** and **158 hosted app tests** pass. New coverage includes real
file hashes, missing/changed/truncated files, symlink/path redirection, copied roots,
invalid/duplicate records, bounded issue lists, cancellation before and after hashing,
empty and partial sessions, exact database scope, unchanged historical outcomes,
read-only leases, concurrent readiness checks, selection races, reselected original
roots, and balanced access after cancellation. Tests use controlled temporary fixtures;
they do not replace physical interruption acceptance.

Normal Debug build, strict SwiftLint and whitespace checks pass. Logs:
`/tmp/cloakroll-saved-check-core.log`, `/tmp/cloakroll-saved-check-app-tests.log`,
`/tmp/cloakroll-saved-check-debug.log`, `/tmp/cloakroll-saved-check-lint.log`.

## Real saved-file and native UI checks

Used only the separate `Backup/CloakRoll Acceptance 2026-10-05` validation copies
from the earlier physical iPhone import. No new backup or device write was started.

- Selecting a different existing root produced a clear folder-mismatch result.
- The reselected original root passed despite its new selection UUID: three items,
  four original components, 10,350,931 bytes, including a Live Photo's two files.
- Temporarily renamed one validation HEIC. The next check reported three matches
  and exactly one unverified path. Restored the same inode/size; Check Again returned
  four matches. The check itself made no repairs.
- The 1,768,397,510-byte saved video passed. A fresh check stopped while hashing and
  showed “Check Stopped,” zero of one checked. Retry completed with one match.
- A historical cancelled session with zero saved resources showed the unfinished
  explanation and “No Saved Originals to Check.”
- UI inspection prompted aligned count rows, a smaller sheet and explicit keyboard
  shortcuts to prevent Escape from accidentally invoking the retry action.
  Verified Escape dismisses an active/finished check, Command-period stops, and
  Command-R retries. Native light/dark results and active progress were inspected;
  system appearance and the original backup destination were restored.

Remaining V1 cable/external-volume interruption, new-capture reconnect, sustained
performance, full VoiceOver/accessibility, macOS 14 runtime and distribution gates
remain open in `../RELEASE.md`. These local checks do not close those gates.
