# CloakRoll website

**The Air website for CloakRoll.**

[Website](https://roll.cloakyard.com/) · [Product README](../../README.md) · [Support](https://ko-fi.com/sumitsahoo21)

## Overview

The static Astro website for [CloakRoll](https://roll.cloakyard.com/), hosted as a Cloudflare Worker. The native macOS app lives separately in [`../macos`](../macos); this directory owns the landing, privacy and recovery pages.

## Features

A finite product illustration, clear download/installation guidance, real native-app screenshots and the shared Air header/footer. Navigation and policy reading remain useful without JavaScript. The small local script adds Escape, anchor focus and active-section behavior.

A local filmstrip arrives once, then rests. The shared lifecycle pauses offscreen/hidden and respects reduced motion, forced colours, Save-Data and constrained devices. After completion, the artwork itself accepts a deliberate replay; there are no separate playback controls.

## Privacy

The site serves static assets without analytics, external fonts, a database or media uploads. Cloudflare handles website requests. Native-app processing and network behavior are described separately in the [native privacy policy](../../docs/PRIVACY.md); the website preserves that policy and its genuine revision date. Keep policy sources and displayed copy aligned.

## Getting started

Visit [roll.cloakyard.com](https://roll.cloakyard.com/) for the product and published downloads. The website links to the [GitHub Releases index](https://github.com/cloakyard/cloakroll/releases) so prereleases remain visible. Source versions, available releases and signing status are distinct; preserve the current [root installation guidance](../../README.md#getting-started).

## Development

Use the Node range in `package.json` (`^22.23.4 || ^24.15.0 || >=26.0.0`) and the pinned npm 12.2.2. From a full repository checkout:

```sh
cd apps/site
npx --yes npm@12.2.2 ci
npm run dev
```

| Command | Purpose |
| --- | --- |
| `npm run check` | Astro type checking |
| `npm run build` | Sync source assets and build static `dist/` |
| `npm run preview` | Serve the production build |
| `npm audit` | Check the dependency graph |
| `npx --yes knip@6.44.2` | Audit the web module/dependency graph |

TypeScript 6 is retained for the supported Astro checker. Astro 7 may leave a server running after the command returns; stop owned servers with `npx astro dev stop` or `npx astro preview stop`.

`npm run verify` combines type checking, build and route/asset/canonical-source checks. `npm run check:worker` dry-runs the Worker without publishing. Run both before committing. Website checks do not certify native or physical-device acceptance.

Inspect phone, tablet, laptop and desktop in both themes, including privacy/recovery, menu focus, enlarged text, reduced motion and no-JavaScript fallback.

## Design and assets

Read the complete portable [DESIGN.md](DESIGN.md) before visible changes. The pinned `src/styles/air.css` owns shared tokens, controls and page geometry; `src/styles/global.css` owns product composition. Product colours stay in artwork.

`scripts/sync-assets.mjs` copies the native app icon and synthetic library screenshots from the repository sources. Do not use a site-only sparse checkout. Edit source assets, then rebuild. Generated public copies are not the source of truth. Screenshot content is illustrative; it contains no personal media.

The [surface inventory](../../docs/air/surfaces.json) and dated audits record actual verification separately from the design reference.

## Project structure

```text
apps/site/
├── src/components/       # Landing sections, public chrome and artwork
├── src/pages/            # Home, privacy and recovery routes
├── src/styles/           # Pinned Air foundation and site composition
├── scripts/              # Asset sync and static verification
├── public/               # Static/generated public assets
├── astro.config.mjs      # Static Astro configuration
└── wrangler.jsonc        # Cloudflare Worker and custom domain
```

<a id="cloudflare-workers-builds"></a>

## Deployment and releases

Promote verified changes through a `dev` → `main` PR and keep `dev` updated. When dev also contains unrelated native work, follow the maintainer's reviewed website-only exception instead of publishing that work. The production Worker is `cloakroll`; the repository is `cloakyard/cloakroll` and the build root is `apps/site`.

| Setting | Value |
| --- | --- |
| Production branch | `main` |
| Build command | `npm run verify` |
| Deploy command | `npx wrangler deploy` |
| Custom domain | `roll.cloakyard.com` |

Workers Builds uses dashboard-managed Git settings. Production deployment belongs to main; branch/PR builds must use preview versions. Never point a non-production branch at the production deploy command. Check the actual dashboard configuration and exact commit receipt rather than inferring deployment from `wrangler.jsonc`.

Keep watch paths aligned with `apps/site/**`, asset-sync sources, the root policy and imported `docs/air/**` assets. The full checkout is required. Native-only work must not be released by a website merge. CI validates/builds the website; no Cloudflare credentials belong in the repository.

For an explicitly authorized manual deployment, `npm run deploy` checks/builds as configured and publishes. For a local validation only, build first and run `npx wrangler deploy --dry-run`. After publication, verify the exact main build, public headers, routes and asset hashes. Native app releases and notarization are separate; the published [release notes](https://github.com/cloakyard/cloakroll/releases) own artifact and signing facts.

## Contributing

Read [AGENTS.md](../../AGENTS.md) and [CONTRIBUTING.md](../../CONTRIBUTING.md). Follow the [family README standard](https://github.com/cloakyard/cloakyard/blob/main/docs/README_STANDARD.md), keep shared Air patterns portable, and record browser coverage without claiming unperformed hardware tests.

[Buy me a coffee](https://ko-fi.com/sumitsahoo21) supports the project.

## License

Released under the [MIT License](../../LICENSE). Third-party components retain their own notices.

Built by [Sumit Sahoo](https://github.com/sumitsahoo), part of [Cloakyard](https://cloakyard.com/).
