# Website layout follow-up — 2026-11-03

The six-site Air 1.5.0 audit found two website copy deviations: numbered feature
eyebrows and text saying the first beta was still being prepared. The labels now
use plain sentence case; the download section reflects the published
[public beta](https://github.com/cloakyard/cloakroll/releases/tag/v0.1.0-beta.20261030).
Installation guidance points to the available GitHub releases.

`npm run verify`, `npm run check:worker` and the root standalone portability
check pass. The final built website passes 312 link/layout observations and 108
keyboard interactions on home, privacy and 404, with no browser errors. Reviewed
phone, tablet and desktop light/dark captures are retained alongside the compressed
report in `evidence/all-layouts-2026-11-03/`.

The wider family audit covers all eleven required viewport sizes, enlarged text,
privacy/back navigation, neutral links, header/footer geometry and normal/reduced
motion. Its canonical record is in Cloakyard's
`docs/air/all-layout-audit-2026-11-03.md`; this local report remains understandable
without a sibling checkout. Browser automation does not certify physical iPhone,
software-keyboard, spoken-assistive or native USB/hardware acceptance.

This website-only piece is based on remote dev/main `001977c`. Concurrent native
work in the original checkout is excluded. Promotion uses the authorized dev →
main PR; its description records exact-main checks and deployed asset verification.
No native source, dependencies, policy meaning or contract tokens change.
