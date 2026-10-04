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

## 3 October — contextual help and destination checks

Optional help is available from the native Help menu and connection/empty-library states.
Getting Started explains connection, folder choice, originals and the current-view backup scope.
USB Availability explains that exposed items can differ from the iPhone Photos library, that
Optimize Storage can omit cloud originals, and that locked Hidden items are omitted on supported
macOS versions. Explicit Apple guidance links are available; the app adds no network service.
A completed selected backup does not claim complete iCloud coverage. Help and Media Info share
one presentation state so their sheets cannot compete. The grouped, scrollable native form
uses system surfaces and controls without a mandatory onboarding flow.

Media cells expose Show Info, Copy Filename and applicable backup actions to accessibility,
using the same action content as their context menus. Stop Backup uses Command-period.
Backup Settings can check the saved folder without an iPhone and retry an unavailable folder.
The sidebar reports the last check quietly; cached readiness never authorizes a transfer.
Each operation still resolves its bookmark, validates access and owns its security scope.
Generation checks discard stale readiness results; scopes are balanced on failure/cancellation.
No disk-space API, new entitlement or dependency is introduced. Physical external-drive
removal/read-only checks remain distinct from injected failure tests.

Design references: Apple's [Onboarding guidance](https://developer.apple.com/design/human-interface-guidelines/onboarding),
[Liquid Glass adoption](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass),
[keyboard conventions](https://developer.apple.com/design/human-interface-guidelines/keyboards),
and [VoiceOver action parity](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria).
USB copy follows [Apple's unavailable-photo guidance](https://support.apple.com/en-us/102302)
and [Image Capture documentation](https://support.apple.com/guide/image-capture/image-capture-imgcp1003/mac).

### Verification of this stage

- **76 hosted app tests pass**, including two help-presentation tests and destination readiness
  cases for absent selection, denied/read-only/unavailable folders, retry, stale completion,
  cancellation, exact security-scope balancing, and retry of blocked history without rescanning
  healthy history. Two stale-bookmark acquisition orderings and a failed stale completion are
  deterministic regressions. Review found and corrected bookmark-refresh interference; advisory
  checks now never persist refreshed bookmarks. Initial tests also caught cleanup on MainActor;
  the entire advisory acquire/validate/release operation now runs in its detached worker.
- **287 core tests pass**, including the separate preparation-cancellation stage. Final normal
  Debug build, strict SwiftLint, whitespace and signature checks pass with no compiler warnings.
  The final entitlement set matches the existing normal sandboxed Debug app, without test-host
  additions. No dependency, schema or source-transfer option changed in this UI stage.
- Normal app UI: connection help opens from the empty state; both Help-menu entry points work;
  topic switches keep one sheet; USB guidance scrolls to its final link/button; Escape and Return
  dismiss as intended. Light/dark help, the 860-point main window/sidebar and Backup Settings were
  inspected. The final Settings refinement puts folder actions on one native row so all content
  fits without scrolling at the existing window size. Real saved-folder checks succeed both
  automatically on Settings entry and through Check Folder while no iPhone is exposed.
- A generated 20-item library was used **only for accessibility presentation**: cells expose
  Copy Filename and Show Info as named actions, and invoking Show Info directly opens the correct
  media sheet. Sample backup remains unavailable. This does not replace a physical transfer or
  a complete VoiceOver audit. Live mode, System appearance, Medium size and General Settings were
  restored after inspection. No personal-media screenshot was saved in the repository.
- At the end of UI verification the app reported No iPhone Connected. A final unlock request was
  sent; no additional successful physical Stop/retry result is claimed. Hardware interruption,
  instrumented reconnect/cache reuse, physical external-drive failures, full VoiceOver/contrast
  combinations, macOS 14 runtime and final-icon acceptance remain open.

Local logs: `/tmp/cloakroll-help-readiness-app-tests-final.log`,
`/tmp/cloakroll-help-readiness-normal-build-final.log`. The app is left running its normal build.

## 3 October — interruption and retry refinement

Backup preparation errors now retain a terminal summary and the exact intended selection.
Explicit Stop and source-caused cancellation remain distinct: the latter retains verified
counts, presents Backup Interrupted, and finalizes persistent history as Incomplete. If a
source failure reaches the controller before a device-state event, its original error stays
Incomplete; the current connection state still supplies reconnect guidance. A fully completed
backup is not downgraded by a later disconnect.

Try Again is offered only when the session and complete selected asset metadata still match.
After reconnecting or a catalog change, Choose Items returns to the current library without
matching stale runtime IDs or filenames. Temporary connection/catalog/history states explain
the next step instead of displaying an unusable retry button. Active progress and terminal
summaries stay visible in Backup History, which offers Show Library when further action is needed.
The bar uses native buttons, system progress, an adaptive horizontal/vertical layout, and the
existing system bottom-bar treatment with macOS 14 fallback.

Interrupted Backups is available through the native Help menu and getting-started guidance.
It explains saved versus unfinished originals, reconnect/reselection, unavailable/full drives,
and waiting for Stop or Quit to settle. No companion app, source mutation, network service,
schema migration or new entitlement was introduced.

Validation: all 86 hosted app tests, 288 core tests, strict lint, a warning-free normal Debug
build, whitespace and signature checks pass. Independent review found and corrected temporary
lease retention by the acquisition queue; no additional transfer or completion-counting flaw
was found. Actual app checks covered the new Help menu entry, light/dark native sheet layout,
scrolling to the final section, return navigation to getting-started guidance, and Escape/Return
dismissal. The modified detail container still shows the seven real offline history sessions
with native source-list/navigation styling. Saved-folder checks pass automatically on entering
Backup Settings and on explicit Check Folder. System appearance, General Settings and the live
All Photos view were restored; Medium remains selected.

The final app has no exposed iPhone library, so active/terminal bar interaction and pixel-level
failure-state checks with physical transfers remain pending. Controller/persistence behavior is
covered by generated callback tests, not substituted for hardware acceptance. Full VoiceOver,
system contrast variants, macOS 14 runtime and final icon remain open. No personal screenshots
or media were added to the repository. Logs are listed in the Phase 7 refinement appendix.

## 4 October — floating Liquid Glass backup surface

On macOS 26 and later, the existing backup controls now sit on one native regular
Liquid Glass rounded rectangle, inset 12 points from the detail edges. Internal
horizontal padding keeps the text aligned with the media grid. The panel has no
custom blur, tint, painted highlight or whole-panel interaction effect. Native
buttons and measured progress retain their existing behavior. macOS 14–15 retain
the system bar-material fallback.

`safeAreaInset` reserves the panel's full height and margins. This replaces the
previous `safeAreaBar` scroll-edge extension, avoiding a second full-width blurred
band behind the glass. At the actual bottom scroll limit the final image row is
fully visible above the panel; content can pass behind it while scrolling.

The normal Debug app was inspected in standard light and compact light/dark sizes,
with both idle controls and illustrative active progress. Native text, percentage,
meter and Stop fit without clipping. Debug build, strict lint, whitespace and
signature checks passed. No new tests were added for this reversible surface-only
change. System reduced-transparency/high-contrast preferences and macOS 14 runtime
were not separately exercised; system glass owns those adaptations.

Public Xcode 27 SDK availability was checked. Design references:
[custom glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views),
[materials](https://developer.apple.com/design/human-interface-guidelines/materials),
[safe-area bars](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)),
and [adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
Radius and margins are local design choices, not prescribed Apple measurements.
Build log: `/tmp/cloakroll-glass-initial-build.log`.

## 4 October — direct Finder access from Destination

The sidebar now exposes **Open in Finder** below the selected backup folder and
above Change Folder. It uses a native borderless action and the existing bookmarked
destination access path. It remains available without an iPhone and during backup;
choosing another folder temporarily disables it. Sample mode and no-selection mode
do not show an action for a nonexistent destination. No navigation selection changes.

Verified in the normal Debug app: activating the new row opened the selected
**CloakRoll Verification** directory in Finder. Its title and folder contents were
inspected through the native UI. The 338 core tests, Debug build, strict lint,
whitespace and signature checks pass. This adds only a presentation entry point;
no new tests or storage behavior were introduced. Existing destination validation
still applies (including writable access). Log: `/tmp/cloakroll-finder-build.log`.

## 4 October — move Finder access into the destination context menu

Following the user's hierarchy refinement, Open in Finder is now a native
right-click action on the destination folder row. The sidebar shows the selected
folder, its status and Change Folder without an extra Finder action row. The entire
folder row is the context-menu target. The same action is also supplied through
SwiftUI accessibility actions; a separate VoiceOver pass was not performed.

Verified in the final normal Debug build: right-clicking the folder showed Open in
Finder, and choosing it opened CloakRoll Verification in Finder. All Photos remained
the selected navigation item. The uncluttered sidebar and native menu were visually
inspected in the standard window with System appearance, including while no camera
library was exposed. The existing bookmark/access implementation is unchanged.

The combined stage passes 338 core tests, 146 hosted app tests, Debug/Release builds,
strict lint, whitespace and both signature checks. No tests were added solely for
this reversible menu placement. Logs use `/tmp/cloakroll-presentation-*.log`, listed
in the Phase 4 display-readiness appendix. No backup or source mutation was started.
