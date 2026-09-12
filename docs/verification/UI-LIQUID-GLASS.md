# Liquid Glass UI audit — 12 September 2026

The user requested another native UI audit, emphasizing the slider's appearance and pointer
interaction. This pass refines the existing development UI. Phase 3 physical library acceptance
remains pending; it does not advance the backup implementation or hardware gates.

## Implemented changes

- A standard SwiftUI `Slider` now sits in the toolbar with 200 points of available width. Settings
  uses the same slider. The system owns tracking, focus, keyboard editing and appearance; custom
  focus, arrow handling and accessibility-value replacement have been removed.
- Sort and group choices use a native `Menu` with `Picker` items. This replaces the options popover,
  which allowed arrow keys to reach the underlying grid when custom focus handling was removed.
- On macOS 26+, the bottom action area uses `safeAreaBar` with system scroll-edge treatment.
  macOS 14–15 retain the native material/inset fallback. The grid receives no decorative glass.
- Media Info uses a standard navigation title and confirmation toolbar with Done, preserving
  its scrollable metadata and existing sheet dimensions.
- AppAccent includes light/dark increased-contrast variants. The custom selection checkmark uses
  the semantic content background over the accent, avoiding white on pale purple in dark mode.
  Backup marks use white over a 65%-black backing; duration labels use the same dark opacity.

Standard controls and navigation receive the current OS design automatically. Custom backgrounds
can interfere with those effects; `safeAreaBar` is the supported integration for custom bars.
[Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
Glass is reserved primarily for controls and navigation, while content retains standard surfaces.
[Apple: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

## Observed interaction and appearance

Manual checks used the running native app on **macOS 27.0 (26A428), built with Xcode 27**.
Appearance overrides were app-local; system accessibility preferences were not changed.

| Check | Evidence |
| --- | --- |
| Final toolbar slider | Pointer drag changed 132 → approximately 183.32. Further drags reached the supported 84 and 200 endpoints. The first selected asset remained selected. |
| Final toolbar track click | A click in the final 200-point slider changed 132 → approximately 180.76 and resized the grid. |
| Settings slider | Pointer drag changed 143.6 → approximately 180.82; a track click changed it to approximately 110.08. |
| Native options menu | Down, Right and Escape navigated/dismissed the menu while preserving the selected grid item. |
| Media Info | Native title and bottom Done action inspected with an 860-point parent window. Return dismissed the sheet. |
| Appearance | Normal light compact UI inspected. AppKit light/dark increased-contrast previews inspected for grid and selected badges; all Settings tabs inspected in dark. |
| Toolbar width | 860- and 1,100-point windows retain the slider, View Options and Info. The native search control collapses to its icon at compact width and expands at standard width. |
| Scrolling and search | Scrolling beneath the bottom bar preserves readable status text. Search entry and the no-matches state remain usable at standard width. |

The completed build is left open with clearly labeled sample media and the system's normal
appearance so the updated controls can be tried immediately.

## Build evidence and limits

- **111 core tests and 12 hosted app tests pass.** The final normal build after hosted testing and
  badge refinements passes without compiler warnings/errors. Strict lint and diff checks pass.
  The signature verifies with normal sandbox, USB, Photos-library and Debug get-task-allow
  entitlements; no hosted-test file-access additions remain.
- A source review checked toolbar/menu composition, availability guards, native sheet structure
  and accent variants. It identified the selection-checkmark contrast issue corrected above.
- The macOS 14 fallback has compile-time coverage, not an actual macOS 14 runtime check.
- Full VoiceOver, full keyboard editing of the slider, actual system Increase Contrast, and Reduce
  Transparency preferences were not tested. AppKit high-contrast appearance previews do not
  establish the behavior of those preferences.
- Menu keyboard evidence is separate from slider keyboard access. Native macOS controls should
  follow the system's keyboard-access conventions; no custom grid-to-control focus workaround is
  retained. [Apple: Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/)

The earlier `UI-REFINEMENT.md` remains historical evidence for its own committed stage.

Gate: this UI refinement is complete. Phase 3 still requires its physical library acceptance.
