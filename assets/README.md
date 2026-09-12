# CloakRoll artwork

These assets are original, local artwork. The scenic images are visibly illustrated sample
media for the mock library, not user photographs or evidence of device imports.

## App icon prototype

The Phase 1 icon explores a purple photo stack, a soft shield silhouette and a simple landscape.
Its rounded dimensional treatment relates to CloakDrop, while the pictogram expresses preserving
photographs. It is a **prototype**; final small-size and appearance refinements belong to Phase 8.

Editable SVG layers and the Icon Composer document live in `icon/CloakRoll.icon/`. The document
stays outside the app target so CloakRoll can target macOS 14 without depending on the newer
layered-icon format. Generated PNG slots live in
`apps/macos/App/Resources/Assets.xcassets/AppIcon.appiconset`; About uses its own 256/512 exports.
Do not hand-edit generated PNGs.

From the repository root, with Xcode 26.4 or later selected:

```sh
swift apps/macos/scripts/generate_app_icon.swift
```

The generator finds Icon Composer through `xcode-select`, uses its Default macOS rendition and
pins design generation 26 to retain the intended family treatment. App builds use the committed
conventional catalog, so regeneration is not required to build. When finalizing, inspect 16, 32,
128 and 512 pixels, including native light/dark contexts. The newer layered document is retained
for future platform adoption; the current app uses the flattened Default artwork in both modes.

## Illustrated mock library

The source for all twelve scenic illustrations is
`apps/macos/scripts/generate_sample_art.swift`. It uses only AppKit paths, shapes and gradients;
there are no downloads, photographs, third-party artwork, or random inputs.

```sh
swift apps/macos/scripts/generate_sample_art.swift
```

The generator creates `Sample0` through `Sample11` image sets, each with a 640 × 480 PNG. They
depict alpine dawn, coast, forest, dunes, lavender fields, island, snow, evening city, desert night,
autumn lake, green valley and canyon. SwiftUI previews and the explicit mock catalog can reuse
these image names without USB I/O or full-resolution originals. A sample illustration does not
represent an actual asset's metadata, transfer size or backup state.
