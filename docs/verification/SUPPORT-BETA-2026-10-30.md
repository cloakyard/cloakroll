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

Full dated release verification and publication are recorded after building from the clean
source commit. Hardware, sustained performance, full VoiceOver, minimum-OS and notarization
acceptance remain open; this link and dependency update do not close those gates.
