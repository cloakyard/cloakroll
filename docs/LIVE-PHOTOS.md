# Live Photos in CloakRoll

A Live Photo contains a still image and a paired motion video. CloakRoll backs up both original
files, including any explicitly associated adjustment files exposed over USB. It does not flatten
the Live Photo into a still, transcode the motion file or rewrite embedded metadata.

## Browsing and backup

- The Live Photos filter shows pairs recognized through device-supplied relationships. Matching
  filenames alone never join unrelated photos and videos.
- Media Info labels the Photo and Motion originals and shows their combined size. When available,
  it also shows the motion duration. The preview displays the still image; animated playback
  inside CloakRoll is not implemented.
- Newly backed-up components use the same folder for that iPhone in either Year/Month or One
  Folder organization. Name collisions never overwrite existing originals; a safe suffix can
  differ between components. Original file contents and the saved relationship evidence remain
  unchanged.
- An item is complete only after every discovered component is verified. If the motion file
  fails or disappears, the item remains incomplete. Retry rechecks already saved components and
  copies the missing one. Folder recovery also treats a missing or altered companion as incomplete.

Keep the still and motion files together when moving a backup. The `.cloakroll-recovery` records
are also part of the backup's history-recovery evidence; do not remove hidden recovery data when
copying the folder. Use a Live Photo-capable viewer/import workflow to play the preserved pair.

## Scope and validation

CloakRoll can preserve only the originals and relationships the iPhone exposes over USB.
Ambiguous associations remain separate; edits, effects, cloud-only originals and locked Hidden
albums may expose different or incomplete representations. It does not recreate the complete
Photos library, guarantee every Photos edit is reversible, or restore a library to a new iPhone.

The [29 October audit](verification/LIVE-PHOTOS-AND-BRANCHES-2026-10-29.md) separates software
coverage from physical acceptance. Normal Live Photo imports/repeats were previously observed;
edited/effect variants, interrupted transfers and playback in an independent viewer still need
physical validation. The new tests use opaque bytes, not playable photo/video fixtures.

Apple documents the two-resource representation in
[Capturing and saving Live Photos](https://developer.apple.com/documentation/avfoundation/capturing-and-saving-live-photos)
and [paired video resources](https://developer.apple.com/documentation/photos/phassetresourcetype/pairedvideo).
