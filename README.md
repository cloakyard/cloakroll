# CloakRoll

**Your camera roll, safely on your Mac.** A native macOS photo and video backup app, part of Cloakyard.

CloakRoll is a development preview entering V1 closeout. The app browses a real USB-connected iPhone and
backs up selected or filtered originals into separate iPhone folders, checking file sizes and local
SHA-256 digests before reporting success. Bounded physical imports have covered photos, Live
Photos, RAW and video. Real incremental repeats, new-item detection, Stop and deferred Quit have
bounded evidence; final cable/external-drive interruption, reconnect and sustained performance
checks remain open. The app includes offline Backup History, remembered browsing choices,
native search/menu actions, clearly labeled sample media, chronological groups, filtering,
selection, camera metadata and Settings. Media Info has native Previous/Next controls and
⌘[ / ⌘] shortcuts for browsing the current results without changing the backup selection.
See [Info navigation verification](docs/verification/MEDIA-INFO-NAVIGATION.md).
Interrupted publication recovery and a per-original
available-space check preserve completed files when a later operation fails.
Active backups, explicit saved-file checks and history rebuilding keep the Mac awake
while allowing the display to sleep. Stop waits for work to settle before releasing
the activity. Keep a MacBook's lid open; explicit sleep can interrupt the connection.
See [backup activity verification](docs/verification/BACKUP-ACTIVITY.md).
Backup History → expand a session → **Check Saved Files…** checks its recorded originals
in the selected original backup folder, without needing the iPhone. The read-only check
has progress, Stop/retry and missing-or-changed-file results; it does not change history.
See [saved-file verification evidence](docs/verification/SAVED-BACKUP-CHECK.md).
Follow [the implementation plan](docs/PLAN.md) for actual progress and verification evidence.
The [release checklist](docs/RELEASE.md) consolidates the remaining gates, repeatable software
checks and local packaging. See the [privacy policy](docs/PRIVACY.md) for local data handling.
The [native UI refinement evidence](docs/verification/PHASE-8.md) covers history, menu parity,
remembered preferences and compact light/dark layout checks. Small, Medium and Large thumbnail
presets remain the only size controls. The connected iPhone shows its last completed
backup date, count and size; photos scroll beneath the native translucent toolbar
and compact Liquid Glass date labels.
See [sidebar and toolbar verification](docs/verification/SIDEBAR-AND-TOOLBAR.md).
Settings → Backup → Folder structure offers Year and Month (the default) or One Folder
for photos and videos within each iPhone folder. The choice applies to new files;
existing verified originals stay in place and remain eligible for incremental reuse.
See [organization verification](docs/verification/BACKUP-ORGANIZATION.md) for safety checks
and the pending physical check of the new flat layout.
Each iPhone remembers its own chosen backup folder. Reconnecting or relaunching restores
that folder and checks access; an unavailable folder offers **Choose Folder…**.
Switching folders and returning to the same original folder preserves its incremental
history identity. See [destination mapping verification](docs/verification/DEVICE-DESTINATIONS.md).
The [scale performance evidence](docs/verification/PHASE-9.md) records generated 10k/50k/100k
catalog measurements and improvements to identity preparation and history matching.

The intended workflow is a USB-connected iPhone → available originals → user-selected Mac or
external-drive folder → verified incremental backup. No account, analytics or cloud processing.
V1 will not modify or delete iPhone media, convert originals, or represent DCIM folders as
Photos albums. A wired backup can only include originals exposed by the device; iCloud-only or
otherwise unavailable media may be omitted.

Requires macOS 14 or later; development uses Xcode 27, Swift 6, XcodeGen and SwiftLint.
The current 0.1.0 (10) Release binary contains Apple silicon and Intel architectures.
It is locally ad-hoc signed; Developer ID, notarization and older-system runtime acceptance
remain release gates. Local software validation: 380 core tests and 192 hosted app tests.

**Recover after losing app data:** open **Backup History → Rebuild History…**, choose
an existing backup folder, and use saved recovery records. New backups store these
records beside the originals; surviving app history can prepare older backups automatically.
For a folder containing only media, choose **Verify older files with iPhone over USB**.
This reads potential matches once, verifies full size/SHA-256, and preserves saved files
in place. The next backup copies only missing originals, including missing Live Photo
companions. Keep hidden `.cloakroll-recovery` records when copying a backup folder.
See [folder recovery](docs/verification/FOLDER-RECOVERY.md) for evidence and limits.

**Feature backlog:** restore selected photos and videos from an existing backup folder to a new
iPhone. This remains outside V1 until a supported public approach works without installing an
extra iPhone app; no companion app is planned. Apple's manual Finder synchronization is an
external option with different behavior, not an implemented CloakRoll restore feature. See
[restore research and requirements](docs/RESTORE-TO-IPHONE.md).

```sh
cd apps/macos
GIT_CONFIG_COUNT=0 xcodegen generate
GIT_CONFIG_COUNT=0 xcodebuild -project CloakRoll.xcodeproj -scheme CloakRoll -destination 'platform=macOS,arch=arm64' -configuration Debug -derivedDataPath build/Verify build
open build/Verify/Build/Products/Debug/CloakRoll.app
```

See [development instructions](docs/DEVELOPMENT.md), [architecture](ARCHITECTURE.md),
[Apple API research](docs/APPLE_APIS.md), and [artwork sources](assets/README.md).
