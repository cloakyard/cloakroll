# CloakRoll landing motion and web dependencies

24 November 2026 · Air 1.8.1

Product introduction and preview, feature and principle articles, privacy copy and download instructions.

The production landing passed 22 viewport sizes in both themes in Chromium and
WebKit. The browser measured the combined 520 ms wipe, fade and 4 px settle,
checked the stagger where blocks enter together, and scrolled back through the
page to check that blocks play once. Focus, initial fragments, return from
privacy, live reduced motion, print, forced colours and the missing-observer
fallback passed. A touch profile also checked direct navigation with reduced motion.

![Phone, tablet, laptop and desktop scroll samples in light and dark](evidence/landing-reveals-2026-11-24.jpg)

## Dependencies and feature coverage

Compared all 5 direct web runtime and development package declarations with
the npm registry and refreshed the lockfile. Astro 7.4.13, Sitemap 3.7.6, Wrangler 4.167.0 and npm 12.2.3. TypeScript 6.0.3 is the latest supported by Astro Check 0.9.12.

Clean npm installation, package-tree check, audit, Astro diagnostics, site verification, Knip and Wrangler Worker dry-run. Link checks covered 312 layouts and states and 108 keyboard checks across home, privacy and recovery. Navigation correctly marks the last section when it reaches the bottom of the page.

This review covered the web landing and the listed regression checks on local
builds. Physical-device and assistive-technology acceptance remain open.

## Release verification

The installation instructions use their visible heading. The reference to a missing accessibility label was removed. The site includes the Air 1.8.2 portable bundle.

Production testing exposed a slow-load layout shift in the product screenshot. Its 2200 × 1480 HTML dimensions now reserve the full image height before its bytes arrive. The product browser regression in `scripts/test-air-preview.mjs` holds back the light and dark screenshots and compares the preview height before and after decoding. At 390 px the original height jumped from 0 to 229 px, interrupting the next feature reveal. The corrected height stayed fixed at 390, 768, 1280 and 1440 px in both themes. [Responsive preview captures](evidence/preview-reservation-2026-11-24.jpg)
