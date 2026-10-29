# Contributing to CloakRoll

Start with [development](docs/DEVELOPMENT.md), [architecture](ARCHITECTURE.md) and the
[implementation plan](docs/PLAN.md). Keep changes focused on the current backup scope.
Use native macOS controls, semantic colors and small app-side presentation components.
The headless Swift package must remain independent of SwiftUI.

## Branches and pull requests

`dev` is the ongoing development branch; `main` is the reviewed production source for the
Cloudflare Worker. Keep both branches. Start work on `dev`, commit verified stages, and open
a `dev` → `main` pull request when ready. Merge with a merge commit so the shared branch history
and beta source commits remain intact. After merging, fast-forward `dev` from `origin/main`.
Do not squash, rebase or delete the shared `dev` branch after a release.

The Website check builds the static site and dry-runs Wrangler on pushes to either branch and
on pull requests to `main`. It does not deploy. Native Swift/hardware evidence belongs in the PR
as well; a passing website check does not establish app acceptance. See the
[Cloudflare setup](apps/site/README.md#cloudflare-workers-builds) before connecting production.

Run the core and hosted app tests, a normal Debug build and strict SwiftLint before a
pull request. Record exactly what you verified; sample data does not establish hardware
acceptance. See [release checks](docs/RELEASE.md) for packaging and physical test gates.

Preserve originals, per-iPhone identity, verified completion and no-overwrite publication.
Never match media by filename alone. Do not include private photos, databases, device IDs
or paths in issues, fixtures or screenshots. Use the illustrated sample library for UI work.

Contributions are under the [MIT License](LICENSE). Third-party components retain their licenses.
