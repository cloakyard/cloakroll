# CloakRoll contributor guidance

Read `docs/PLAN.md` before working. Implement phases in order and record actual verification;
hardware acceptance cannot be replaced with a mock. CloakDrop is read-only reference material.

The native app is under `apps/macos`. `project.yml` generates the ignored Xcode project.
The local `Packages/CloakRollCore` package is headless and uses Swift 6 Sendable values.
Keep SwiftUI, colors, symbols and presentation formatting in the app. Keep AppModel small.

From `apps/macos`:

```sh
GIT_CONFIG_COUNT=0 xcodegen generate
GIT_CONFIG_COUNT=0 xcodebuild -project CloakRoll.xcodeproj -scheme CloakRoll -destination 'platform=macOS,arch=arm64' -configuration Debug -derivedDataPath build/Verify build
swiftlint --strict
```

From `apps/macos/Packages/CloakRollCore`: `GIT_CONFIG_COUNT=0 swift test`.

Use native controls and semantic `AppAccent`, system surfaces and small components. No network
services, analytics, photo conversions, iPhone deletion or private APIs. Never mark an incomplete
transfer verified. Never match by filename alone or overwrite unrelated destination files.
Consult `docs/APPLE_APIS.md` before making ImageCaptureCore assumptions.
