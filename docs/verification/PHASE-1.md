# Phase 1 verification — 12 September 2026

Environment: Apple silicon, Xcode 27.0 / Swift 6.4. App deployment target macOS 14.

- XcodeGen succeeded. Ad-hoc signed Debug app build succeeded with no warnings/errors.
- Strict SwiftLint passed.
- Core Swift Testing: 33 tests passed, including parameterized filters/date order, deterministic
  fixtures, unknown dates, DST date boundaries, companion preservation, selection range/toggle,
  and a 100,000-item metadata projection. Debug projection measured 0.369 seconds on this Mac;
  this does not constitute Phase 9 scrolling/memory/database profiling.
- A separate Swift 6 AppModel regression probe checked repeated Shift-range growth/contraction,
  active-item Info, first-arrow selection, query changes while loading 100k samples, and source-load
  supersession. All passed. This was an ad-hoc diagnostic probe, not a committed test target.
- Native app manually inspected through accessibility and window screenshots: light/dark sample
  library, native sidebar/toolbar, Settings, Info sheet, sample badges and disabled backup actions.
- A click → Right → Shift-Right → Shift-Right selected exactly three items. Command-A selected
  all 1,200. Space opened the active item's Info sheet. Command-A while editing search remained
  native text selection. Video filter + filename search returned the expected single item.
- Scrolling 12 pages moved into historical dates without a visible stall; accessibility showed
  only a small visible/prefetched slice, rather than all 1,200 cells.
- Dark no-device screen was checked after final layout. Its message fills the content region
  and backup bar stays at the bottom. An earlier intrinsic-size issue was fixed and rechecked.
- Accessibility now reports only selected media as selected; decorative backup checkmarks no
  longer incorrectly mark cells selected. Cell roles are buttons with explicit actions/labels.
- All 12 illustrated fixture assets and prototype icon sizes were decoded/dimension-checked.
  Reference and prototype icon visual review completed. See `assets/README.md` for regeneration.

Fixes discovered by manual review: grid first-responder routing, repeated range selection cursor,
source/projection cancellation races, false accessibility selection traits, empty-state sizing.

Limits: no backup code, persistence, actual thumbnail pipeline or device integration in this
phase. No VoiceOver listening session, macOS 14 runtime test, exhaustive reduced-transparency
test or formal scroll-frame profiling performed. The icon remains a prototype. Physical iPhone
was visible in the host USB inventory but was not opened by CloakRoll during Phase 1.
