# CloakRoll documentation

## Using the app

- [Beta notes](releases/v0.1.0-beta.20261029.md) — installation, scope and known limits.
- [Privacy](PRIVACY.md) — local data, originals, recovery records and removal.
- [Folder organization](verification/BACKUP-ORGANIZATION.md) and [per-iPhone folders](verification/DEVICE-DESTINATIONS.md).
- [Rebuild history](verification/FOLDER-RECOVERY.md) and [check saved files](verification/SAVED-BACKUP-CHECK.md).
- [Restore-to-iPhone research](RESTORE-TO-IPHONE.md) — backlog, not a shipped feature.

## Developing and releasing

- [Development](DEVELOPMENT.md), [architecture](../ARCHITECTURE.md), [Apple APIs](APPLE_APIS.md).
- [Implementation plan](PLAN.md) — completed work and open acceptance gates.
- [Release process](RELEASE.md) — checks, dated builds, DMGs and distribution requirements.
- [Beta readiness audit](verification/BETA-2026-10-28.md).
- [Artwork](../assets/README.md) and [contributing](../CONTRIBUTING.md).

## Verification records

The [verification directory](verification/) separates automated checks, native UI inspection,
generated scale measurements and physical device evidence. Dated records describe what was
actually observed on that build; they do not imply later hardware or OS acceptance.

- [Keyboard, system accessibility, scale profiling and beta 20261029](verification/CLOSEOUT-2026-10-29.md)
- [Apple silicon, family Settings and Dock progress](verification/SILICON-SETTINGS-DOCK-2026-10-28.md)
- [Backup fix, mixed-media folders, Air site and beta 20261028.1](verification/BACKUP-FIX-AND-SITE-2026-10-28.md)
- [Family Air comparison and durable incomplete-backup details](verification/FAMILY-AIR-AND-HISTORY-2026-10-28.md)
- [Website development and deferred Cloudflare deployment](../apps/site/README.md)
