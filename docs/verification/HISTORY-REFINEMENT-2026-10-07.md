# Backup history and saved-file check refinement

7 October 2026 · CloakRoll 0.1.0 (14) · macOS 27.0.1 (26A434), Apple silicon.

## Changes

Expanded history now keeps labels and values in a compact, leading-aligned grid.
Native bordered actions sit beneath the detail, and Check Saved Files is also in
the row’s context menu. Completed, recovered and unfinished results remain distinct.
A stopped backup with nothing saved says **No originals saved** and offers no empty
check. A partially saved Live Photo shows its saved original count even when no
whole item finished; those originals remain checkable.

Check Saved Files opens a compact review sheet before hashing. It recalls the
bookmark belonging to that session, independently of the sidebar destination. If
no bookmark remains, the user must choose the original folder. Change opens a native
existing-folder picker; cancelling preserves the choice. The selection and any
bookmark refresh live only in this check, so neither phone mappings nor backup history
are rewritten. Readable, read-only folders are allowed. The original identity and
checksum checks remain in force; a different folder is never accepted by name alone.

The sheet grows to show results, keeps scrolling at the edge, and provides native
Cancel/Check Files before work and Check Again/Done afterward. Return triggers the
primary action; Escape dismisses the check and cancels its work. While the folder
picker is open, Escape cancels just the picker. Stop/cancellation retains the existing
lease-lifetime guarantees. Help and README describe the updated flow.

## Actual UI verification

- Standard 1,100-point light and compact 860-point dark windows: history headings,
  expanded metadata, status summaries and check sheet inspected without overlap.
- Right-clicking a collapsed session opened the native Check Saved Files action.
- A real completed session (7 October, 3 Live Photos, 6 originals, 16.1 MB) recalled
  **CloakRoll Acceptance 2026-10-07**, while the sidebar retained **iPhone 15 Pro Max**.
- Return checked all six saved originals successfully. No new USB transfer was made.
- Cancelling the native folder picker preserved the original choice and parent sheet.
- Explicitly selecting the other existing backup folder returned the filesystem identity
  error before file checking. Reselecting the original folder reset the old result;
  the next check matched all six originals. Escape returned to unchanged sidebar state.
- Reopening the check still recalled the original session folder. Light/dark sheet
  appearance, Return completion and Escape dismissal were inspected.
- The physical 2,078-item iPhone library became available during the Debug review;
  last completed backup stayed 18 items / 4.98 GB. This is connection evidence only.

The native history list exposes aggregate rows to the inspected accessibility tree.
The context menu and sheet actions were inspected, but a complete VoiceOver/keyboard
navigation audit remains open; this pass does not claim full accessibility acceptance.

## Software checks

**393 core tests and 214 hosted app tests pass (607 total)**. Seven additional test
functions cover isolation from both phone mappings, unknown-bookmark handling, cancelled
selection, read-only selection, a real temporary-folder checksum check, partial Live
Photo companions across four terminal outcomes, and running-session action gating.

Strict SwiftLint, whitespace checks, final normal Debug build and universal arm64/x86_64
Release build passed. No compiler warnings. Hosted tests emitted the known nonfailing
macOS linkd service diagnostics and deliberate invalid-thumbnail fixture diagnostics.
The actual Release bundle passed signature, sandbox entitlements, hardened runtime,
architecture, version, icon and privacy-manifest checks. ZIP integrity passed.

Archive: `apps/macos/build/releases/CloakRoll-0.1.0-14-local-universal.zip`.
SHA-256: `84e0ae1e0e43f17c70fd2787420980f701701b1f1c2957e3bac68232ec9e803e`.

Logs are under `/tmp/cloakroll-refine14-`: `core-tests.log`, `app-tests-final.log`,
`debug-final.log`, `lint-final.log`, and `release.log`.

## Design references and limits

Apple’s [disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls),
[buttons](https://developer.apple.com/design/human-interface-guidelines/buttons),
and [menus](https://developer.apple.com/design/human-interface-guidelines/menus)
informed the detail hierarchy and secondary action placement. This uses native
controls and semantic surfaces, with no extra glass behind ordinary metadata.

The broader [release gates](../RELEASE.md) remain open: cable interruption during a
real transfer, removable-volume/full-disk cases, two physical iPhones, sustained
scrolling/RSS, full accessibility/older-OS runtime, and notarized distribution.


## Installed result

The byte-identical universal Release is installed at `/Applications/CloakRoll.app`.
About reports **0.1.0 (14) · Development preview**. The superseded installed app and
Debug/Release build app copies were moved to recoverable Trash; backups, saved history
and phone mappings were retained. The final installed app is in All Photos with the
real **2,078-item** library, the remembered **iPhone 15 Pro Max** destination marked
Access checked, and the same last completed backup. No selection or transfer is active.
