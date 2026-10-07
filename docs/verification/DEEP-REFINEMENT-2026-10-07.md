# Library interaction and recovery refinement

7 October 2026 · CloakRoll 0.1.0 (15) · macOS 27.0.1 (26A434), Apple silicon.

## Changes

Arrow-key navigation follows the actual rows in each date group. Moving Down from
an incomplete final row now enters the same column in the next group instead of
skipping an item. A short row temporarily uses its nearest item and remembers the
intended column for the next vertical move. Clicking, moving horizontally, changing
column count or regrouping resets that preference. Shift extends and retracts the
selection from its anchor. Navigation is inactive while a sheet is presented.

Command, Option and Control arrow combinations remain in the native responder chain;
the grid no longer treats them as ordinary arrow presses. This also leaves VoiceOver
Control-Option chords alone. Settings now explains arrow-key range selection.

Rebuild Backup History shows the selected folder's actual path below its name, with
middle truncation and a full-path tooltip for long locations. Change opens the native
folder picker. The picker uses the sheet's task lifecycle, and cancellation/dismissal
is guarded while that picker is open: Escape cancels the picker first, preserving the
parent sheet and the current folder. A second Escape dismisses recovery when idle.

Show Backup Folder in Finder now requires readable access, rather than unnecessarily
requiring a writable folder. It retains the security-scoped lease through the Finder
request, fails visibly for unavailable folders, and does not claim write readiness.

## Actual native verification

- Reproduced the build-14 bug with the physical 2,078-item library in an 860-point
  window: Down from the 19th October item entered the right-hand September column.
  Option-Right also unexpectedly changed selection.
- Build 15: Down from the last October item enters the first September item in the
  left column; Up returns to the original item. Option-Right leaves selection intact.
- Shift-Down selects both boundary items; Shift-Up contracts back to the anchor.
  Space opens Media Info for that item. Down inside the sheet does not navigate the
  library. Escape closes it; Right then moves the grid selection, confirming focus
  restoration. Escape clears selection.
- Real photo preview and camera metadata inspected in Media Info. Settings General
  displays the new keyboard guidance without clipping.
- Recovery shows the real remembered destination path. Change opens the native picker.
  Escape closes only that picker; the parent sheet retains its destination. A second
  Escape returns to history. No recovery operation was started.
- Real library idle controls inspected in compact dark appearance. Sample verification
  progress inspected in compact dark and standard 1,100-point light windows; title,
  spinner, count, percentage and meter retain their compact hierarchy. Backup Details
  opens and Escape dismisses it. These sample states did not transfer any files.
- Existing real history and last completed backup remained visible: 18 items / 4.98 GB.

## Software verification

**393 core tests and 223 hosted app tests pass (616 total).** New tests cover uneven
section boundaries, preservation/reset of the preferred column, direction reversal,
resizing/regrouping, edge and empty states, bounds across many section/column sizes,
actual model range selection and modal guards, native modifier parsing, and read-only
or unavailable Finder destinations with scoped-access lifetime checks.

Final normal Debug and universal arm64/x86_64 Release builds passed, as did strict
SwiftLint and whitespace checks. No compiler warnings. Hosted tests emitted the known
nonfailing macOS linkd service diagnostics and intentional invalid-thumbnail diagnostics.
The actual Release bundle passed version, architecture, signature, sandbox entitlements,
hardened runtime, icon and privacy-manifest checks. ZIP integrity passed.

Archive: `apps/macos/build/releases/CloakRoll-0.1.0-15-local-universal.zip`.
SHA-256: `f83150ec6c63203e8fa0442b110f4f33300cc1267faea18e6c59d56f425a6b6c`.
Logs: `/tmp/cloakroll-deep15-core.log`, `-tests-final.log`, `-debug-final.log`,
`-lint-final.log` and `-release.log` (all share the `/tmp/cloakroll-deep15` prefix).

## Design references and limits

Apple's [focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/)
and [keyboard guidance](https://developer.apple.com/design/human-interface-guidelines/keyboards)
informed the native responder behavior. Existing system controls, semantic surfaces
and compact Liquid Glass containers were retained.

This is a targeted interaction and layout pass, not complete VoiceOver acceptance.
No original backup transfer, history recovery or physical cable interruption was run.
The outstanding hardware, sustained performance, accessibility, older-OS and signed
public-distribution gates in [RELEASE.md](../RELEASE.md) remain open.

## Installed result

The byte-identical universal Release is installed at `/Applications/CloakRoll.app`.
About reports **0.1.0 (15) · Development preview**. The previous installed app and
Debug/Release build app copies are recoverable in Trash. Backups, history and phone
folder mappings were retained.

The installed app reloaded the physical **2,078-item** library, recalled **iPhone 15 Pro
Max** with **Access checked**, and retained the last completed backup summary. It is
left in All Photos at standard window size, using system appearance, with no selection,
transfer or sample fixture active.
