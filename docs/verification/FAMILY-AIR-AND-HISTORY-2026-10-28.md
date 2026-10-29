# Family Air audit and durable backup explanations

28 October 2026. Software and browser verification only; physical acceptance remains last.

## Implementation queue

Reviewed `PLAN.md` and the current source. The V1 features are implemented; remaining phase
gates concern acceptance and distribution. Added a current checklist near the top of the plan
so historical unchecked gates are not mistaken for missing features. Restore to a new iPhone
remains conditional backlog under the no-companion-app requirement.

One reliability gap was actionable: dismissing an incomplete backup discarded its explanation.
Schema v7 now preserves a bounded failure message and distinct unavailable-original count.
History shows these inside the native disclosure. Older sessions retain unknown explanations;
no verified counts, identities or reuse rules are changed. Filenames in the terminal sheet are
still ephemeral; this change persists only the explanation and count.

Validation: 401 core tests and 224 hosted app tests pass (625 total), Debug builds, and strict
lint passes with no violations. New checks cover populated v6 migration, database reopening,
partial Live Photos, duplicate unavailable IDs, bounded messages and cancellation. Existing
older-schema migration tests still exercise their real previous schemas. The hosted missing-source
test confirms retry copies only the missing companion. Native sample History was inspected in
light/dark; the disclosure exposes the count and selectable explanation through accessibility.
This is not a complete VoiceOver acceptance pass.

## Family comparison

Read-only browser inspection covered the published Cloakyard, CloakDrop, CloakPDF and
CloakResume sites, with the local CloakResume Air build as an additional reference. CloakIMG
was excluded. KERR was inspected at the same three sizes as an intentionally distinct immersive
experiment; its design was not substituted for the Air product-page structure. No sibling repo
was edited and no site was deployed.

The first CloakResume visit returned the previous design. Subsequent fresh visits at desktop,
tablet and phone sizes returned its current Air page. Both observations are retained locally;
the cause of the earlier response is not established, so this is not reported as a confirmed
deployment defect.

| Check | Desktop 1440×1000 | Tablet 768×1024 | Phone 390×844 |
| --- | --- | --- | --- |
| CloakRoll and four Air references: header | 72 px | 72 px | 68 px, native Menu |
| Footer height and structure | 109 px, one row | 219 px, identity + two-column links | 219 px, identity + two-column links |
| Horizontal overflow | None | None | None |
| Brand, type hierarchy, gutters, neutral actions | Consistent | Consistent | Consistent |
| KERR initial screen | Fits | Fits | Fits |

The shared product footer order is Privacy, Source, MIT license, Cloakyard. The family homepage
ends with All apps instead. Product content remains specific to each task: native apps use
product/craft/privacy/download; web workbenches use their start/features/privacy sections.
CloakRoll follows CloakDrop's hierarchy without importing downloader features or claims.

Light header/hero and footer screenshots were inspected at all three sizes; dark tablet
screens were also inspected across all Air sites. CloakRoll's actual product screenshot and
feature content were inspected, revealing white raster corners against the dark frame. A
proportional CSS corner mask now follows the native window as the screenshot scales.

CloakRoll also passed overflow/image checks at 320, 375, 430, 641, 1024, 1280, 1366 and 1920 px.
At 320 px the menu expands in document flow, Download closes it and moves focus to the download
section, and the footer Privacy link opens the real policy route. The updated explanation of
local failure history is present there. Verification copy now distinguishes expected-size and
local SHA-256 checks from an unavailable independent source checksum.

`npm run verify` passes Astro checking (no errors/warnings), the production build, Air source
hashes, routes, anchors, assets, canonical domain and release destination. Browser emulation
does not establish physical Safari/device acceptance.

Local visual evidence is in `apps/site/build/family-audit/`, including light/dark native
History, family desktop/tablet/phone headers and footers, narrow menu, corrected product frame,
and `layout-metrics.json`. These are review artifacts, not committed personal media.

## Still pending

Hardware validation is deliberately last: affected-Mac long backup, incremental/new capture,
cable interruption, external-drive removal/full destination, sleep/wake and multiple physical
iPhones. Full VoiceOver, sustained performance, older supported macOS runtime and distribution
acceptance remain open. Cloudflare deployment stays ready for later as requested.

## Packaged beta

The clean `a6f4e06676eae056aeb0b977d7af201de298bbc6` source produced **0.1.0 Beta 20261028.2**.
The packaging pipeline repeated all 625 tests, strict lint, Debug and universal Release builds,
bundle checks and mounted-DMG comparison. All pass. The DMG contains 19 matching bundle entries,
the expected Air artwork/guide/layout and the Applications link.

Artifact size is 10,040,280 bytes; SHA-256 is
`3c60c620879aa69a9d629b5cc63523dc3a37b715fc981eb1c12d0d6a638d215a`.
Installed from the read-only DMG at `/Applications/CloakRoll.app`, verified its signature, then
launched and inspected About (20261028.2) and Backup Settings (existing destination and One Folder).
The prior 20261028.1 app bundle is in Trash; user backups/history/preferences were retained.
No hardware transfer was run. The local build remains ad-hoc signed, unnotarized and unpublished.
