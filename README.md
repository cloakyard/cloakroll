# CloakRoll

**Your camera roll, safely on your Mac.** A native macOS photo and video backup app, part of Cloakyard.

CloakRoll is being built in verified phases. The current foundation is a native media browser
with clearly labeled sample media, chronological groups, filtering, selection, media info and
Settings. **It does not back up files yet.** Follow [the implementation plan](docs/PLAN.md) for
actual progress and verification evidence.

The intended workflow is a USB-connected iPhone → available originals → user-selected Mac or
external-drive folder → verified incremental backup. No account, analytics or cloud processing.
The app will not modify or delete iPhone media, convert originals, or represent DCIM folders as
Photos albums. A wired backup can only include originals exposed by the device; iCloud-only or
otherwise unavailable media may be omitted.

Requires macOS 14 or later; development uses Xcode 27, Swift 6, XcodeGen and SwiftLint.

```sh
cd apps/macos
GIT_CONFIG_COUNT=0 xcodegen generate
GIT_CONFIG_COUNT=0 xcodebuild -project CloakRoll.xcodeproj -scheme CloakRoll -destination 'platform=macOS,arch=arm64' -configuration Debug -derivedDataPath build/Verify build
open build/Verify/Build/Products/Debug/CloakRoll.app
```

See [development instructions](docs/DEVELOPMENT.md), [architecture](ARCHITECTURE.md),
[Apple API research](docs/APPLE_APIS.md), and [artwork sources](assets/README.md).
