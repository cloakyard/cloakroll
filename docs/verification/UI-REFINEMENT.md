# UI refinement gate — 12 September 2026

The user requested validation and a focused UI audit, particularly the thumbnail-size slider,
before further feature development. Phase 2 physical acceptance was recorded and committed first.

## Changes

- Replaced the cramped 80-point toolbar slider with a native View Options popover. A continuous
  native slider has small/large image endpoints, an accessible name/value, and deliberate keyboard
  focus. The same control appears in Settings; no tick-mark rail or custom slider drawing is used.
- Kept sort/group pickers native. Opening options moves focus away from grid selection. Arrow keys
  adjust size in four-point increments within the supported range; Escape dismisses the popover.
- Shortened the sidebar's Recent Backups label, protected count widths, and allowed device status
  text to wrap. Removed the nonfunctional destination picker; sample mode identifies its destination
  as illustrative. Empty live screens no longer show an inactive backup bar or repeated tagline.
- Reduced emphasis on the disabled sample backup button. Separated the small video icon from its
  duration so duration and backup marks have their own space in small cells.
- Replaced preference-like keyboard-help rows with a Settings footer and corrected “Preview” to
  “Show Info.” Added Debug-only compact/standard window commands for repeatable layout inspection.
- Fixed a defect found during the audit: sorting/filter changes scrolled the first cell beneath a
  pinned date heading. The scroll reset now targets the actual content start above the grid.

## Actual manual evidence

Inspected the running native app on this Mac using the normal sandboxed Debug build, with
app-local light/dark appearance overrides (system appearance settings were not changed):

| Check | Observation |
| --- | --- |
| Default light library | 1,200 illustrated items; calm native toolbar, readable sidebar, clear date hierarchy. |
| Compact library | 860-point width; toolbar/search and 224-point sidebar fit. No cropped sidebar labels in the tested counts. |
| Long counts | Dark compact fixture with 100,000 items, including localized `1,00,000`, 25,000 new and 31,250 recent. Counts remain readable. |
| Slider | Both range endpoints inspected; AX reports 0–100 percent and named Smaller/Larger thumbnail buttons. |
| Keyboard focus | With a grid item selected, opening options focuses the slider. Right changed 132 → 136; Left restored 132; selection did not move. A further arrow at either endpoint stayed clamped. |
| Picker / dismissal | Native sort menu selected Oldest First with keyboard navigation; size remained 132. Escape dismissed the popover. |
| Tab behavior | With this Mac's existing keyboard-navigation setting, Tab remained on the slider. No system preference was changed; full keyboard-navigation mode was not separately verified. |
| Settings | General slider and help inspected in light/dark; keyboard adjustment observed in Settings. Backup and About inspected in dark. |
| Small videos / selection | Video indicator, duration, backup mark and selected state remain distinct. Info sheet opened with Space and displayed readable metadata. |
| Search empty / device empty | Compact dark states remain centered and readable. Device-empty fixture has no disabled backup bar. |
| Filter scroll fix | Changing to Videos now shows a complete square first cell below the date heading, with scroll offset zero. |

CloakDrop's split-navigation, system surfaces, grouped forms and design tokens were compared again
as read-only reference. A separate source review found no blocking regression. Native controls and
macOS 14-compatible APIs are preserved. This is a reviewed development UI, not a claim that final
product polish or the prototype icon is finished.

## Automated verification and limits

- All **56 core tests** and **4 hosted AppModel tests** pass.
- Strict SwiftLint and `git diff --check` pass.
- Debug app builds without compiler warnings/errors. Rebuilt normally after hosted tests to remove
  test-host signing additions before further device use.
- Hosted tests print macOS `linkd.autoShortcut` service diagnostics; the test suites pass. No compiler
  warning or application test failure was introduced by this stage.
- Full VoiceOver navigation, increased-contrast appearance and an actual macOS 14 runtime were not
  tested. Inspected AX labels/focus are not a substitute for those checks in the final polish phase.
- No original or thumbnail was requested from the iPhone during this UI pass. Sample backup states
  remain explicitly illustrative. Phase 3 real catalog and subsequent backup work remain to be built.

Gate: complete. Commit this stage before Phase 3 implementation.
