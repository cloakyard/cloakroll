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
