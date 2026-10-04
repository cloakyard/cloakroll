# Media Info redesign — 4 October 2026

The sheet now places an uncropped, aspect-fit preview beside a scrolling details column.
Native GroupBox surfaces group aligned metadata and original-file rows; a separate status
line names the selected backup folder. Filenames wrap, remain selectable, and have complete
accessibility labels. The primary filename stays distinct from aggregate original-file size.
The existing native sheet, Done/default Return action and model-owned presentation remain;
Escape dismissal was added. Sample previews now respect the same fit/fill setting as real ones.

The design follows Apple's [sheet guidance](https://developer.apple.com/design/human-interface-guidelines/sheets)
and uses semantic system surfaces and native confirmation controls. It does not add glass
to the photo or simulate custom window chrome.

## Actual UI evidence on macOS 27.0.1

- Opened the user's selected physical-iPhone Live Photo and inspected its full portrait
  preview, two original files, combined size, dimensions and destination-scoped backup status.
- Refined row alignment after the first screenshot and inspected the resulting full-width
  metadata group and consistent label/value alignment in the next build.
- Dark appearance and an 860 × 560 parent window: video sample shows duration, dimensions,
  original size and an uncropped landscape illustration; Done remains reachable.
- Long-name fixture: a Unicode filename and 30 originals wrap within the details column.
  Scrolled to the final original; the preview and Done remain fixed and available.
- Missing-details fixture: Untitled, Unknown date, absent dimensions, zero original records
  and a thumbnail placeholder are represented without layout failure.
- AX inspection confirms complete metadata label/value strings, full original filenames and
  readable backup status. This is not a full VoiceOver user-session audit.
- Escape and Return each dismissed the sheet in actual native UI interaction.

Development → Media Info Examples provides the two synthetic edge cases for repeatable
visual review. These are Debug-only and enter the existing sample mode; they do not transfer
files or access a backup destination. Real-iPhone evidence above remains separate from these samples.

Debug build and strict lint pass. All 305 core tests pass. No new unit tests were added for
the layout-only stage. Local logs: `/tmp/cloakroll-media-info-build.log` and
`/tmp/cloakroll-media-info-core-tests.log`. No backups or iPhone originals changed.

## Next requested addition

The user requested camera EXIF including ISO and aperture while the redesign was being
validated. The UI milestone above precedes that implementation; its API, parser, request
lifecycle and physical-iPhone verification will be recorded separately below when complete.
