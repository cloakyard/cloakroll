# Phase 8 — native history and interaction refinement

Date: 3 October 2026. The history, menu and preference stage is implemented and verified below.
Phase 8 remains in progress; this is not final accessibility, icon or hardware acceptance.

## Implemented behavior

- **Backup History is available without an iPhone.** A dedicated sidebar destination shows up to
  100 recent sessions from local history. Standard list rows and disclosure controls expose date,
  device, outcome, logical items, verified original components and bytes. Expanded rows distinguish
  verified bytes from bytes transferred during the session, including zero-transfer repeats.
- History retains completed, stopped, incomplete and interrupted outcomes. Its explanatory note
  makes the distinction between recorded verification and checking the current files again.
  Viewing history does not acquire a destination lease, download an original or claim a present-day
  backed-up status for an unavailable source catalog.
- A matching selected destination exposes its stored display name and **Show in Finder** through
  the existing scoped access path. Other destinations show **Another backup folder** or **Not
  selected**. The app does not guess a missing path or offer a misleading per-row folder action.
- Native loading, empty and failure presentations include retry. Failed refreshes retain the last
  good session list. Generation checks prevent older results or errors from replacing a newer
  query, and overlapping initial loads do not issue duplicate reads.
- History has its own refresh action; library search, thumbnail options and the backup action bar
  stay in the library. The compact sidebar label **Recent Backups** still filters the current
  library; **Backup History** is the separate saved-session destination. The former three-row
  history preview has been removed from Settings.
- Standard menu commands expose Find (⌘F), sidebar visibility, library/history navigation, view
  choices, Info, filename copying, deselection, backup, stop, history refresh and folder actions.
  Context actions use the selected batch only when the clicked item belongs to it; a click outside
  that batch targets that item without changing selection. Unavailable context backup actions
  are omitted, and menu commands reflect the current screen and operation state.
- Small/Medium/Large thumbnail size, sort, grouping and the last Settings pane are remembered in
  local preferences. Invalid saved values fall back independently. The size choices remain native
  pickers; no continuous slider or replacement custom control was introduced.

The implementation uses the existing NavigationSplitView, native sidebar list, toolbars, menus,
DisclosureGroup, LabeledContent and grouped Settings forms. System surfaces and semantic colors
remain in control; history adds no custom glass layer or decorated card surface. The existing
macOS 26+ bottom bar and native older-system fallback remain confined to the library.

## Apple design references

The audit used current official Apple guidance and local SDK availability checks. Standard
framework controls and navigation adopt the system material; custom backgrounds can interfere
with it, and display/accessibility variants still need testing.
[Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)

The dedicated history destination follows the sidebar's role of navigating between app areas.
Toolbar commands remain relevant to the visible content and avoid unnecessary clutter.
[Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars),
[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)

Context commands are also discoverable in the menu bar, and Find uses its familiar keyboard
shortcut. Related choices share their implementation across the toolbar and View menu.
[Menus](https://developer.apple.com/design/human-interface-guidelines/menus),
[Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus),
[Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)

The Settings pane is restored on reopening. Appearance and accessibility remain system choices;
the app does not add competing global appearance switches.
[Settings](https://developer.apple.com/design/human-interface-guidelines/settings),
[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

These are implementation decisions guided by Apple's documentation, not a claim of Apple
certification or complete Human Interface Guidelines conformance.

## Automated evidence

- **62 hosted app tests in 11 suites pass**, including six new history-loading test functions and
  three interaction/preference tests. Parameterized stale-result cases exercise both success and
  failure arriving after a newer result.
- History cases cover a real temporary SQLite store loading with no device or destination lease,
  unreadable database preservation and successful retry, last-good-result retention, coalesced
  initial reads, generation isolation and the 100-session bound.
- Interaction cases verify persisted size/sort/grouping/Settings choices, independent fallback
  from invalid preferences, correct context selection scope and disabled backup actions in History.
- The normal Debug rebuild, strict SwiftLint, whitespace check and actual signature/entitlement
  verification pass without compiler warnings. No new entitlement or dependency is introduced.
  Hosted-test signing additions were removed by the normal rebuild before manual verification.
- The core remains the Phase 7 baseline of **266 passing tests**; this refinement changes the app
  presentation and preferences, not the verified file or persistence contracts.
- Hosted log: `/tmp/cloakroll-phase8-app-tests.log`. Logs remain local verification artifacts.

## Actual native UI evidence

The normal app displayed saved history while no source library was exposed. It showed two
completed real sessions for the same **three logical items / four originals / 30,736,406 verified
bytes**. The expanded repeat session reported **zero transferred bytes**, preserving the distinction
between repeated verification and another copy. These are existing real sessions, not generated
history presented as hardware evidence.

Observed through native UI automation:

- History opens offline from the sidebar, expands session details and refreshes through the native
  command. Its rows remain unchanged after refresh and app relaunch.
- Find (⌘F) focuses the library search field. Typing filters the library; ⌘A in that field selects
  its text rather than activating grid selection.
- Changing thumbnail size through the native View controls is reflected in Settings. Large size
  and the Backup Settings pane survive quit/relaunch. Medium and General were restored afterward.
- The native Library menu in History disables media actions appropriately. Refresh Backup History
  works, and Stop Backup is disabled when idle.
- Compact **860-point light appearance** and expanded **1100-point light and dark appearance** were
  inspected. The history note initially clipped and expanded disclosure rows shortened separators;
  the final refinement gives the note a wrapping list row and aligns the native separators.
- History and Settings were inspected in dark appearance. Final compact light and standard expanded
  light/dark history layouts show the complete note, aligned separators and readable session details.

The UI audit did not save personal media, filenames, device identifiers, database exports or
personal-path screenshots in the repository. Appearance observations on the current macOS runtime
do not establish behavior on macOS 14 or every accessibility configuration.

## Remaining acceptance

- [ ] Full VoiceOver reading order, labels, disclosure interaction and keyboard-only task completion.
- [ ] System Reduce Transparency, Reduce Motion and Increase Contrast combinations; measured contrast
      and larger-text/long-localized-content checks.
- [ ] macOS 14 runtime verification in addition to deployment-target compilation.
- [ ] Final application icon and remaining onboarding, cloud-availability and external-volume polish.
- [ ] Remaining physical reconnect/new-capture, thumbnail-cache reuse, interruption and external-drive
      checks tracked in Phases 4, 6 and 7.
- [ ] Final Phase 8 acceptance after those product and accessibility checks are recorded.

No additional source-transfer, external-volume or physical interruption result is implied by the
offline history and preference checks above. Restore to a new iPhone remains backlog-only under
the no-extra-iPhone-app requirement.
