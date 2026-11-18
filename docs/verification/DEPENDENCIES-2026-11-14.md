# Native dependency audit — 14 November 2026

Updated the sole third-party Swift library, GRDB, from 7.11.1 to 7.12.0 in the core package and generated-data performance probe. Both resolved files pin upstream revision `92a554c` (full revision in the lockfiles). Native UI, backup behavior and app version are unchanged.

Validation: 418 core tests and 246 hosted app tests pass (664 total); strict SwiftLint, normal arm64 Debug build and a separate clean build pass. Compiler-backed unused-import analysis checked all 167 first-party files with zero violations. The Release performance probe builds and completes its 10,000-item generated-data run, including identity/candidate and completion-query checks. The initial probe resolution found its separate old pin; both manifests and lockfiles now agree.

The build-only DMG dependencies remain current: dmgbuild 1.6.7, ds_store 1.3.3 and mac_alias 2.2.3, checked against PyPI. No new dependency is added. No native installer/release is published or installed, and physical USB, minimum-OS, spoken accessibility and distribution gates remain open. These software checks do not establish hardware acceptance.

Source: [GRDB 7.12.0 release](https://github.com/groue/GRDB.swift/releases/tag/v7.12.0). Portable receipts are in `dependencies-2026-11-14/manifest.json`; full local logs remain in the family audit workspace.
