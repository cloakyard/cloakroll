# CloakRoll

**Your camera roll, safely on your Mac.** A native macOS photo and video backup app, part of Cloakyard.

CloakRoll is being built in verified phases. The app browses a real USB-connected iPhone and
backs up selected or filtered originals into Year/Month folders, checking file sizes and local
SHA-256 digests before reporting success. Bounded physical imports have covered photos, Live
Photos, RAW and video. Persistent incremental history is implemented and tested; its physical
reconnect/new-photo acceptance check remains pending. Thumbnail reconnect and broader reliability
checks also remain open. The app includes offline Backup History, remembered browsing choices,
native search/menu actions, clearly labeled sample media, chronological groups, filtering,
selection, media info and Settings. Interrupted publication recovery is implemented and tested
with generated files; physical interruption checks remain pending.
Follow [the implementation plan](docs/PLAN.md) for actual progress and verification evidence.
The [native UI refinement evidence](docs/verification/PHASE-8.md) covers history, menu parity,
remembered preferences and compact light/dark layout checks. Small, Medium and Large thumbnail
presets remain the only size controls.
The [scale performance evidence](docs/verification/PHASE-9.md) records generated 10k/50k/100k
catalog measurements and improvements to identity preparation and history matching.

The intended workflow is a USB-connected iPhone → available originals → user-selected Mac or
external-drive folder → verified incremental backup. No account, analytics or cloud processing.
V1 will not modify or delete iPhone media, convert originals, or represent DCIM folders as
Photos albums. A wired backup can only include originals exposed by the device; iCloud-only or
otherwise unavailable media may be omitted.

Requires macOS 14 or later; development uses Xcode 27, Swift 6, XcodeGen and SwiftLint.

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
