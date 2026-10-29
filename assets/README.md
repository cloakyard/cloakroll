# CloakRoll artwork

These assets are original, local artwork. The scenic images are visibly illustrated sample
media for the mock library, not user photographs or evidence of device imports.

## App icon

The icon is an edge-to-edge landscape with a sweeping violet mountain ridge, a distant lavender
peak and an apricot sun. Four editable SVG foreground layers and a full-bleed warm sky live in
the canonical [Icon Composer document](icon/CloakRoll.icon/). The system supplies the enclosure
mask and material effects, following Apple's [app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons/).
There is no inset photo frame or surrounding purple tile. The Dark appearance uses the system's
dark background with lighter mountain faces. The concept was explored with built-in image
generation, then drawn as editable vectors; no generated bitmap or baked glass lighting ships
in the layered icon. See the [design and verification record](../docs/verification/ICON-REFINEMENT.md).

`apps/macos/project.yml` includes this document as an app target resource and sets
`ASSETCATALOG_COMPILER_APPICON_NAME` to `CloakRoll`. Xcode 27 compiles it into `Assets.car` and
`CloakRoll.icns` with a minimum deployment target of macOS 14. The generated Info.plist uses
`CloakRoll` for `CFBundleIconName` and `CFBundleIconFile`. The former PNG `AppIcon.appiconset`
has been removed; Xcode generates the older-system representation from the layered source.
See Apple's [Icon Composer integration and compatibility guidance](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

Select **Xcode 27** for generation and builds. From the repository root:

```sh
swift apps/macos/scripts/generate_app_icon.swift
```

The generator locates Icon Composer through `xcode-select` and pins design generation 27.
It exports six 512-pixel appearance previews—Default, Dark, Clear Light/Dark and Tinted
Light/Dark—plus Default previews at 16, 32, 64 and 128 pixels into `assets/icon/Previews`.
Default and Dark About artwork is generated at 256 and 512 pixels in `AboutAppIcon.imageset`.
All exports are staged and validated before replacing committed outputs. Do not edit these
PNGs by hand; regeneration updates previews and About artwork, while the app build compiles
the canonical layered icon directly.

From `apps/macos`, regenerate and build the project:

```sh
GIT_CONFIG_COUNT=0 xcodegen generate
GIT_CONFIG_COUNT=0 xcodebuild -project CloakRoll.xcodeproj -scheme CloakRoll -destination 'platform=macOS,arch=arm64' -configuration Debug -derivedDataPath build/Verify build
```

Inspect every appearance and the small-size previews after artwork changes. The generated
ICNS was inspected and contains 16, 32, 128 and 256-pixel PNG renditions; `Assets.car` also contains
fallback images through 1024 pixels and native Aqua, Dark Aqua and tintable icon stacks. Successful compilation
for the macOS 14 deployment target establishes fallback generation; runtime appearance on
macOS 14 and macOS 26 has not been verified. Generation-27 previews describe the current
material rendering, not those older systems.

## Illustrated mock library

The source for all twelve sample illustrations is
`apps/macos/scripts/generate_sample_art.swift`. It uses only AppKit paths, shapes and gradients;
there are no downloads, photographs, third-party artwork, or random inputs.

```sh
swift apps/macos/scripts/generate_sample_art.swift
```

The generator creates `Sample0` through `Sample11` image sets, each with a 640 × 480 PNG. They
depict alpine dawn, a coastal sailboat, flowers, a café still life, an arched courtyard, an island,
a resting cat, an evening city, desert night, citrus, a green valley and a canyon.
SwiftUI previews and the explicit mock catalog can reuse
these image names without USB I/O or full-resolution originals. A sample illustration does not
represent an actual asset's metadata, transfer size or backup state.


## Air installer and README captures

The beta installer follows CloakDrop’s Air composition: light neutral page, native system
fonts, open spacing, a restrained purple horizon, a single arrow and real Finder items.
Editable source: `apps/macos/scripts/dmg/background.swift`. The committed export is
`assets/dmg/background.png` (1520×1140, 144 dpi, displayed at 760×570 points).
The artwork is authored in AppKit and uses the existing CloakRoll icon; no AI bitmap is needed.
See [Release](../docs/RELEASE.md) for regeneration and mounted validation.

`assets/screenshots/library-light.png` and `library-dark.png` show the current native app
with its illustrated sample library. They contain no personal media and do not prove a physical
backup. Refresh through the Debug Development menu and inspect both appearances.

The website uses `apps/site/public/cloakroll-mark.svg`, a circular adaptation of the native
mountain-and-sun paths matching CloakDrop’s web mark. It is used for the site brand and SVG
favicon only; the native layered app icon and touch-icon PNG are unchanged.
