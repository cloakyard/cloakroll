# CloakRoll privacy

Updated 5 October 2026. Applies to the current macOS development preview.

CloakRoll works locally with an iPhone connected over USB and a backup folder you
choose. It has no accounts, advertising, analytics, telemetry or app-operated cloud
service. It does not upload your photos, videos or device information to Cloakyard.

## What the app reads and saves

- The connected device's exposed media catalog and thumbnails, including filenames,
  sizes, dates, dimensions, media relationships and device identity needed to keep
  different iPhones' backups separate.
- Camera metadata such as camera/lens, ISO, aperture and exposure settings when you
  open Media Info. The app does not extract or store GPS fields from that request.
- Original photo, video and companion files you ask to back up. They are copied to
  your chosen destination without conversion or deletion of the iPhone originals.
- Local backup history containing source metadata, device and destination references,
  relative paths, verification digests and session outcomes. This supports incremental
  backup, detecting missing/changed saved files and interruption recovery.
- Portable recovery records in `.cloakroll-recovery` inside the selected backup folder.
  These include source/device identity, original companion membership, relative paths,
  sizes and SHA-256. They let you rebuild history after losing app data. They contain
  metadata, not thumbnail or original-file copies.
- During optional verification of older media-only folders, a temporary original read
  from the iPhone is compared byte-for-byte by size/SHA-256 with the saved file. A verified
  temporary copy is removed after comparison; uncertain interrupted copies are preserved
  in isolated hidden staging rather than deleted by filename.
- App preferences, a security-scoped bookmark for your chosen folder, and bounded,
  disposable thumbnail caches inside the macOS app sandbox.
- Available space on the destination volume before downloading a new original. This
  is used only to avoid a transfer when macOS reports insufficient space.

Original files may themselves contain location and other embedded metadata. Keeping
originals means preserving those bytes; CloakRoll does not strip them. If you choose
a folder managed by a cloud-sync service or located on a network volume, that service
or macOS may move the files according to your separate configuration.

## Storage and control

Backups are ordinary files in the folder you choose and can be opened in Finder.
The local database is `Application Support/CloakRoll/Backups.sqlite` inside the app's
sandbox; cached thumbnails are in its Caches directory. The app retains history across
launches and device reconnections. Removing the app bundle alone does not erase your
backups, history or preferences. Removing the app's sandbox data discards local history
and preferences. Use Backup History → Rebuild History to verify the selected folder and
restore its evidence. Copy the entire backup folder, including its hidden recovery records,
when moving it to another drive. Older folders without those records can be checked once
against a connected iPhone over USB. Without successful recovery, later backups may copy
originals again rather than trust filenames.

Diagnostic logging covers operations, cache counts and error codes. Framework error
descriptions may be logged with macOS's private-data designation and may contain file
context; raw photos/videos are not logged. There is no automatic upload of logs or
crash reports by CloakRoll. macOS diagnostics are governed by your system
settings. No data is sent to third-party SDK services; GRDB is used for local SQLite
storage only.

The app's privacy manifest declares scoped file metadata, app-owned preferences and
disk-space checking, with no tracking or collected-data declarations. macOS sandbox,
USB and user-selected-folder permissions restrict access. A USB catalog can omit media
not exposed by the phone; a successful backup does not assert complete iCloud Photos
coverage.
