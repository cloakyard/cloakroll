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

## Camera metadata and edge scrolling

Added a native Camera group with make/model, lens, ISO, F-number, shutter speed, focal length,
35 mm equivalent and exposure bias. Partial metadata shows only supplied fields; an empty
result gets a quiet explanation. Failures expose Try Again. Sample assets and video assets
do not request camera metadata. Opening Info during a backup defers optional camera reads.
Metadata is normalized from the public ImageCaptureCore callback before crossing actors;
no original download, image conversion, GPS extraction or metadata persistence is involved.

One physical metadata request and eight queued callers are allowed. Every caller has a
15-second deadline; cancellation, timeout and session retirement do not release a still-active
framework operation. Late callbacks cannot update a different asset or reconnected session.
The existing primary-resource identity selects the still component of a Live Photo.

Actual hardware checks on macOS 27.0.1:

- Opened the selected physical iPhone Live Photo. It supplied Apple iPhone 17 Pro Max,
  the back triple-camera lens, ISO 200, ƒ/1.78, 1/71 s, focal length and 24 mm equivalent,
  and 0 EV. Reopening the same item showed the same facts.
- Opened a physical PNG image with no camera EXIF. The sheet showed “Camera details aren’t
  available for this photo.” No made-up fallback values or error state appeared.
- Camera values and original-file names have complete accessibility labels and selectable text.
- The phone later reported restricted access after locking. The final scrollbar-only change
  was visually checked with native fixtures; EXIF hardware evidence is from the successful
  connected-phone reads above.

Following the user's scrollbar feedback, the ScrollView now extends to the sheet's right
boundary. Native `contentMargins(..., for: .scrollContent)` preserves 24-point content
spacing without moving the scroll indicator inward. Verified the visible indicator against
the outer edge while scrolling in light and dark appearances, using the 30-original fixture.
The preview and Done button stay fixed, and the final long filename remains reachable.
Missing-resource size now reads Unknown, and a single original's accessibility label is singular.

Validation: all **333 core tests** and **112 hosted app tests** pass, including 11 parser,
16 request-lifecycle, one explicit-permission, seven app-bridge and nine formatter tests added
for this feature. Debug and Release builds, strict lint and whitespace checks pass. The normal
Debug app was rebuilt after hosted tests. Logs:

- `/tmp/cloakroll-camera-core-tests.log`
- `/tmp/cloakroll-camera-app-tests.log`
- `/tmp/cloakroll-camera-build.log`
- `/tmp/cloakroll-camera-release.log`

Disconnect, timeout and ignored late success are covered by deterministic tests, not a claimed
physical cable-removal experiment in this milestone. Older macOS runtime and full VoiceOver
sessions remain unverified. No backups or iPhone originals changed.
