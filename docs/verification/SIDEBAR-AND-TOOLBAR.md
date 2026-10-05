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

## Installed local preview

Installed the audited universal Release at `/Applications/CloakRoll.app`.
Native About shows **0.1.0 (6) · Development preview**. The destination and One Folder
preference remain intact; All Photos loads the real iPhone and its last-backup summary.
The previous installed app and temporary Debug/Release bundles were moved to Trash.
Backups and existing history were retained; only the additive index migration applies.

Archive: `apps/macos/build/releases/CloakRoll-0.1.0-6-local-universal.zip`.
SHA-256: `88e25867c1f846367f0c2f836422eb721d89c31ebc29d89fee9d0985d808cb4f`.

## Compact date labels — build 7

Removed the full-width opaque date/count strip. The native pinned section now has
an intrinsic-width capsule with a semibold date and secondary count. Only that
capsule receives regular Liquid Glass; the remaining row is transparent. The
macOS 14/15 fallback uses native regular material in the same shape. The API follows
[Apple's Liquid Glass guidance](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views).
No interactive glass effect is applied to this static heading. It combines the
date and count for accessibility and does not intercept clicks on photos beneath it.

Changing grouping can leave SwiftUI's previous pinned-header positions cached.
The grid now has the resolved grouping as its identity, resetting that layout only
when the section hierarchy changes, not on progress or scroll updates.

Actual checks on 5 October:

- **380 core / 166 hosted app tests** pass. Strict lint has zero violations in
  126 files. Final normal Debug and universal Release builds pass, including the
  final grouping-identity refinement. The actual **0.1.0 (7)** bundle and isolated
  ZIP pass architecture, signature, sandbox, hardened-runtime, icon, privacy-manifest
  and archive integrity checks.
- The connected physical iPhone exposed **2,073 items** after unlock. Scrolled from
  October into September in light and dark appearances: the capsule stays pinned,
  real photos remain visible across the rest of its row, and the toolbar retains
  its native translucent backdrop.
- Clicking through the pinned capsule selected its underlying photo; Escape cleared
  the selection. The accessibility tree exposes a combined date/count heading.
- Inspected day grouping in the compact window. After the layout refinement, switched
  Day → Year, scrolled with the year capsule pinned, then restored Automatic and
  resized to compact: the October capsule was immediately present. Restored standard
  window size and system appearance before quitting the preview.

Logs: `/tmp/cloakroll-date-glass-{core,tests,build,release,lint,package}.log`.
No new backup or media mutation was initiated. This does not establish older-OS,
full VoiceOver, accessibility-settings or sustained frame-time acceptance.
