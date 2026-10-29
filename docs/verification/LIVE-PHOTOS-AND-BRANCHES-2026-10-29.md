# Live Photo support and branch workflow — 29 October 2026

The user requested only `main` and `dev`, ongoing development on `dev`, PR promotion to `main`,
Cloudflare Workers readiness, and a Live Photo support review. GitHub initially had only `main`;
there were no stale branches to delete. Created `dev` from the validated local work, preserving
the thirteen commits not yet published to `origin/main`.

## Live Photo audit

Reviewed `CatalogRelationships`/`CatalogAssembler`, `CameraCatalog`, original download options,
`BackupEngine`, persistence/recovery and app presentation. Existing behavior uses explicit
device relationships, preserves original bytes, downloads discovered companions independently,
and requires all components before claiming a complete logical item. Same filenames alone do
not prove a pair; ambiguous or unrelated resources remain visible separately.

Added two parameterized regression tests, eight cases in total: HEIC and JPEG stills, each with
MOV and AAE companions, in dated and flat per-iPhone folders. All cases passed. Checks verify:

- Two Live Photos with identical filenames preserve all six distinct originals without overwrite.
- Every pair and its adjustment sidecar share a destination folder; file bytes are unchanged.
- A repeat validates/reuses all components and transfers zero bytes.
- A missing motion original leaves zero completed assets while retaining verified still/adjustment
  evidence. Retry downloads the motion only and then completes the item.

Existing tests also cover session interruption, reconnect with new runtime IDs, copied-folder
history recovery and missing/corrupt companions. These automated fixtures contain opaque bytes;
they do not prove playable Live Photos, actual cable behavior or every edited/effect variant.

Media Info now labels Photo and Motion originals, explains retaining both files, and identifies
the still-only preview. Actual native light/dark samples were visually inspected; the AX rows
include those roles and file sizes. Escape dismisses the sheet. The app-only appearance override
was restored and Debug quit. No system preference or real backup was changed. Screenshots are
ignored local evidence under `apps/macos/build/Closeout-20261029/live-photo-info-*.png`.

Normal Debug build and strict lint passed. See [Live Photo support](../LIVE-PHOTOS.md) for exact
product scope and remaining independent-viewer/hardware acceptance.

## Website readiness

Added the Website workflow for pushes to `main`/`dev` and PRs to `main`. It has read-only repository
permissions, pinned official action revisions, pinned Node/npm, clean dependency installation,
site validation and Wrangler dry-run. It has no deployment credentials or publish step.

Local `npm ci`, `npm run verify` and `WRANGLER_SEND_METRICS=false npm run check:worker` passed:
three static routes, Air provenance, anchors/assets, canonical domain and GitHub release link
validated; Wrangler read 14 static files and exited in dry-run mode. The Worker remains configured
for `roll.cloakyard.com`. Dashboard settings and the production-only branch choice are documented
in [the site README](../../apps/site/README.md#cloudflare-workers-builds).

## Full native release check

Built beta **20261029.1** from clean source `ccb98dc87684644af19d431d30f1e4263171441b`.
All 403 core + 227 hosted app tests (630 Swift tests), five release-tool tests, strict lint,
probe build/10k smoke, normal Debug/arm64 Release, bundle and mounted-DMG checks passed.
Installed the packaged app and matched all 19 bundle entries. Finder's normal installer-open
layout, About version and retained destination/One Folder preference passed. Previous app is
in Trash, the installer was ejected, and the app is idle. See [artifact notes](../releases/v0.1.0-beta.20261029.1.md).

## Branch policy

Applied and read back `main` protection: pull requests required, the up-to-date Website check
required, force pushes/deletion blocked, and administrators subject to the same policy. No
additional reviewer is mandatory, allowing the owner to merge a validated PR without a second
maintainer. Automatic branch deletion is disabled, preserving `dev`. Use merge commits so dated
beta source hashes remain in repository history. GitHub PR/check records provide the final
promotion evidence; continue development on `dev` after fast-forwarding it to merged `main`.

Existing hardware, full VoiceOver, minimum OS, signing/notarization and deferred deployment gates
remain unchanged. No physical acceptance was substituted with these automated checks.
