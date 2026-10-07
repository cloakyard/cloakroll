# Capture-date filtering and UX refinement

7 October 2026 · CloakRoll 0.1.0 (13) · macOS 27.0.1 (26A434), Apple silicon.

## Feature and behavior

The calendar button in the library toolbar opens native From/Through date fields.
Today, Last 7 Days, Last 30 Days and This Month populate a draft; Apply commits it,
Cancel/Escape discards it, and Clear Filter restores all capture dates. View also
exposes Filter by Capture Date and Clear Date Filter. The active calendar gains a
checkmark, an accessible date-range value and a tooltip; the existing idle backup
caption includes the selected range. No extra strip occupies the photo area.

The filter includes both calendar days, respects daylight-saving transitions and
excludes unknown capture dates until cleared. It composes with filename search and
category/status filters. Sidebar counts describe the complete source library;
selection, visible bytes and backup candidates describe the current results. Query
changes reset scrolling and discard selections that are no longer visible. A backup
already in progress retains its captured work list. Dates are temporary browsing state.

## Refinements

- Search now says **Search by filename**, matching what it searches.
- Empty results offer independent date/search reset actions. Empty backup collections
  explain whether no new, saved or recently saved items are available.
- An idle empty result hides the unused backup bar. A nonempty view with no new items
  uses **No new items in this view** and omits the disabled backup action. Active and
  terminal progress remain visible independently of the current results.
- Backup Details now explicitly handles Escape. The initial audit reproduced a
  lingering popover; the final build dismissed it without clearing library selection.
- Media Info says **Backup folder:** rather than implying an unbacked item is already
  in that folder. Its preview, metadata, original-file list and edge scroll view remain.
- Recovery uses Cancel/Rebuild History before starting and Start Again/Done after it
  settles. Done is the Return default. Escape cannot dismiss an active recovery, and
  Stop stays disabled while its final history transaction is saving.
- Saved-file checks use Return for Done and retain Escape cancellation. Recovery
  progress has a meaningful accessibility label/value, including indeterminate work.
- Help explains date filtering, selection reset, saved-file checks and rebuilding history.

## Design references

Reviewed Apple's [Materials](https://developer.apple.com/design/human-interface-guidelines/materials),
[Pickers](https://developer.apple.com/design/human-interface-guidelines/pickers),
[Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields),
and [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons).
The implementation uses system popovers, DatePicker, menus, sheets and semantic colors.
Liquid Glass remains on functional floating controls; metadata uses ordinary grouped
surfaces. Native controls supply focus, enabled states and platform appearance.
This is a design review, not an Apple certification or complete accessibility acceptance.

## Feature audit and actual evidence

| Area | Review performed in this pass | Result / scope |
| --- | --- | --- |
| Connection and sidebar | Build-12 and first build-13 install showed the real 2,078-item library; build-13 disconnected UI; source review of device picker and last completed backup | Last backup remained 7 Oct, 18 items / 4.98 GB, with the remembered folder. Build 13 has clear connection help; no new transfer acceptance claimed. |
| Destination and per-phone mapping | Source review of sidebar context action, mapping/readiness tests, native Backup settings | Finder stays a secondary action; folder structure remains native and settings retain the chosen folder. Multiple-phone physical switching is still pending. |
| Library and selection | Standard and compact sample windows; native category counts, selection and Shift-Command-A; source review of date-group/context/keyboard actions | Photo area, compact date capsules and toolbar remain intact. Selection resets and filtered backup scope are covered by hosted tests. |
| Capture-date filter | Native popover, Today/Apply, invalid start-after-end via native stepper, Escape, clear action, accessibility values | Invalid Apply disabled; cancelled draft did not alter active range; clearing restored results. Final empty state had no idle backup bar. |
| Search/sort/group/thumbnail size | Source and test review; toolbar/search and General settings inspected | Accurate filename prompt; native preset sizes, grouping and sort behavior retained. No slider introduced. |
| Media Info / EXIF / originals | Normal and next-item preview, long Unicode filename plus 30-original fixture, scrolling; metadata presentation tests | Readable wrapping, fixed full-fit preview, content scrolls independently, native Done and navigation work. EXIF parser/presentation regression suite passed; no fresh USB metadata read claimed. |
| Backup progress and retry | Copying fixture at compact size in light/dark; details popover and Escape retest; progress/retry/activity tests and source review | Aligned static heading, determinate bytes/count/percentage and small details surface retained. Actual transfer/interruption requires physical checks. |
| History | Real saved history displayed read-only in compact dark UI; expanded session; paging/filter/controller regression tests | Existing history readable with clear result and destination guidance. No history reconstruction or new backup was performed. |
| Recovery / integrity checks | Recovery idle sheet, both methods, disabled USB prerequisite state, Escape; lifecycle/checker tests and toolbar source review | Native action hierarchy; prerequisites clear; guards retained. Terminal recovery UI changes are source/build verified, not a newly executed physical recovery. |
| Settings / About | All three native Settings tabs inspected; final installed build launched | Folder organization, privacy guidance and version presentation retained. |
| Help / empty states | Final installed connection help with new sections; date-empty UI; device-state source and tests | Clear next actions, scrolling grouped content and concise reset controls. |
| Appearance / accessibility | Light/dark and 860-point compact / 1,100-point standard window checks, AX labels, Return/Escape checks | No observed overlap in reviewed layouts. Full VoiceOver, Reduce Transparency/Increase Contrast and macOS 14 runtime remain open. |
| Scrolling / performance | Existing pipeline/100k catalog regression suite; Info scrolling and normal library layouts | No new frame-time or sustained memory claim. Physical-library scrolling profiling remains a release gate. |
| Restore to iPhone | Plan reviewed | Still backlog: no supported no-extra-iPhone-app implementation established. |

## Software verification

- **393 core tests** passed, including three new date-filter tests (one parameterized
  across 23- and 25-hour days).
- **207 hosted app tests** passed, including date-query replacement, selection reconciliation,
  backup candidate scope, scroll reset, clear restoration and empty/active bar visibility.
- Normal Debug build and universal arm64/x86_64 Release build passed without compiler warnings.
- Strict SwiftLint and whitespace checks passed. Hosted tests emitted the previously known
  `linkd.autoShortcut` service diagnostics without test failures.
- Actual Release-bundle checks passed: signature, hardened runtime, reviewed entitlements,
  icon assets, privacy manifests, versions and architectures.
- ZIP integrity check passed. Archive:
  `apps/macos/build/releases/CloakRoll-0.1.0-13-local-universal-r2.zip`.
  SHA-256: `c477f019fb90e4000a5a1a5ee348b032458d5ad2fee582920ad865c2914a627b`.
- Installed a byte-identical Release at `/Applications/CloakRoll.app` after quitting the
  idle preview. Superseded installed/Debug/Release bundles went to recoverable Trash.
  Originals, saved history and preferences were retained. Installed Release launched
  with the new calendar control, accurate search prompt and updated Help.

Logs: `/tmp/cloakroll-date-core.log`, `/tmp/cloakroll-refine-tests.log`,
`/tmp/cloakroll-refine-debug.log`, `/tmp/cloakroll-refine-release.log`,
`/tmp/cloakroll-refine-lint.log`.

The [release gates](../RELEASE.md) remain open for cable interruption/reconnect,
external-volume and full-disk cases, two physical iPhones, sustained scrolling/RSS,
full accessibility/older-OS runtime and Developer ID/notarized distribution.

Final installed-state check: About reports 0.1.0 (13), the remembered destination and
One Folder setting remain, and View exposes the date-filter actions. After the final
bundle replacement the app showed No iPhone Connected, so applying the date range to
real media remains pending reconnection. The current-month draft and View → Clear Date
Filter were checked; the app is left in All Photos, All dates, with no selection/transfer.
