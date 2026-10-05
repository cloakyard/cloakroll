# V1 closeout and release checks

Target: finish the current USB-original-backup scope, fix acceptance failures, and keep
restore-to-iPhone in the backlog. Additional feature expansion is not needed to finish V1.

## Remaining release gates

| Gate | Current position | Next acceptance |
| --- | --- | --- |
| Core V1 features | Implemented, including incremental history, separate iPhones, original companions, folder organization, measured progress and recovery | Fix failures found in the checks below |
| Physical reliability | Bounded import, repeat, Stop and deferred Quit have recorded evidence | Cable removal during a large transfer; reconnect/retry; external-volume removal, full disk and restoration |
| Incremental and thumbnails | Bounded real new-item/repeat and nearby-thumbnail evidence exists | Final same-device new capture/reconnect and preview reuse across reconnect |
| Scale and responsiveness | Generated 10k/50k/100k metadata/history measurements recorded | Sustained app RSS, frame/main-thread timing and rapid physical-library scrolling |
| Accessibility and OS support | Current-macOS light/dark, compact layout, native labels/actions inspected | Full VoiceOver/keyboard pass, system accessibility variants, macOS 14 runtime |
| Distribution | Local universal development preview | Developer ID signing, notarization, stapled ticket, clean-Mac launch and final release screenshots |

Hardware testing resumed on 5 October 2026. Physical flat-folder import, zero-byte
repeat, early Stop/retry and relaunch passed; see [the evidence](verification/HARDWARE-2026-10-05.md).
New-capture reconnect, cable removal during transfer and destination interruption remain open.
Software checks do not close those gates. The build remains labeled **Development preview**; 0.1.0
build 3 identifies this closeout preview, not a public release approval.

## Repeatable software validation

From `apps/macos/Packages/CloakRollCore`, run `GIT_CONFIG_COUNT=0 swift test`.
From `apps/macos`, run:

```sh
GIT_CONFIG_COUNT=0 xcodegen generate
swiftlint --strict
GIT_CONFIG_COUNT=0 xcodebuild -project CloakRoll.xcodeproj -scheme CloakRoll -destination 'platform=macOS,arch=arm64' -configuration Debug -derivedDataPath build/Verify test
GIT_CONFIG_COUNT=0 xcodebuild -project CloakRoll.xcodeproj -scheme CloakRoll -destination 'platform=macOS,arch=arm64' -configuration Debug -derivedDataPath build/Verify build
GIT_CONFIG_COUNT=0 xcodebuild -project CloakRoll.xcodeproj -scheme CloakRoll -destination 'platform=macOS,arch=arm64' -configuration Release -derivedDataPath build/VerifyRelease build
python3 scripts/check_release.py build/VerifyRelease/Build/Products/Release/CloakRoll.app
```

The normal Debug build after hosted tests removes test-host additions before manual
device use. The bundle checker is intended for Release: it requires the reviewed
entitlements exactly, rejects test bundles, validates the signature/hardened runtime,
and checks version, architecture, icons and both app/GRDB privacy manifests. Release
disables automatic base-entitlement injection so `get-task-allow` is absent; Debug
retains its development configuration. Neither the checker nor packaging changes a
signature or downloads credentials.

To create a **local preview** ZIP, use a new output path:

```sh
bash scripts/package_local.sh build/VerifyRelease/Build/Products/Release/CloakRoll.app build/releases/CloakRoll-0.1.0-3-local-universal.zip
```

Packaging validates an isolated copy, checks the ZIP, reports SHA-256 and refuses
to overwrite an existing artifact. The current Release executable contains both
arm64 and x86_64; this does not establish Intel or macOS 14 runtime acceptance.
Before distribution, re-run the app/hardware checks. After the actual Developer ID signing and Apple
notarization workflow has been completed, the stricter gate is:

```sh
python3 scripts/check_release.py /path/to/CloakRoll.app --require-distribution
```

It requires a Developer ID Application signature, a successful Gatekeeper assessment
and a valid stapled ticket. The local ad-hoc build intentionally fails this gate.
Do not bypass Gatekeeper or treat an ad-hoc signature as notarization.

## Privacy and sandbox review

See [the privacy policy](PRIVACY.md). The app has no network entitlements, analytics,
account system or remote processing. The actual signed bundle must contain only the
reviewed sandbox, USB, user-selected read/write, app-scoped bookmark and photo-library
entitlements. Existing photo access permission is retained until device testing can
validate any reduction; this pass does not expand access. No download path enables
conversion, source deletion, private PTP commands or device writes.

The manifest declares disk capacity for preventing insufficient-space writes (E174.1),
metadata for container and explicitly selected files (C617.1/3B52.1), and app-owned
preferences (CA92.1). There is no tracking or collected-data declaration. Source:
[Apple's required-reason API definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
The local core modules are linked into the app; GRDB's bundled manifest is also checked.

This is a source/bundle review and local software check, not App Store review or
third-party security certification. Release gates above remain explicit.

## 5 October local closeout evidence

- All **350 core tests** and **148 hosted app tests** pass. Normal Debug/Release builds
  have no compiler warnings; strict lint and whitespace checks pass. The app test host
  emits the existing `linkd.autoShortcut` service diagnostics without test failures.
- The new checker rejected the hosted-test app and exposed the Release build's injected
  `get-task-allow` entitlement. After the Release configuration correction, it accepts
  the actual five-entitlement Release bundle. The stricter distribution check rejects
  the ad-hoc signature as expected, before Gatekeeper/notarization assessment.
- Packaging the isolated verified bundle succeeds and its ZIP CRC check passes. A second
  invocation using the same output path is rejected without overwriting the archive.
- Installed the byte-identical verified Release at `/Applications/CloakRoll.app` and
  launched it. Native Settings preserves the destination and One Folder preference;
  About displays **0.1.0 (2) · Development preview**. The app is left in All Photos.
  Superseded app/build copies went to Trash; backups and saved history were not changed.
- No physical backup was active or started. Device testing is deferred by explicit user
  request. No new performance, accessibility, older-OS or physical acceptance is claimed.

Local artifact: `apps/macos/build/releases/CloakRoll-0.1.0-2-local-universal.zip`.
SHA-256: `457ae7d74bd95a66729c8733079b7153e8a9335346c44125f31b385ab9bed25a`.
Logs: `/tmp/cloakroll-wrapup-core.log`, `/tmp/cloakroll-wrapup-app-tests.log`,
`/tmp/cloakroll-wrapup-debug.log`, `/tmp/cloakroll-wrapup-release.log`,
`/tmp/cloakroll-wrapup-lint.log` and `/tmp/cloakroll-wrapup-package.log`.

## 5 October follow-up preview

Version **0.1.0 (3)** adds native history filters by saved iPhone and result. All **354 core**
and **150 hosted app** tests, Debug/Release builds, strict lint and the Release bundle audit
pass. [History-filter evidence](verification/HISTORY-FILTERS.md) records real history/UI checks;
[physical evidence](verification/HARDWARE-2026-10-05.md) records flat imports, zero-transfer
repeat, early cancellation/retry, relaunch and bounded warm-thumbnail reuse. Outstanding
physical interruptions, new-capture reconnect and distribution gates remain open.

Installed and launched the audited universal Release at `/Applications/CloakRoll.app`.
About shows **0.1.0 (3)**; the physical iPhone exposes 2,073 items and the new history
filter is present. The original destination was restored through the native folder
picker. Superseded installed/build apps were moved to Trash; backup originals and history
were retained. The separate validation copies remain in `Backup/CloakRoll Acceptance 2026-10-05`.

Latest local preview archive: `apps/macos/build/releases/CloakRoll-0.1.0-3-local-universal.zip`.
SHA-256: `bf0d93033f6bd6df4ebd813278e930fe9b02a82aa4e27f40299fa5ea29252d22`.
The packaged copy passed bundle validation and ZIP integrity checks; nothing was published.
