# CloakRoll contributor guidance

Read `docs/PLAN.md` before working. Implement phases in order and record actual verification;
hardware acceptance cannot be replaced with a mock. CloakDrop is read-only reference material.

Keep only the long-lived `main` and `dev` branches. Continue feature work on `dev`, commit verified
stages there, and promote to `main` through a pull request after validation. Do not commit feature
work directly to `main` or delete `dev` after merging. `main` is the Cloudflare production source;
deployment remains the user's action unless explicitly requested. See `CONTRIBUTING.md`.

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

## Website design

Read `DESIGN.md` (also in `apps/site/DESIGN.md`) before visible website changes.
The full Air contract and pinned local bundle are synchronized from Cloakyard.
Run `npm run verify` and `npm run check:worker` in `apps/site`, and
`node scripts/check-air-portability.mjs` at the root. Keep responsive light/dark,
keyboard/touch and text-reflow evidence in `docs/air/`. These website checks do not
certify native or hardware acceptance. Preserve actual policy meaning and dates.
