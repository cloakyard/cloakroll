# Backup reliability and Air website — 28 October 2026

## Report and scope

The reported error was from **another Mac**, with the iPhone still connected. The screenshot's
`MediaModels.MediaSourceError error 2` maps to `missingResource` (confirmed with a Swift
NSError bridging probe). This means a queued original no longer resolves in the current
USB registry. No diagnostic log/database from the affected Mac is available. The cause of
its catalog change has not been established or reproduced on physical hardware.

A missing original now allows other originals and surviving Live Photo companions to continue.
It leaves a truthful incomplete outcome, lists unavailable filenames, and never records a
missing component as verified. Cancellation, session/access changes and destination/persistence
failures still stop. Readable source errors replace enum error codes. Saved components retain
persistent retry evidence. These changes are in commit `ca4b2e0`.

Regression coverage includes missing still + surviving motion + later photo, all originals
missing, cancellation, stale/access failures, persisted incomplete history and reconnect retry
copying only the missing still. Full software checks pass: **398 core + 224 hosted app tests**,
strict SwiftLint (146 files), Xcode project generation and hosted Debug build. This does not
replace a repeat of the large backup on the affected Mac.

## Combined media folders

The existing Settings → Backup → Folder structure → One Folder option already places photos,
videos and companions together in one per-iPhone folder. Its explanation now states that
explicitly and follows the selected option. The stored preference and existing paths are
unchanged. New coverage uses independent photo/video assets on different dates and proves
both share the phone folder and a repeat transfers zero bytes. Existing tests cover name
collisions, multiple phones, partial Live Photos and changes of organization.

## Dependencies

Checked upstream sources on this date. App/runtime GRDB **7.11.1** and build-only dmgbuild
**1.6.7**, ds_store **1.3.3**, mac_alias **2.2.3** already match stable upstream versions.
Exact pins and hashes were retained. Sources: GitHub `groue/GRDB.swift/releases/latest` and
PyPI's package JSON endpoints. No dependency bump is claimed for unchanged native packages.

Website: Astro **7.4.3**, @astrojs/sitemap **3.7.4**, @astrojs/check **0.9.12**, Wrangler
**4.154.0**, TypeScript **6.0.3**. TypeScript 7.0.2 was tested but is explicitly unsupported
by `astro check`; retained its supported 6.x version instead. npm registry checks and the
lockfile record the versions. `npm audit` reports zero vulnerabilities across the tree.

## Website implementation

User selected the same repository + Cloudflare setup as CloakDrop. `apps/site` is a static
Astro site with its own `cloakroll` Worker and `roll.cloakyard.com` custom-domain configuration.
Air 1.2.4 stylesheet, contract and lifecycle are copied with SHA-256 provenance. Builds have
no dependency on sibling checkouts. CloakDrop/CloakPDF were read-only references.

Shared header/footer/neutral buttons/typography/navigation follow CloakDrop. The unique
mountain-and-sun filmstrip has a finite 2.66-second unfolding sequence and static fallback;
no animation library or external visual assets. App previews are repository sample media.
Hero CTA goes to `#download`, then the real GitHub Releases index, including future prereleases.
The releases API currently returns no published releases, so preparation copy is explicit;
no guessed DMG download URL or false public-availability claim. Privacy and 404 pages included.

Astro check, production build, Air hash verification, route/anchor/asset checks and audit pass.
Visual comparison: live CloakDrop and CloakPDF's current **local Air build**. The public PDF
site still shows an older design; it is not evidence of current Air parity.

Browser QA uses the Codex in-app browser, not a physical mobile device. Layout widths/heights:
320×568, 375×812, 390×844, 430×932, 639×800, 640×800, 641×800, 768×1024, 1024×768,
1280×720, 1366×768, 1440×900, 1920×1080, 844×390. No document horizontal overflow in
these sizes. Native menu switches at the 640/641 boundary. The initial small-screen strip
centering/clipping bug was found in visual review and fixed. Desktop light/dark, phone hero
and download, and tablet app-preview sections were inspected. Menu Escape restores summary
focus; hero download focuses `#download`. Reduced motion yields the still scene. 200% root
text size at 320px has no horizontal overflow. With scripts disabled, native menu and download
anchor work; scripts were restored after checking. Additional final checks are recorded below.

## Distribution boundaries

Cloudflare `wrangler whoami` reports not authenticated on this Mac. No domain route, DNS or
public deployment has been changed. A Cloudflare login with access to the Cloakyard account
is required for `npm run deploy`. No GitHub app release/tag has been published. Native beta
remains ad-hoc signed and unnotarized. Earlier hardware/accessibility/older-runtime gates
remain open; this work does not close them.
