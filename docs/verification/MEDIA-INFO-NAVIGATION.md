# Media Info navigation — 7 October 2026

Build **0.1.0 (10)** adds Previous/Next browsing inside Media Info. Native grouped buttons
and a secondary position label sit beside Done in the standard sheet action area. ⌘[ and
⌘] provide keyboard access; Settings → General describes the shortcuts. This follows
Apple's [macOS interaction guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/),
[keyboard guidance](https://developer.apple.com/design/human-interface-guidelines/keyboards)
and [toolbar guidance](https://developer.apple.com/design/human-interface-guidelines/toolbars).

## Behavior and safety

- Browse only the current filtered, searched and sorted results; do not wrap at either end.
- Keep the grid's selected batch, active item and range anchor unchanged, including when
  Info was opened through a context action outside the selected batch.
- Retain one sheet identity while reading the currently inspected item from the model.
  Reset preview, camera-request state and details scroll position for a new asset or session.
- Resolve each activation against the current projection and asset identity. Ignore callbacks
  from an older displayed item, changed/removed assets, dismissed/other presentations,
  pending projection/catalog preparation, a disconnected/restricted device or another phone.
- Keep the existing cancellable thumbnail/EXIF pipelines and bounded request queues.
  This feature performs no original downloads, backup writes, conversions or iPhone writes.

## Automated verification

All **380 core tests** and **192 hosted app tests** passed. The six new navigation tests cover
endpoints, stable presentation identity, selected-batch/range preservation, filter/search/sort
ordering, pending projections, stale actions, other presentations, missing/changed assets
and unavailable/foreign device contexts. Existing preview/metadata cancellation and stale-result
tests also passed. No mocked result is counted as hardware acceptance.

XcodeGen, strict SwiftLint (132 files, zero violations), normal Debug build after hosted tests,
universal arm64/x86_64 Release build, whitespace check and Release/installed-bundle audits pass.
Both normal build logs contain no compiler warnings or errors. The archive passed integrity
validation. Local logs are `/tmp/cloakroll-info-nav-{tests,core,lint,debug,release}.log`.

## Native UI verification on macOS 27.0.1

Debug sample library:

- Next updated item 1 to 2 without closing the sheet. Rapid ⌘] / ⌘[ steps reached the
  expected Live Photo with matching filename, illustration, size and two original rows.
- Escape returned to the original selected item. Return also dismissed the sheet.
- Videos filtered to three items; the third showed “3 of 3” and disabled Next.
- An exact filename search showed “1 of 1” with both arrows disabled.
- Inspected light and dark native sheet screenshots: preview, action group, count and Done
  remained aligned and readable. The app-only appearance override was returned to System.

Installed Release with the physical iPhone:

- About displayed **0.1.0 (10)** and General displayed the new keyboard instructions.
- The 2,078-item library reconnected after relaunch. The regular phone destination returned
  with “Access checked”; last-backup details remained available.
- Opened the first Live Photo: Previous disabled, position “1 of 2,078”, real preview and
  camera EXIF. Scrolled details to the bottom, then Next: filename and preview changed,
  position became “2 of 2,078”, and the details scrollbar returned to zero.
- Four rapid forward shortcuts reached a PNG with no camera details; the prior EXIF fields
  disappeared. Going back showed a different Live Photo's ISO 160 and ƒ/1.78 instead of
  the earlier ISO 320 and ƒ/2.2. The displayed item, dimensions and companion count agreed.
- Done left only the original first photo selected despite browsing to the fifth. Cleared
  this test selection and left All Photos visible with the regular destination restored.

This stage did not start a backup or run cable-removal, external-drive, explicit sleep/wake,
multi-phone switching, full VoiceOver or older-macOS checks. Those gates remain open.

## Installed artifact

The audited Release was copied byte-for-byte to `/Applications/CloakRoll.app`. Superseded
app bundles are recoverable in Trash; originals, history and preferences were preserved.
Local preview archive: `apps/macos/build/releases/CloakRoll-0.1.0-10-local-universal.zip`.
SHA-256: `042beb47239614a609205bee90ed9a181a905dc234ba6de796411a4837271087`.
Local ad-hoc signing is not Developer ID/notarization or public-release acceptance.
