# CloakRoll · Air

Air **1.2.4**, copied from the Cloakyard canonical design package on 28 October 2026.
`design/contract.md` is the unmodified portable contract. `design/air-manifest.json` records
SHA-256 provenance for the shared stylesheet and finite-artwork lifecycle. The production
site builds entirely from this repository; it has no sibling-checkout dependency.

CloakDrop's header/footer, neutral controls, system typography, open composition, responsive
menu and focus handling are reused under the family's MIT license. CloakDrop remains
read-only. Product copy, previews, release status and privacy details describe CloakRoll.

CloakRoll-specific extension: a bounded strip of five illustrated scenes unrolls into place:
mountains, a sailboat at the coast, flowers, a city at dusk and a forest path. Different subjects,
silhouettes and muted palettes suggest a varied camera roll within one illustration style.
This is decorative identity artwork, not a simulated backup or progress meter.
Only the artwork uses muted product colors. Navigation and actions keep Air's semantic
palette. Existing shared `--air-*` values are not overridden. The illustration is code-native
SVG with a still HTML/CSS base; no raster generation, remote asset, looping animation or
playback controls are needed. No changes are made to the canonical family package.

The website-only circular mark follows CloakDrop's 64-unit enclosure (30-unit radius), displayed
at the shared 36px size. It reuses CloakRoll's native mountain/sun paths and palette; the native
Icon Composer document is unchanged. The SVG is also the browser favicon, with the separate
native PNG retained for touch-icon compatibility. The screenshot section shows the actual app
with the repository's varied synthetic sample library. The hero CTA always leads to the download section,
which describes the current beta state and links to the repository's release index.
