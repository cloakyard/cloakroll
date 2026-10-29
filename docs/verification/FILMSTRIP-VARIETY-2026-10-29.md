# Landing filmstrip variety — 29 October 2026

The user reported that the deployed animation's images looked almost identical. Inspected
`https://roll.cloakyard.com/` in Chrome: five frames used the same mountain silhouette with
different palettes. This also confirms the user's first website deployment; no app release
publication was inferred from it.

## Change

The filmstrip now contains mountains, a coast with a sailboat, flowers, a city at dusk and a
forest path. Each has a different composition and muted palette, with a shared flat illustration
style. `PhotoRollScene.astro` renders local inline SVG; no image requests or dependency are added.
The existing strip geometry, arrival timing and pinned Air lifecycle remain unchanged. Native
app code, header/footer, navigation and download behavior are unchanged.

## Verification

- `npm run verify`: Astro check/build and Air provenance, routes, anchors, local assets,
  canonical domain and release-target validation passed.
- `WRANGLER_SEND_METRICS=false npm run check:worker`: passed, 14 static files, no deployment.
- Chrome visual inspection: 1440×900 desktop, 768×1024 tablet, 390×844 phone and 320×568 minimum
  width. All five subjects remain distinct and the strip stays within the page.
- Dark appearance plus reduced motion at 390×844: all scenes render; lifecycle reports `reduced`.
  Normal animation reports `playing` after reload and `complete` after arrival. Browser console
  contained no warning/error entries during this check. Temporary emulation was restored.
- Production-output DOM/layout checks at 320×568, 375×812, 390×844, 430×932, 844×390, 768×1024,
  1024×768, 1280×720, 1366×768, 1440×900 and 1920×1080: five frames and no horizontal document
  overflow at every size. This is browser emulation, not physical mobile-device acceptance.

Local screenshots: `apps/site/build/verification/20261029-filmstrip-*.png` (ignored).
Prepared on `dev` for a PR into `main`; the user's merge can trigger Workers Builds. No direct
Cloudflare deployment, hardware backup or native beta rebuild was performed for this artwork change.

## Follow-up: circular web mark and varied app captures

The user also requested CloakDrop's rounded website logo treatment and more varied artwork in
the actual app preview. Added a website-only circular SVG using the native mountain/sun paths
inside CloakDrop's 64-unit, 30-radius enclosure. The header keeps the shared 36px mark size;
the SVG is also the browser favicon. Native Icon Composer sources, About artwork and the
separate PNG touch icon are unchanged. Compared the live CloakDrop header and its local SVG
source; the family Air package, header/footer layout and navigation are unchanged.

Updated the deterministic AppKit sample-art generator with flowers, a café still life, an arched
courtyard, a resting cat and citrus, plus a sailboat in the coastal scene. The existing landscapes
provide the remaining subjects. All twelve are original local illustrations; no personal media,
remote image service or third-party artwork is used.

Captured the rebuilt native Debug app using the Development menu's 1,200-item sample library,
Standard Window and Light/Dark appearances. Both 2200×1480 captures show eight distinct subjects
in the first two rows and retain the explicit sample-library disclosure. Saved real UI captures,
encoded as PNG without compositing, to `assets/screenshots`; the site asset-sync process copies
them into `public/images`. Updated README, page and social-image descriptions accordingly.
Restored System appearance, closed Debug and reopened the installed beta.

Additional verification:

- Sample generator completed, normal arm64 Debug build succeeded, and strict SwiftLint reported
  zero violations across 151 files. Only sample art changes in the native app; no transfer or
  catalog behavior changed and no new beta was packaged or installed.
- `npm run verify` passed with zero Astro diagnostics, and Worker dry-run passed with 15 static
  files. Source screenshot copies match the built site assets.
- Actual Chrome inspection of the rebuilt static site: desktop 1440×900, tablet 768×1024,
  phone 390×844, and narrow dark/reduced-motion 320×568. The header logo stays 36px; no horizontal
  overflow. Inspected the new product capture on desktop, tablet and phone, and confirmed dark
  mode loads `library-dark.png` at its full 2200px source width. No console warnings/errors.
- Browser media/viewport overrides were restored. Local visual evidence is in
  `apps/site/build/verification/20261029-rounded-logo-*.png` and
  `20261029-varied-product-*.png` (ignored).

The follow-up remains on `dev` in PR #2. `main`, Cloudflare settings and the deployed site are
unchanged; merging the PR is the user's production release step.

## Puppy revision and publication request

The user subsequently requested a cute dog instead of the cat and explicitly asked to deploy.
Replaced only `Sample6` with a floppy-eared puppy on the existing cushion, regenerated the
deterministic asset, and captured new light/dark native screenshots at 2200×1480. Updated the
website's image description and artwork inventory. The sample disclosure remains visible;
no personal photos or composited UI are used.

Normal arm64 Debug build, strict lint (151 files, zero violations), `npm run verify` and Worker
dry-run passed. Inspected the rebuilt static page at 1440×900, 768×1024 and 390×844, including
the dark screenshot. No horizontal overflow; both screenshot variants load correctly. App and
browser appearance overrides were restored and the installed beta reopened. No app beta was
repackaged. Local evidence: `apps/site/build/verification/20261029-puppy-*.png` (ignored).

Publication is now authorized through PR #2 after CI; its final deployment result is recorded
in the PR. Cloudflare's previously observed build root `/` must be corrected to `apps/site`
before promotion. Retain both `main` and `dev` and fast-forward `dev` after the merge.
