# V1 closeout and release checks

Target: finish the current USB-original-backup scope, fix acceptance failures, and keep
restore-to-iPhone in the backlog. Additional feature expansion is not needed to finish V1.

## Remaining release gates

| Gate | Current position | Next acceptance |
| --- | --- | --- |
| Core V1 features | Implemented, including incremental history, separate iPhones, original companions, folder organization, measured progress and recovery | Fix failures found in the checks below |
| Backup power activity | Native idle-sleep protection, lifecycle tests, local OS probe and real build-9 transfer assertion/release pass | Long backgrounded transfer with display sleep; explicit sleep/wake interruption and release after Stop |
| Physical reliability | Bounded import, repeat, Stop and deferred Quit have recorded evidence | Cable removal during a large transfer; reconnect/retry; external-volume removal, full disk and restoration |
| Incremental and thumbnails | Bounded real new-item/repeat and nearby-thumbnail evidence exists | Final same-device new capture/reconnect and preview reuse across reconnect |
| Device destinations | Per-iPhone mappings, access checks and original-folder ID recall implemented; one connected phone's relaunch/missing-folder flow passed | Switch two physical phones with separate folders; external-volume removal/remount |
| Scale and responsiveness | Generated 10k/50k/100k metadata/history measurements recorded | Sustained app RSS, frame/main-thread timing and rapid physical-library scrolling |
| Accessibility and OS support | Current-macOS light/dark, compact layout, native labels/actions inspected | Full VoiceOver/keyboard pass, system accessibility variants, macOS 14 runtime |
| Distribution | Local universal development preview | Developer ID signing, notarization, stapled ticket, clean-Mac launch and final release screenshots |

Hardware testing resumed on 5 October 2026. Physical flat-folder import, zero-byte
repeat, early Stop/retry and relaunch passed; see [the evidence](verification/HARDWARE-2026-10-05.md).
New-capture reconnect, cable removal during transfer and destination interruption remain open.
Software checks do not close those gates. The build remains labeled **Development preview**; 0.1.0
build 12 identifies this closeout preview, not a public release approval. Per the user's
7 October request, remaining software work precedes the final hardware matrix.
Hardware testing subsequently resumed on 7 October: build 9 passed original imports,
zero-transfer Live Photo repeat, independent saved-file hashes and observed activity
release. The first intended cable-test batch completed before a disconnect; cable
interruption remains unaccepted. See [current evidence](verification/HARDWARE-2026-10-07.md).

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
bash scripts/package_local.sh build/VerifyRelease/Build/Products/Release/CloakRoll.app build/releases/CloakRoll-0.1.0-12-local-universal.zip
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

Build 3 archive: `apps/macos/build/releases/CloakRoll-0.1.0-3-local-universal.zip`.
SHA-256: `bf0d93033f6bd6df4ebd813278e930fe9b02a82aa4e27f40299fa5ea29252d22`.
The packaged copy passed bundle validation and ZIP integrity checks; nothing was published.


## 5 October saved-file-check preview

Version **0.1.0 (4)** adds read-only saved-original checks from Backup History. All
**363 core / 158 hosted app tests**, normal Debug/Release builds, strict lint and
whitespace checks pass. The actual universal Release bundle and isolated package
passed signature, entitlement, hardened-runtime, privacy-manifest and ZIP checks.
[Feature evidence](verification/SAVED-BACKUP-CHECK.md) records real saved-file hash,
missing-file/retry, cancellation, zero-record and native light/dark/keyboard checks.

Installed and launched `/Applications/CloakRoll.app`. About reports **0.1.0 (4)**;
Backup settings retain `iPhone 15 Pro Max` and **One Folder**. The connected iPhone
exposes 2,073 items. System appearance and the original destination were restored,
and the app was left in All Photos. Superseded app copies are recoverable in Trash.
An independent post-check SHA-256/size read of all six validation originals passed
(2,912,814,777 bytes); no temporary missing-file rename remains. No new transfer,
iPhone write, history result change or distribution claim was made.

Latest local preview: `apps/macos/build/releases/CloakRoll-0.1.0-4-local-universal.zip`.
SHA-256: `c3077ce5c8873c6297f84bae68bea56c6bcc64c7a484e857bf21b6d2116336ae`.
Release/package logs: `/tmp/cloakroll-saved-check-release.log` and
`/tmp/cloakroll-saved-check-package.log`. Remaining gates above stay open.

## 5 October folder-recovery update

Version **0.1.0 (5)** adds folder-owned recovery evidence, native Rebuild History and
optional one-time USB verification for media-only folders. All **376 core / 162 hosted
app tests**, strict lint, normal Debug/Release builds and the actual Release-bundle
check pass. There are no compiler warnings or new entitlements/dependencies. The native
light/dark sheet, idempotent repeat and unavailable-USB state were inspected; Escape
closes the settled sheet. Physical indexed and media-only recovery, plus a normal
zero-byte incremental repeat, are recorded in [folder recovery](verification/FOLDER-RECOVERY.md).

The universal local ZIP passed its isolated bundle audit and archive CRC check:
`apps/macos/build/releases/CloakRoll-0.1.0-5-local-universal.zip`, SHA-256
`c8d4fce708587b7bbe3ea4b84c65110b50691c731084f9931a1ac750aac9516d`.
Both running app versions were quit before replacement. The byte-identical verified
Release is installed at `/Applications/CloakRoll.app`; About reports **0.1.0 (5)**.
Settings preserves `iPhone 15 Pro Max` and **One Folder**. On final launch the connected
iPhone exposed 2,075 items with no history error, and the app was left in All Photos.
Superseded app/build bundles and the temporary 10.4 MB recovery-validation folder are
recoverable in Trash. The six pre-existing acceptance originals retain their exact
inodes, sizes and independent SHA-256 digests. User backup originals were not changed.
The separate physical interruption, performance, accessibility and distribution gates
remain open; this is a Development preview.


## 5 October sidebar and toolbar preview — build 6

- Added device-specific last completed backup date, count and size, independent of
  history filters and bounded lists. Removed the redundant USB-count strip and enabled
  native seamless photo scrolling beneath the toolbar.
- All **380 core and 166 hosted app tests** pass; the strengthened asynchronous
  device-summary regressions also pass separately. Strict lint, normal Debug and
  universal Release builds, and the actual Release-bundle audit pass.
- Real 2,073-item iPhone library inspected in light/dark and compact layouts. Scrolled
  photos visibly appear beneath the native translucent toolbar. The device summary
  agrees with its stored completed session. No backup was initiated for this UI task.
- Installed **0.1.0 (6)** at `/Applications/CloakRoll.app`; verified native About,
  retained destination/One Folder settings and connected library. Previous app/build
  copies are recoverable in Trash. Existing photos and backup records were retained.
- Local preview ZIP SHA-256:
  `88e25867c1f846367f0c2f836422eb721d89c31ebc29d89fee9d0985d808cb4f`.
  See [sidebar verification](verification/SIDEBAR-AND-TOOLBAR.md). Remaining release
  gates above are unchanged.

## 5 October compact date-label preview — build 7

The full-width opaque date header is now a compact Liquid Glass capsule with the
date and item count. Photos remain visible behind the pinned header; the capsule
does not intercept photo selection. Native material is the older-macOS fallback.
Changing date grouping recreates the grid's pinned-header layout.

All **380 core and 166 hosted app tests**, strict lint, final normal Debug/Release
builds and actual Release-bundle checks pass. Physical-library light/dark, compact,
scrolling, grouping and click-through checks are recorded in
[sidebar verification](verification/SIDEBAR-AND-TOOLBAR.md). Remaining gates stay open.

Local archive: `apps/macos/build/releases/CloakRoll-0.1.0-7-local-universal.zip`.
SHA-256: `7439b0e20c5c6ec00b9e24bdb42ac10e37b0195bada98a065ca0be24b4a8d4b1`.

Installed and launched **0.1.0 (7)** at `/Applications/CloakRoll.app`. Native About,
retained destination/One Folder settings, the connected 2,073-item library and
floating dates were verified. The installed bundle passes the audit. Previous
app/build copies are recoverable in Trash; backup originals and history remain intact.

## 5 October per-iPhone destination preview — build 8

Each iPhone remembers its chosen folder, checks access on reconnect, and offers native
folder selection when that destination is unavailable. Returning to the same original
folder preserves its incremental-history identity. Pending folder choices cannot be
assigned to a different phone after a device change.

All **380 core and 180 hosted app tests**, strict lint, normal Debug/universal Release
builds and actual Release-bundle/package checks pass. One connected physical phone's
folder selection, relaunch, missing-folder recovery and original-ID recall passed.
Two-device incremental reuse and missing-companion behavior have automated real-file
coverage; switching two physical phones and external-volume interruption remain open.
See [device destination evidence](verification/DEVICE-DESTINATIONS.md).

Installed and launched the audited **0.1.0 (8)** Release at `/Applications/CloakRoll.app`.
The real 2,073-item library and original destination returned automatically with access
checked. Native About, per-phone Settings caption and retained One Folder organization
were verified. Superseded app/build bundles are recoverable in Trash. No physical
transfer or source-media change was initiated, and no remaining release gate is closed.

Local archive: `apps/macos/build/releases/CloakRoll-0.1.0-8-local-universal.zip`.
SHA-256: `c6fb1161ec6bfdbc9087357ee592601f35f175c9dacafc1f30a6c990d8d22eff`.


## 7 October backup activity preview — build 9

Backups, explicit saved-file checks and history rebuilding now hold a native activity
through file work and cleanup. Idle system sleep is prevented while the display can
sleep; Stop and deferred Quit retain the activity until outstanding callbacks settle.
Details and Help explain the behavior without expanding the compact progress bar.

All **380 core and 186 hosted app tests**, strict lint, warning-free normal Debug and
universal Release builds, Release/installed-bundle audits and ZIP validation pass.
A separate process running the production helper demonstrated the expected OS assertion
and release. This is not prolonged physical backup or sleep/wake acceptance; see
[backup activity evidence](verification/BACKUP-ACTIVITY.md).

Installed **0.1.0 (9)** at `/Applications/CloakRoll.app`; native About, Help scrolling and
retained destination/One Folder settings were checked. Superseded app copies are in
Trash. Originals and history were retained. Hardware validation is deferred to the end
by user request, and no distribution or full-phase acceptance is claimed.

Local archive: `apps/macos/build/releases/CloakRoll-0.1.0-9-local-universal.zip`.
SHA-256: `abf27eca450548e796d28acfe3680afae15977fc5565ecc84b6146a35c3f0f93`.

## 7 October Media Info navigation preview — build 10

Media Info now browses adjacent items with native grouped buttons and ⌘[ / ⌘] shortcuts,
following the current results and preserving the backup selection. Per-item content resets
inside a stable sheet; invalidated/stale actions and unavailable devices cannot navigate.

All **380 core and 192 hosted app tests**, strict lint, warning-free normal Debug and
universal Release builds, Release/installed-bundle audits and ZIP validation pass.
Native sample checks covered light/dark appearance, filtered boundaries, a single search
result, keyboard dismissal and selection preservation. Installed Release browsing on the
2,078-item physical library checked previews, camera metadata, missing EXIF and scroll reset.
See [Info navigation evidence](verification/MEDIA-INFO-NAVIGATION.md).

Installed **0.1.0 (10)** at `/Applications/CloakRoll.app`; About and General Settings show
the version and new shortcuts. Restored the regular phone destination, which passed access
checking on reconnect, and cleared temporary selections. The superseded installed app and
Debug/Release build copies are recoverable in Trash. Backups, history and preferences remain.
No transfer was initiated during this feature validation; outstanding hardware gates remain.

Local archive: `apps/macos/build/releases/CloakRoll-0.1.0-10-local-universal.zip`.
SHA-256: `042beb47239614a609205bee90ed9a181a905dc234ba6de796411a4837271087`.

## 7 October date group selection preview — build 11

Date-label context commands now select/deselect the current group's displayed items while
preserving other groups. Library menu parity and assistive actions use the same guarded
operations. Pinned labels keep the existing compact glass appearance and allow clicks on
adjacent photos. General Settings includes the new interaction hint.

All **384 core and 199 hosted app tests**, strict lint, warning-free normal Debug and
universal Release builds, bundle audits and ZIP validation pass. Native light/compact-dark
checks and the installed physical-library 19 → 204 → 185 → 0 selection sequence passed.
See [date group selection evidence](verification/DATE-GROUP-SELECTION.md).

Installed **0.1.0 (11)** at `/Applications/CloakRoll.app`, verified About and Settings, and
left All Photos at the top with no selection and the regular destination available. Older
app bundles are recoverable in Trash. No backup was started or source original modified.
Hardware interruption, distribution and other remaining acceptance gates stay open.

Local archive: `apps/macos/build/releases/CloakRoll-0.1.0-11-local-universal.zip`.
SHA-256: `c9d99e835afcdd04994717ed0ea4ec37f3af611e38e494d9c1e8378fc7c23969`.

## 7 October full history browsing preview — build 12

Backup History now pages beyond its latest 100 sessions with native Newer/Older controls,
filter preservation, stable date/ID boundaries, bounded row loading and retry of the failed
page. Migration v6 adds ordered global/device indexes and preserves original-file evidence.

All **390 core and 205 hosted app tests**, strict lint, warning-free normal Debug/universal
Release builds, actual bundle audits and ZIP validation pass. Native 205-session paging,
filter/scroll reset, light/dark and compact real-history checks passed. Before/after row
digests confirm the existing 32 sessions and 18,229 verified records, plus related evidence,
were unchanged. See [history paging evidence](verification/HISTORY-PAGING.md).

Installed and launched **0.1.0 (12)** at `/Applications/CloakRoll.app`. About, offline
history loading, the returned 2,078-item physical library, sidebar last-backup details
and remembered destination access were checked. All Photos is left at the top with no
selection; superseded app bundles are recoverable in Trash. No backup was started.
Outstanding hardware, accessibility/performance, older-OS and distribution gates remain.

Local archive: `apps/macos/build/releases/CloakRoll-0.1.0-12-local-universal.zip`.
SHA-256: `a11b16f361ef2b6b8542ca590023bb185324901122ff7088ddb801191eab45f3`.
