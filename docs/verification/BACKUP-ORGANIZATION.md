# Backup folder organization — 4 October 2026

Settings → Backup → Originals now has a native **Folder structure** picker:

| Choice | New original path |
| --- | --- |
| Year and Month (default) | `iPhone <stable token>/Year/Month/original` |
| One Folder | `iPhone <stable token>/original` |

Both choices separate iPhones by the existing stable device token, even when display
names or filenames match. The flat option applies to all original components,
including Live Photo motion files and media without a capture date. It does not
convert media or attempt to reproduce Photos albums.

The preference is saved locally. Missing/invalid values retain the existing date
organization. The native picker is disabled while a backup is active; the controller
also captures its layout before folder selection, lease acquisition or transfer
awaits. A running backup cannot switch organization partway through. A later run,
including a retry, uses the current choice for originals still needing publication.

Previously verified paths are reused only after the existing size/hash checks,
regardless of the current organization preference. Changing the preference does not
move or recopy existing originals. Missing originals are published using the new
choice. Collision suffixes, descriptor-relative safe paths, no-overwrite publication,
staging and the persisted recovery journal remain in use. There is no database or
existing-file migration; journal entries already contain their exact publication paths.

## Verification

- **342 core tests pass.** Coverage includes all old/new layout combinations,
  unknown-date Live Photo components, duplicate names from different dates, an
  unrelated collision sentinel, separate phones, mixed-device rejection, symlink
  defense and recovery of interrupted publication into the flat layout.
- **148 hosted app tests pass.** Preference round-trip and invalid-value fallback
  are checked. Persistent integration reopens the database and reconnects with new
  runtime identifiers before switching layouts in both directions: two originals
  are reverified, their saved paths are preserved, and no bytes are downloaded.
  An actual AppModel → controlled source → controller → engine test changes the
  preference while the first transfer waits; that run stays flat, the next distinct
  original uses date folders, and original bytes/access-lease ownership remain correct.
- Normal Debug and Release builds, strict lint, whitespace and both signature checks
  pass with no compiler warnings. Normal Debug was rebuilt after hosted testing.
  Hosted tests still emit the pre-existing system shortcut-service diagnostics.
- Native Settings was visually inspected at its existing window size. Both choices
  can be selected and the per-iPhone/new-files explanation fits without clipping.
  The original Year and Month choice was restored after the UI check. Copying,
  Verifying and Stopping previews also confirm the companion stable-heading change.

At the start, the running app reported the user's prior 5,146-item, 9,077-original,
130.7 GB backup complete. That was observed UI state, not a new independent file
audit. No backup was running when the app was rebuilt. No physical original transfer
or deletion was initiated during this stage; tests use temporary generated files.
The iPhone was not exposed to the app for a new transfer, so a physical flat-layout
import/repeat remains pending. These automated checks and previews do not substitute
for hardware acceptance, and no broader phase gate is promoted.

Logs: `/tmp/cloakroll-flat-device-core-tests.log`,
`/tmp/cloakroll-organization-app-tests.log`, `/tmp/cloakroll-organization-build.log`,
`/tmp/cloakroll-organization-release.log`.
