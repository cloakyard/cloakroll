# First public beta — 29 October 2026

Published [v0.1.0 Beta (Build 20261029.2)](https://github.com/cloakyard/cloakroll/releases/tag/v0.1.0-beta.20261029.2)
at **14:06:43 Asia/Kolkata** as a GitHub prerelease, at the user's explicit request. The title,
notes structure, date-based build number, DMG name and checksum attachment follow the
[CloakDrop beta reference](https://github.com/cloakyard/cloakdrop/releases/tag/v1.0.0-beta.20260910).
The `.2` suffix preserves the existing same-day build sequence; `20261029` and `20261029.1`
were already used for local candidates. CloakRoll's numeric version remains `0.1.0`.

## Source and build

`dev`, `origin/dev` and `origin/main` all pointed to clean source
`8027c8f751df186d30560d6bb963ef7839c1df45` before packaging. Ran from `apps/macos`:

```sh
scripts/prepare_beta.sh --build 20261029.2
```

The pipeline preserved that clean source revision throughout every stage. The public release
tag points to this exact commit. Subsequent commits record publication evidence and update
documentation; they do not change the packaged app or installer.

Environment: Apple silicon, macOS **27.2 (26B123)**, **Xcode 27.1 (27A9275)**, macOS **27.0 SDK**.
The Release executable contains arm64 only; Info.plist and Mach-O require macOS **26.0**.
App version: **0.1.0 (20261029.2) · Beta**. No valid code-signing identity was available.

## Actual verification

- All **403 core tests** across the six test targets and **227 hosted app tests** passed
  (**630 Swift tests total**), plus **five release-tool regression tests**.
- Strict SwiftLint: **151 files, zero violations**. Fresh normal Debug and optimized arm64
  Release builds succeeded without compiler warnings or errors. Hosted tests emitted the
  existing `com.apple.linkd.autoShortcut` service diagnostics, with no test failures.
- The Release scale probe built and completed its generated **10,000-item / 12,500-resource**
  metadata smoke check. This is not physical transfer or sustained UI performance evidence.
- The actual Release bundle passed signature, exact reviewed sandbox entitlements, hardened
  runtime, architecture/minimum-OS, icons, app/GRDB privacy manifests and license checks.
- The UDZO read-only DMG passed filesystem verification and exact comparison of **19 bundle
  entries** against the Release app. Artwork, guide, volume icon, Finder layout and the
  `/Applications` link passed the packager's checks. macOS emitted hdiutil deprecation warnings;
  all disk-image operations and validation succeeded.
- Opened the final DMG through Finder. Visually checked its full Air composition, real app and
  Applications icons, guide, installation instructions and macOS 26+/Apple silicon requirement.
- Quit the idle installed app and launched `/Volumes/CloakRoll/CloakRoll.app`. The disconnected
  library appeared normally, and native About displayed **0.1.0 (20261029.2) · Beta**. Process
  inspection confirmed the mounted executable; its bundle audit passed again after launch.
- Quit the packaged app, ejected the installer and reopened the existing installed app. No
  replacement installation or physical backup was performed, and no private media was captured.
- `npm run verify`, `npm run check:worker` and root `node scripts/check-air-portability.mjs`
  passed. Astro checked 17 files with zero errors/warnings/hints and built three routes;
  Wrangler completed a dry-run. No website source or production deployment changed here.

## Artifact and GitHub verification

Artifact directory: `apps/macos/build/Beta-0.1.0-20261029.2/`. It retains the command logs,
pre-publication build manifest, app inventory, complete local checksums and publication files.
The manifest's `published: false` records the preparation stage; GitHub publication happened
afterward and is recorded here.

| Public asset | Bytes | SHA-256 |
| --- | ---: | --- |
| `CloakRoll-v0.1.0-beta.20261029.2.dmg` | 6,620,320 | `b2e3a7408bc66c954254161dba2116576c0b645aa303e1c8c3219026ecc89851` |
| `SHA256SUMS.txt` | 103 | `46d7158c23922bdcb50914ad2e4e8b41a127cdbe5d12c7fba65412612e0789f5` |

Created the release as a draft with both assets, then downloaded them and checked the downloaded
checksum file and byte-for-byte equality with the originals. Published only after those checks.
Read back GitHub release **427620297**: `draft: false`, `prerelease: true`, both assets
`uploaded`, and matching GitHub SHA-256 digests. Read back the tag target as the exact source
commit above. The public checksum file lists only its attached DMG; the local checksum file
also covers the retained build manifest and app inventory.

After publication, downloaded both assets again through their unauthenticated public URLs.
Both sizes and hashes matched, and the public checksum file verified the downloaded DMG.

Release documentation is committed on `dev` for a `dev` → `main` PR. Both long-lived branches
are retained; no feature commit or direct push is made to `main`.

## Acceptance limits

This is an **ad-hoc signed, unnotarized beta**. Developer ID signing, stapling, clean-Mac
Gatekeeper and minimum macOS 26 runtime acceptance remain open. So do the final hardware
interruption/reconnect/full-volume/sleep-wake/two-phone matrix, sustained physical-library
profiling, full VoiceOver spoken feedback and remaining accessibility variants. Earlier bounded
physical evidence is retained, but no new hardware acceptance was run for this release.
Live Photo playback/edited-effect variants and restore-to-iPhone boundaries remain as documented.
The public release notes disclose these limits; publication does not close any of those gates.
