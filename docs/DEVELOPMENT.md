# Development

## Toolchain and layout

The first build uses Xcode 27.0 and Swift 6.4 with Swift 6 language mode and macOS 14 deployment
target. Install XcodeGen and SwiftLint. `apps/macos/project.yml` is authoritative; regenerate the
ignored Xcode project after adding sources or changing configuration. No third-party dependency
is required by the foundation. CloakDrop is a read-only architectural/design reference.

## Verification commands

From `apps/macos`:

```sh
GIT_CONFIG_COUNT=0 xcodegen generate
GIT_CONFIG_COUNT=0 xcodebuild -project CloakRoll.xcodeproj -scheme CloakRoll -destination 'platform=macOS,arch=arm64' -configuration Debug -derivedDataPath build/Verify build
swiftlint --strict
GIT_CONFIG_COUNT=0 xcodebuild -project CloakRoll.xcodeproj -scheme CloakRoll -destination 'platform=macOS,arch=arm64' -configuration Debug -derivedDataPath build/Verify test
```

From `apps/macos/Packages/CloakRollCore`:

```sh
GIT_CONFIG_COUNT=0 swift test
```

`GIT_CONFIG_COUNT=0` prevents inherited Git configuration from breaking SwiftPM. Keep actual exit
codes when recording results. The app treats first-party warnings as errors. Core tests use Swift
Testing and deterministic protocol-friendly fixtures without launching the app; hosted tests launch
an app with physical discovery disabled.

## Sample UI

The app now starts in live device-discovery mode. Use `--sample` for 1,200 illustrated sample items. This is a development preview, and
sample backup status never represents transferred files. Use the Debug **Development** menu to
switch between 20/1,200/100,000 items, no-device/restricted/disconnected states and static progress.
The same menu includes Compact Window (860-point width) and Standard Window for repeatable UI checks.
Sample media is generated locally from editable illustration code; no personal photos are used.

Debug launch options:

```sh
open -n build/Verify/Build/Products/Debug/CloakRoll.app --args --sample --verify-light-appearance
open -n build/Verify/Build/Products/Debug/CloakRoll.app --args --sample --verify-dark-appearance
open -n build/Verify/Build/Products/Debug/CloakRoll.app --args --sample --verify-light-appearance --verify-increased-contrast
open -n build/Verify/Build/Products/Debug/CloakRoll.app --args --sample --verify-dark-appearance --verify-increased-contrast
open -n build/Verify/Build/Products/Debug/CloakRoll.app --args --empty
open -n build/Verify/Build/Products/Debug/CloakRoll.app --args --locked
open -n build/Verify/Build/Products/Debug/CloakRoll.app --args --sample-100k
```

Quit the app between appearance variants. These flags set an app-local AppKit appearance; they
do not change or fully simulate the system's accessibility preferences. Launch with `--sample`
alone to inspect the user's normal system appearance.

Check selection (click/⌘/⇧/⌘A), arrows, Space/⌘I info, search, sort, grouping, resizing,
sidebar focus, small-window layout, Settings, light and dark appearance. Keep screenshots and
timing evidence under `docs/verification`. Never commit personal media screenshots, filenames or device identifiers; record aggregate hardware evidence instead. SwiftUI previews cover empty, mixed, large,
restricted, disconnected and illustrative in-progress states.

View Options contains native Small/Medium/Large thumbnail-size choices alongside sort and group
menus. Settings uses the same size picker. Medium is the launch default. Check all three choices
at compact and standard widths; see `verification/UI-PRESETS-PERFORMANCE.md` for current evidence.

## Hardware gates and release limits

Phase 2 requires a physical iPhone: no-device, connect/trust, disconnect and reconnect. Later
phases additionally require original downloads, grouping checks and deliberate interruptions.
The checklist in `APPLE_APIS.md` records what mocks cannot prove. Never call a hardware gate
complete from compile-time probes or sample UI tests.

Local builds are sandboxed, hardened-runtime and ad-hoc signed. These checks do not establish
Developer ID signing, notarization, behavior on macOS 14 hardware, or release readiness. Do not
publish release claims until the corresponding Phase 10 checks are complete.

Hosted AppModel tests use the scheme’s `CLOAKROLL_TESTING=1` environment to prevent the host app from starting hardware discovery; injected mock browsers drive their events. Core package tests remain headless.

After `xcodebuild test`, run the normal `xcodebuild ... build` command before manual device checks. Xcode temporarily signs hosted-test apps with additional test-service/file permissions; the normal build removes those additions. Verify actual entitlements with `codesign -d --entitlements -` on the app bundle.

## Thumbnail diagnostics

The Debug Development menu's **Log Thumbnail Metrics** action writes aggregate cache hits, loads,
queue depth, costs and decode counts to the `Thumbnails` OSLog category. DeviceCapture also logs
actual outstanding framework requests and high-water counts at bounded intervals. These logs
contain no filenames, device identifiers or image data. Read deltas before/after scrolling, Info
and reconnect; a cache hit is not a measured frame-rate improvement or verified backup.

Cache limits are separate from process RSS. Record both; displayed images, SwiftUI rendering,
ImageCaptureCore allocations and temporary buffers are not included in encoded/decoded cache
costs. The cache is disposable and stays inside the app's sandboxed Caches directory. Reconnect
reuse requires a unique complete-catalog metadata match and persistent device identity; prior
runtime namespaces are purged on startup. Hosted tests disable default disk caching.
