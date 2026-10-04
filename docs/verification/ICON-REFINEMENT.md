# Landscape icon refinement — 4 October 2026

## Update — landscape fills the app icon

Following the user's request to retain the identity and remove the inset square, the existing
mountain and sun artwork now fills the system enclosure. The photograph layer and its clipping
frame are removed. The four remaining foreground SVGs use a uniform 1.6× scale, preserving the
sun's circular proportions and the original ridge curves. Mountain paths extend past the
canvas edges; the opaque warm sky is now the document background. Icon Composer supplies the
outer mask and material, including its dark background; lighter dark mountain fills remain.

The canonical `.icon` is still compiled directly by Xcode. Default/Dark About images and all
six appearance previews were regenerated with the existing validated generation-27 exporter.
No application behavior, source media or saved originals changed.

Actual verification for this update:

- Visually inspected Default, Dark, Clear Light/Dark and Tinted Light/Dark at 512 pixels,
  plus Default at 16, 32, 64 and 128 pixels. The sun and ridge remain distinct without an inset border.
- Launched the rebuilt Debug app and inspected About in light and dark on the current Mac;
  both use the new artwork. Restored system appearance afterward.
- Debug and Release builds passed without warnings or errors; both signatures passed
  `codesign --verify --deep --strict`.
- Compiled asset inspection confirms the four foreground vectors and native icon stacks,
  alongside generated fallback artwork and `CloakRoll.icns` for the macOS 14 deployment target.
- All 342 core tests, strict SwiftLint and `git diff --check` passed. No new behavior tests
  were added for this vector/resource-only change.

Logs: `/tmp/cloakroll-full-icon-export.log`, `/tmp/cloakroll-full-icon-debug-build.log`,
`/tmp/cloakroll-full-icon-release-build.log`, `/tmp/cloakroll-full-icon-core-tests.log`.
Older macOS runtime checks remain pending; preview/export and deployment-target compilation
do not substitute for them.

## Previous inset composition

The final direction preserves the mountain and sun requested by the user. A broad violet
ridge curves into the foreground, with a lighter distant peak and an apricot sun in a pale
photo window. The Dark variant uses a deep night sky and lighter mountain faces. It has no
shield, letter mark, curled paper, text, hardware illustration or backup arrow.

## Artwork and Apple integration

- Canonical source: `assets/icon/CloakRoll.icon`, a 1024 × 1024 document with five SVG layers
  in one foreground group. The opaque full-bleed document background supplies the outer tile.
- The photograph's inner frame is artwork. The outer enclosure mask, highlights, shadow and
  translucency are applied by Icon Composer; these effects are not painted into SVGs.
- XcodeGen includes the `.icon` file in the app resource phase, with app-icon name `CloakRoll`.
  Build logs confirm `actool` compiles the actual document with minimum deployment target 14.0.
- The old flattened `AppIcon.appiconset` is removed. A clean build produces `Assets.car` and
  `CloakRoll.icns`, with both `CFBundleIconName` and `CFBundleIconFile` set to `CloakRoll`.
- `assetutil --info` confirms five vector assets, native Aqua/Dark Aqua/tintable icon stacks,
  and fallback images through 1024 pixels. The generated ICNS contains 16/32/128/256 PNGs.
- The export script stages all renditions and validates PNG type, dimensions and decoding
  before publishing. Four Default/Dark About images use asset-catalog luminosity variants.

Design and integration were checked against Apple's
[app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons/),
[Icon Composer integration](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
and [Liquid Glass adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).
This records conformance work, not Apple certification.

## Actual verification

Host: macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), SDK macOS 27, Icon Composer 27.0.

| Check | Actual result |
| --- | --- |
| Generation 27 exports | Default, Dark, Clear Light/Dark and Tinted Light/Dark rendered successfully and visually inspected at 512 pixels. |
| Small-size artwork | Default inspected at 16, 32, 64 and 128 pixels; mountain silhouette and sun remain visible. |
| Generation 26 preview | Default rendered and visually inspected using generation 26; this is a renderer check, not an older-OS runtime test. |
| Native app | Rebuilt app launched on macOS 27.0.1. About inspected in light and dark; both display new artwork. System appearance restored afterward. |
| Debug | Clean normal build succeeded, with no warnings or errors. |
| Release | Separate normal Release build succeeded, with no warnings or errors. |
| Core tests | All 305 passed (31 + 27 + 74 + 82 + 42 + 49). |
| Lint and whitespace | `swiftlint --strict --quiet` and `git diff --check` passed. |
| Signatures | `codesign --verify --deep --strict` passed for Debug and Release. |

Build logs for this local run: `/tmp/cloakroll-icon-debug-build.log`,
`/tmp/cloakroll-icon-release-build.log`, `/tmp/cloakroll-icon-core-tests.log`.
Committed previews are in `assets/icon/Previews`; they are generated with design generation 27.

The macOS 14 deployment target remains unchanged. Xcode's fallback generation is verified;
macOS 14 and 26 runtime appearance remains untested. No new hosted app tests were needed for
this artwork/resource change. No iPhone media or backups were changed during this work.

## Concept provenance

The built-in image-generation tool supplied a visual concept only. Production artwork was
then drawn as layered SVG and rendered by Icon Composer. The generated concept is not a
runtime asset. The final concept prompt was:

> Use case: logo-brand. Create a single premium macOS app icon concept for CloakRoll, an iPhone photo and video backup app. The USER specifically wants a mountain and sun so it unmistakably reads as a photo app, but a distinctive original identity. Design a beautifully balanced, restrained icon at Apple native app quality. Square composition. Deep iris/violet full-bleed background with subtly rounded macOS corners. Foreground: ONE elegant pale photographic window containing a bold sculptural purple mountain range, a warm apricot sun, and a small second lavender mountain plane, composed so the mountain ridge has a memorable flowing diagonal silhouette. The scene should feel like a captured moment, simple and confident, not a generic stock pictogram. Use broad clean geometric shapes and very few elements, with refined spacing and optical balance. Distinctive asymmetry; generous negative space. A subtle glass-like material can suggest the native macOS 27 appearance, but do not add excessive gloss, noise, gradients within every shape, shine streaks, tiny details or outlines. No shield, no padlock, no curled paper, no letter C, no text, no download arrow, no film sprocket holes, no camera hardware, no stacks of cards. One finished icon only, front view, no mockup device, no comparison sheet, no labels. This is a visual concept reference; final production will be redrawn as layered SVG in Apple's Icon Composer.
