# Apple silicon, Settings and Dock refinement — 28 October 2026

## Scope

- The app and local package now require macOS 26.0; the app project and beta pipeline build
  arm64 only. The release checker rejects any other executable architecture and verifies
  both Info.plist and the actual Mach-O minimum OS load command. Website hero/download copy,
  schema metadata, installer artwork/guide and contributor guidance agree.
- CloakDrop remained read-only. Its installed Settings/About UI and five-tap Matrix effect
  were inspected, together with its native Settings, Matrix and Dock controller sources.
- CloakRoll retains the same 640×600 native tabbed Settings content, grouped forms, label/value
  alignment, centered 84-point About icon and semantic accent. Closing Settings resets General;
  the explicit About command can still choose About. Browsing preferences remain persistent.
- Five taps on the icon activate digital rain. Tapping again stops and rearms it; leaving
  About resets it. Animation is confined to the card, pauses for inactive scenes and uses a
  still frame under Reduce Motion. No timers or decorative animation run before activation.
- The app-owned Dock observer uses the backup bar's byte percentage and survives the library
  window's lifecycle. Unknown totals show an ellipsis/empty track. Updates coalesce by whole
  percent; incomplete bytes cannot round to 100. The full ring is data progress, not verification
  success. The normal icon returns after completion, failure or cancellation settles.

## Actual software and visual checks

- Xcode 27.1 on Apple silicon/macOS 27.2: 401 core and 227 hosted app tests pass (628 total).
  The new controller-driven tests cover received-byte progress independent of asset counts,
  very large byte totals, no-window observation, coalescing, completion, failure, Stop and
  source-disconnect cleanup. Tests use temporary files; no physical originals were transferred.
- Normal Debug build passes, strict SwiftLint has zero violations. `npm run verify` passes
  Astro checks, static build, Air provenance, routes, local assets and download destination.
- Native About: five taps visibly activate the rain; the icon stops it. General reappears after
  closing/reopening Settings. General, Backup and About were visually inspected in light
  appearance and About/Matrix in dark appearance against the family reference.
- The production AppKit Dock renderer was visually inspected in the Debug examples window at
  unknown, 33%, 99% and 100%. The actual Dock could not be captured through the native automation
  surface; this is renderer/controller evidence, not a real USB/Dock acceptance claim.
- Website inspected at 1440×1000, 768×1024 and 390×844. Requirements fit beside the download
  actions, mobile/tablet document widths equal viewport widths, and the hero action reaches
  `#download`. No deployment was performed.
- Local visual evidence is under ignored `apps/site/build/silicon-settings-dock/`: Settings,
  Matrix, Dock renderer and responsive landing-page screenshots. No personal media is included.

## Remaining acceptance

The final dated beta artifact is recorded in its release notes after packaging. Physical backup,
background Dock progress, unplug/retry, multiple iPhones, minimum macOS 26 runtime, full VoiceOver
and system Reduce Motion acceptance remain separate. Hardware is explicitly last. Developer ID,
notarization and website deployment are still deferred.
