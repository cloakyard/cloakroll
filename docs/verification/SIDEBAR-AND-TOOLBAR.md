# Sidebar backup summary and seamless toolbar — 5 October 2026

The connected iPhone now includes a quiet two-line last-backup summary: completion
date, logical item count and verified size. Hover and accessibility text include
the completion time. The phone symbol aligns with the name and connection state;
the summary stays subordinate to those details, without another card or badge.

The summary reads the latest completed session for the exact device identity,
across destinations. It is independent of the Backup History screen's filter and
100-row limit. Failed, stopped, running, interrupted and recovered sessions do not
invent a successful original backup date. The summary describes that session,
not coverage of the current library or availability of files in the current folder.
Empty history and a failed read have distinct labels. Device changes and cancelled
or superseded reads cannot publish another phone's result. Finishing a backup or
refreshing history refreshes the summary. The additive v5 index supports this lookup.

Removed the steady “items available over USB” notice. Library scanning, history
checking, retryable errors and iCloud availability notices remain available.
The photo scroll view opts into native pane integration using
[`scrollContentBackground(.visible)`](https://developer.apple.com/documentation/swiftui/view/scrollcontentbackground(_:)).
Apple documents seamless window/titlebar integration on macOS 15 and later. The
system supplies the translucent toolbar and its scrolling treatment. No custom
toolbar blur, fixed titlebar height or ignored safe-area workaround was added.
The API is available at the existing macOS 14 deployment target; the older runtime
retains its native appearance and still needs its separate runtime acceptance.

## Actual verification

- **380 core tests** pass, including device identity with identical names, bound SQL
  parameters, a backup beyond 101 newer sessions, changing destination, completion
  ordering, unfinished/recovered/inconsistent records, and a populated v4 migration.
- **166 hosted app tests** pass. New checks cover independence from the history
  screen's filter, unavailable versus empty history, retry, cancelled reads and
  out-of-order device results/errors. Strengthened stale-result tests were rerun
  after the full suite. Strict lint and whitespace checks pass.
- Normal Debug and universal Release builds pass without compiler warnings. The
  actual 0.1.0 (6) Release bundle passes the signature, hardened-runtime, entitlement,
  architecture, icon and privacy-manifest audit. Local ZIP validation passes.
- Inspected the normal app with a physical connected iPhone and **2,073** exposed
  items. Its sidebar displayed the stored **5 October 2026, 5:41 PM** completed
  session: **3 items, 10.4 MB**. A read-only database query independently confirmed
  its completion time, item count and 10,350,931 verified bytes.
- Visually confirmed real photo content under the native translucent toolbar after
  scrolling, absence of the duplicate top count strip, readable month headers and
  edge-aligned native scrollbar. Inspected light and dark appearances and the compact
  window. Restored system appearance. The disconnected state was also observed during
  initial device discovery; the physical library subsequently became available.

No backup was started for this UI check. Two simultaneously connected phones,
full VoiceOver navigation, older-OS runtime, frame profiling, physical interruption
and distribution signing remain separate acceptance gates in `docs/RELEASE.md`.
