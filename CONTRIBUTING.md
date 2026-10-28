# Contributing to CloakRoll

Start with [development](docs/DEVELOPMENT.md), [architecture](ARCHITECTURE.md) and the
[implementation plan](docs/PLAN.md). Keep changes focused on the current backup scope.
Use native macOS controls, semantic colors and small app-side presentation components.
The headless Swift package must remain independent of SwiftUI.

Run the core and hosted app tests, a normal Debug build and strict SwiftLint before a
pull request. Record exactly what you verified; sample data does not establish hardware
acceptance. See [release checks](docs/RELEASE.md) for packaging and physical test gates.

Preserve originals, per-iPhone identity, verified completion and no-overwrite publication.
Never match media by filename alone. Do not include private photos, databases, device IDs
or paths in issues, fixtures or screenshots. Use the illustrated sample library for UI work.

Contributions are under the [MIT License](LICENSE). Third-party components retain their licenses.
