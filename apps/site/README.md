# CloakRoll website

Static Astro landing page for **https://roll.cloakyard.com**, deployed as Cloudflare Worker
`cloakroll`. It follows CloakDrop's repository/deployment pattern and Air 1.2.5.

```sh
npm ci
npm run dev
npm run verify
npm run check:worker
npm run deploy
```

Use Node 24.15 or later in the supported engine ranges. The lockfile pins dependencies;
TypeScript 6.0.3 is retained because `astro check` does not support TypeScript 7.0.
`npm run verify` checks types, builds the site, and validates routes, anchors, assets,
canonical links and the pinned Air sources. `npm audit` checks the dependency tree.
`.node-version` selects Node 24.22.1 for Workers Builds and GitHub Actions. `check:worker`
dry-runs the configured static Worker without publishing it or requiring Cloudflare credentials.

## Cloudflare Workers Builds

Connect this repository as a **Worker**, with these settings when ready to deploy:

| Setting | Value |
| --- | --- |
| Repository | `cloakyard/cloakroll` |
| Production branch | `main` |
| Root directory | `apps/site` |
| Build command | `npm run verify` |
| Deploy command | `npx wrangler deploy` |
| Worker name | `cloakroll` |
| Custom domain | `roll.cloakyard.com` |
| Non-production branch builds | Disabled initially; `dev` is for ongoing app/site work |

The full repository must be checked out: the asset-sync step reads the app icon and sample
screenshots outside `apps/site`. Avoid a site-only sparse checkout. If adding build watch paths,
include those asset sources as well as `apps/site/**`. Node and npm are pinned in `.node-version`
and `package.json`; dependency installation uses the committed npm lockfile. Do not use
`npm run deploy` as the build command, because that would publish before the deploy stage.

Work on `dev`, open a PR into `main`, and merge after the Website check and relevant native
checks pass. The GitHub workflow only validates/builds/dry-runs; it has no deployment credentials.
Keep `dev` after merging and fast-forward it from `main`. Never use `wrangler deploy` for a
non-production branch against this production configuration. Preview deployment can be configured
separately if requested; it is not enabled by this repository setup.

These settings follow Cloudflare's [Workers Builds configuration](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/),
[production/preview branch behavior](https://developers.cloudflare.com/workers/ci-cd/builds/build-branches/)
and [runtime version overrides](https://developers.cloudflare.com/workers/ci-cd/builds/build-image/).

## Manual deployment and content

For first deployment, run `npx wrangler login` with access to the Cloakyard Cloudflare account.
Review `wrangler.jsonc` before deploying. The custom-domain route creates the binding for
`roll.cloakyard.com` in that account. Existing unrelated DNS records must be reviewed rather
than overwritten. No credentials are committed. The site has no server runtime, database,
analytics, external fonts or media upload endpoint. Cloudflare still handles network requests.

The download button scrolls to `#download`; its release link points to the GitHub Releases
index so prereleases remain visible. The public repository currently has no published release.
Update the honest preparation copy only after a beta asset and release notes are published.
Do not link to a guessed asset URL or automatically publish an app release from this site.

App icon and sample-library screenshots are copied from this repository by `predev`/`prebuild`.
They contain no personal media. Light and dark screenshots follow the visitor's system theme.
The privacy page preserves `docs/PRIVACY.md` and includes website hosting behavior; keep both
in sync when the app changes its data handling.

The filmstrip is a local SVG/CSS composition. It plays once (maximum 2.66 seconds), then
settles. The shared Air lifecycle pauses offscreen/hidden, and uses the static scene for reduced
motion, forced colors, Save-Data and constrained devices. All content and navigation remain
available without JavaScript.

See `DESIGN.md` for source provenance and the dated verification document under
`../../docs/verification/` for actual browser results. Browser viewport checks do not establish
physical iPhone/Safari compatibility or the native app's remaining USB acceptance gates.
