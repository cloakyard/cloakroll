# Select and deselect date groups — 7 October 2026

Build **0.1.0 (11)** adds native **Select Date Group** and **Deselect Date Group** commands
to the date-label context menu. Library → the same commands acts on the active photo's
group; named accessibility actions expose both operations on each date heading. General
Settings and the label's help text describe the interaction.

The design keeps the existing compact Liquid Glass label and native material fallback.
Only the capsule receives the context menu, so its transparent pinned row does not block
photo selection. Native menu parity follows Apple's
[context-menu guidance](https://developer.apple.com/design/human-interface-guidelines/context-menus)
and [menu guidance](https://developer.apple.com/design/human-interface-guidelines/menus).

## Selection behavior

- Select adds the displayed group's members, including already-backed-up items, to the
  current selection. Deselect removes only those members. Neither starts a backup.
- Filters and filename search define membership; hidden assets are never included.
  Day, month, year, automatic grouping and unknown dates use the projected section.
- The first newly targeted group member in the current sort order becomes the range anchor
  and active item. Removing a selected anchor repairs it using remaining visible selections.
  Removing the last group clears focus and the anchor. Normal Shift selection remains usable.
- Each target carries the snapshot revision and connection session. Pending/changed
  projections, changed grouping, missing groups, retired sessions, disconnected/restricted
  or foreign devices, another screen, and open sheets reject the action.
- No filesystem, backup status, original media or device-write behavior changes.

## Automated and build evidence

All **384 core tests** and **199 hosted app tests** passed. Four new headless selection
tests cover additive selection, current ordering, anchor repair, repeated actions, hidden
members and unknown IDs. Seven new app tests cover actual backup candidate sets, partial
selection, clearing the final group, filter/search scope, stale projection/grouping/session,
unavailable or foreign devices, another presentation, empty libraries and unknown dates.

XcodeGen, strict SwiftLint (134 files, zero violations), normal Debug after hosted tests,
universal arm64/x86_64 Release, whitespace checks and actual Release/installed-bundle audit
all passed. Both normal build logs contain no compiler warnings or errors. ZIP integrity
passed. Logs: `/tmp/cloakroll-date-group-{tests,core,lint,debug,release}.log`.

## Native UI evidence on macOS 27.0.1

Normal Debug, illustrated fixtures:

- Right-clicked the first date label and selected all eight items. Initially Deselect was
  disabled; after selection, Library → Select Date Group was disabled and Deselect enabled.
- Invoked the second heading's accessibility action: 16 selected. Library → Deselect Date
  Group removed its eight items and kept the original eight. Shift-Right then selected the
  expected first two items; Escape cleared them.
- Videos filter displayed one item per date. Selecting its first date selected only that video.
- Inspected standard light and compact dark windows, including a pinned glass date label
  over scrolling photos. Clicking the visible photo beside the pinned capsule selected that
  photo, confirming that the transparent header area does not intercept it. The pinned
  capsule's native menu remained readable and functional with a partial selection.
- Restored System appearance and Standard Window after the visual checks.

Installed Release, physical iPhone library:

- About showed **0.1.0 (11)**; the General hint fit without clipping. The 2,078-item library
  reconnected after relaunch with the original destination showing Access checked.
- October's context action selected exactly 19 items and the backup button read “Back Up
  19 Selected”. September's assistive action added 185, giving 204 selected.
- Deselecting October left exactly 185 selected. The Library menu correctly disabled Select
  for the active September group; Deselect cleared all remaining selection and disabled Info.
- Left All Photos at the top, with no test selection. No backup was started during this stage.

This is physical browsing/selection evidence, not cable-interruption or transfer acceptance.
Full VoiceOver sessions, older macOS runtime, sustained scroll performance, device/drive
interruption and distribution gates remain open.

## Installed artifact

Installed the byte-identical audited Release at `/Applications/CloakRoll.app`; the prior app
and build copies are recoverable in Trash. Existing originals, history and folder preferences
remain. The local ad-hoc universal archive is
`apps/macos/build/releases/CloakRoll-0.1.0-11-local-universal.zip`.
SHA-256: `c9d99e835afcdd04994717ed0ea4ec37f3af611e38e494d9c1e8378fc7c23969`.
