# About support link and dependency audit — 30 October 2026

The user requested CloakDrop's About support link, current libraries and another public beta.
Added **Buy me a coffee** below Report a Bug with the same `cup.and.saucer` symbol and native
link-row treatment. Its destination is `https://ko-fi.com/sumitsahoo21`; it opens only after
activation in the default browser. No app network service, entitlement or backup behavior changed.
CloakDrop was read-only reference material.

## Dependency audit

Checked the official GitHub release metadata, npm registry and PyPI on 30 October 2026.

| Component | Result |
| --- | --- |
| GRDB | **7.11.1** remains the latest stable release; both Swift package pins and the bundled license remain current. |
| Astro | Updated **7.4.3 → 7.4.4**. Raised the Node 22 minimum to 22.23.4 to match its declared engine requirement; the pinned Node 24.22.1 remains supported. |
| Wrangler | Updated **4.154.0 → 4.156.0**, with upstream Miniflare **5.20261023.3-beta** and unchanged workerd **1.20261023.1**. These are Wrangler's own pinned dependencies. |
| Astro sitemap/check | **3.7.4 / 0.9.12**, both latest stable. |
| TypeScript | **6.0.3**, latest supported release. TypeScript 7.0.2 exists, but Astro Check 0.9.12 explicitly supports only `^5.0.0 || ^6.0.0`; no incompatible major override was introduced. |
| Undici | Removed the redundant override: updated Miniflare itself pins **7.30.1**, the latest 7.x. Its dependency was not forced onto the unrelated 8.x major. |
| DMG libraries | **dmgbuild 1.6.7, ds_store 1.3.3, mac_alias 2.2.3** are all latest stable; PyPI wheel hashes match the committed requirements. `pip check` passes. |

Refreshed compatible npm transitive dependencies, including Rolldown **1.2.16**, Babel parser
**7.29.12**, OXC types **0.156.0**, ESTree types **1.0.10**, ansi-regex **6.5.0** and
hast-util-to-html **9.0.6**. A clean `npm ci`, full `npm ls --all` and `npm audit` pass with
**zero vulnerabilities**. `npm outdated` reports only the intentionally incompatible TypeScript 7.
Build-tool installers (Node/npm/pip) are not shipped app libraries; the existing pinned Node/npm
build environment is retained. Apple frameworks remain supplied by the OS/SDK.

Primary references: [GRDB](https://github.com/groue/GRDB.swift/releases/tag/v7.11.1),
[Astro](https://github.com/withastro/astro/releases/tag/astro%407.4.4),
[Wrangler](https://github.com/cloudflare/workers-sdk/releases/tag/wrangler%404.156.0),
[Astro Check registry metadata](https://registry.npmjs.org/@astrojs%2fcheck/0.9.12),
[dmgbuild](https://pypi.org/project/dmgbuild/), [ds_store](https://pypi.org/project/ds-store/),
[mac_alias](https://pypi.org/project/mac-alias/).

## Initial verification

- Normal arm64 Debug build and strict SwiftLint passed (151 files, zero violations).
- Native About layout was visually inspected; the new row, icon and existing license control
  fit the window. The accessibility link exposes the exact requested URL. Clicking it opened
  `https://ko-fi.com/sumitsahoo21` in the default browser.
- `npm run verify` passed Astro checks, the three-route production build and site validation.
  `npm run check:worker` passed the Wrangler dry-run. Root Air portability checks passed.
- Local logs and dependency-tree/audit output are retained under
  `apps/macos/build/Support-Beta-20261030/` and the same prefix beside that directory.

## Beta 20261030 verification

Ran `scripts/prepare_beta.sh --build 20261030` from clean source
`843ba9d9c3b5030a3981a10fcf6816a4e6109326`, preserved throughout the pipeline. The resulting
Release app is **0.1.0 (20261030) · Beta**, arm64 only, with a macOS 26.0 minimum in both the
bundle and Mach-O. Toolchain: **Xcode 27.1 (27A9275), macOS 27.0 SDK**; host **macOS 27.2 (26B123)**.

- All **403 core + 227 hosted app tests (630 Swift tests)** and **five release-tool tests** passed.
- Strict lint passed across 151 files. Fresh normal Debug and optimized arm64 Release builds
  passed without compiler warnings or errors. Existing hosted-test system service diagnostics
  did not fail tests; disk-image tooling emitted deprecation warnings while succeeding.
- The Release scale probe built and completed its generated **10,000-item** metadata smoke test.
  This is not USB throughput or sustained UI performance evidence.
- Bundle checks passed for signature, exact reviewed sandbox entitlements, hardened runtime,
  architecture, minimum OS, icons, app/GRDB privacy manifests and bundled license notices.
- The compressed read-only DMG passed filesystem and layout checks. All **19 bundle entries**
  match the verified Release; artwork, guide, volume icon and Applications link also pass.
- Opened the final DMG in Finder and visually checked its Air layout. Launched the mounted
  app, verified the disconnected library and About **0.1.0 (20261030) · Beta**, and inspected
  the coffee row with its exact Ko-fi destination. The mounted bundle audit passed again.
- Quit the packaged app, ejected the installer and reopened the previously installed app.
  No replacement installation, source-media operation or physical backup was performed.
- Sharp's native image roundtrip and Miniflare/workerd fetch smoke passed. The smoke uses
  Miniflare 5's `workers/config/manifest` API; an initial legacy-constructor attempt was rejected
  by option validation before runtime startup. No product-code change was needed.
- GitHub Website and external Cloudflare build checks passed on the exact source commit.
  The production `main` branch was not changed or directly deployed during this work.

Logs, the pre-publication build manifest, app inventory and local checksums are retained in
`apps/macos/build/Beta-0.1.0-20261030/`. The manifest's `published: false` describes preparation;
publication occurred afterward and is recorded below.

## GitHub publication

Published [v0.1.0 Beta (Build 20261030)](https://github.com/cloakyard/cloakroll/releases/tag/v0.1.0-beta.20261030)
at **13:30:54 Asia/Kolkata on 30 October 2026**. GitHub release **428774879** is
`draft: false`, `prerelease: true`; its tag points to the exact source commit above.

| Public asset | Bytes | SHA-256 |
| --- | ---: | --- |
| `CloakRoll-v0.1.0-beta.20261030.dmg` | 6,620,001 | `8b842d05dabe24f3a1e9119022d78eabb03b811737742653aea5a5c93b0d537c` |
| `SHA256SUMS.txt` | 101 | `2124f96595a86cccdb4afb996be91cfd2f975eab200a515fdcfe74a63c93a840` |

Uploaded both assets to a draft, downloaded them and checked the checksum and byte-for-byte
equality before publishing. Read back both uploaded states and matching GitHub digests, then
downloaded both files through unauthenticated public URLs and verified them again. The published
checksum file lists the attached DMG; local checksums also cover the build manifest and inventory.

The source and subsequent release records stay on `dev` for a `dev` → `main` PR. The beta is
available from its immutable source commit independently of production website promotion.
Both long-lived branches are retained. See [release notes](../releases/v0.1.0-beta.20261030.md).

## Remaining acceptance

This is **ad-hoc signed and not notarized**; no valid Developer ID identity was available.
Hardware reliability, sustained physical-library performance, full VoiceOver/accessibility,
minimum macOS 26, clean-Mac Gatekeeper and notarized distribution acceptance remain open.
Neither the support link, automated tests nor publication closes those gates.
