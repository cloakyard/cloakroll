# Social preview consistency — 2026-11-16

The website now shares Air 1.7.5's 1200×630 social composition. Its illustrated
landing filmstrip replaces the raw library screenshot in OG/Twitter previews.
Home, privacy and recovery include matching absolute image URLs, PNG dimensions
and descriptive alternatives. `npm run build` checks all emitted HTML and PNGs.

The card is generated from the existing built landing; native source, app UI and
README screenshots are unchanged. The generated public PNG is ignored and copied
from `assets/social/og.png` by prebuild. See [the portable workflow](social-previews.md)
and [validation receipt](evidence/social-previews-2026-11-16/receipt.json).

The scoped family audit covers 48 card previews across phone/tablet/laptop/desktop
and light/dark surroundings, crawler metadata and repeatable image generation.
This is not new native/full-editor/physical-device acceptance. Keep the approved
website-only PR route and synchronize main into dev without releasing its native history.
