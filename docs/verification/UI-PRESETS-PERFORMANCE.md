# Fixed thumbnail sizes and catalog responsiveness — 12 September 2026

The user reported that continuous sizing still felt choppy and explicitly requested fixed sizes,
removal of the sidebar tagline, pixel-level UI refinement and further physical-device work.

## UI changes and observed behavior

- Removed the slider completely, including its endpoint icons and dedicated toolbar item.
- Native View Options → Thumbnail size offers Small, Medium and Large. The same native picker
  appears in Settings. Medium is the launch default; the grid uses minimum widths 96/144/200.
  Sizing now changes once per choice instead of continuously invalidating layout during a drag.
- Removed the entire “Private by nature.” sidebar footer and its reserved space.
- Inspected all three choices with real iPhone thumbnails. Settings reflected the choice made in
  the menu; changes from Settings resized the grid. Medium was restored after checking Large.
- The 860-point and 1,100-point live windows have aligned toolbar controls, visible search, clear
  date headings and an uncluttered sidebar. No slider or orphaned endpoint icon remains.
- The normal rebuilt app again enumerated the physical iPhone and displayed real thumbnails.
  This session reported 1,893 logical items, including 12 additional non-still/non-video items;
  counts are session-exposed media, not a completeness claim about the entire phone.

## Catalog performance

Superseded catalog projections now throw CancellationError before and during scanning, sorting
and grouping. The app discards cancellation without replacing the visible library. Calendar
grouping reuses the current half-open interval, resolving a new interval only at a boundary.
Ascending/descending DST, month and year boundary tests retain the prior behavior.

An isolated optimized before/after harness measured five-run medians after warmup, excluding
fixture generation. Outputs matched; this measures metadata projection, not scrolling or USB time.

| Assets | Before | After |
| --- | ---: | ---: |
| 1,000 | 2.378 ms | 1.532 ms |
| 10,000 | 16.179 ms | 12.441 ms |
| 100,000 | 199.665 ms | 161.196 ms |

The 100,000-item run improved by about 19%. Two deterministic tests cover cancelled work and
superseded large requests without timing thresholds.

## Validation and next gate

- **113 core tests and 12 hosted app tests pass.**
- Final normal Debug build has no compiler warnings/errors; strict lint and diff checks pass.
- Signature verifies with normal sandbox/USB/Photos-library/Debug entitlements after rebuilding
  following hosted tests.
- Physical catalog/thumbnail acceptance is recorded separately in `PHASE-3.md` and has passed.
  Original files have not been downloaded. Phase 4 now addresses cache reuse, deduplication,
  visible-item priority, prefetch, cancellation and measured cache/USB bounds.
- This stage's manual UI checks used the current Mac's light appearance. Actual macOS 14 runtime,
  full VoiceOver and the complete accessibility-setting matrix remain release/polish checks.
