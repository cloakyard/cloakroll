# CloakRoll

**Your camera roll, safely on your Mac.** A native macOS photo and video backup app, part of Cloakyard.

CloakRoll is being built in verified phases. Physical iPhone discovery and the native UI quality
gate have passed. The current Phase 3 work adds real metadata and lazy thumbnails; its physical
library acceptance check is still pending. The app also includes clearly labeled sample media,
chronological groups, filtering, selection, media info and Settings. **It does not back up files yet.**
Follow [the implementation plan](docs/PLAN.md) for actual progress and verification evidence.

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
