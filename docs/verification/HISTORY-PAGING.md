# Backup history paging — 7 October 2026

Build 12 removes the 100-session browsing cutoff. Backup History shows at most 100
rows at once and offers native Newer/Older controls in a small bottom bar when more
than one page is available. The current page remains visible while loading. Page
changes start at the top; iPhone/result filters start a fresh first page; Refresh
returns to the latest matching backups. A one-page history has no pagination bar.

## Safety and bounded work

- SQL orders by stored `started_at DESC, id DESC`, with a cursor using the exact
  database Double and ID. It does not round the boundary through Foundation Date.
  Identical timestamps remain deterministic, and newly inserted sessions do not
  shift an existing older-page boundary as they would with an offset.
- Filters run before LIMIT. Cursors carry their filter; the store rejects reuse
  with a different filter. Queries fetch one extra row to establish whether an
  older page exists, without a full count. The public store caps requests at 200;
  the app requests 100 and retains only cursor positions for previous pages.
- Migration v6 replaces the single-column time index with ordered time/ID and
  device/time/ID indexes. Existing original-file evidence is untouched.
- A failed page retains the last successful rows and navigation position. Try Again
  retries that page, including a failed refresh. Newer requests/filter changes fence
  older successes and errors; cancellation cannot publish rows. An older page that
  becomes empty after sessions leave an outcome filter reloads the latest results.
- Navigation does not acquire a destination lease, enumerate iPhone originals,
  mark anything verified, or modify a backup's recorded result.

## Automated checks

All **390 core tests and 205 hosted app tests** pass. New checks cover empty, exact
100-row and partial page boundaries; all 201 records visited once; tied and fractional
timestamps; a newly inserted backup between pages; combined filter boundaries and
incompatible cursors; extreme requested limits; preserved upgrade rows; ordered query
plans without a temporary sort on a 1,005-session fixture; forward/back/refresh; failed
navigation and exact retry; stale success/error after filtering; cancellation; and
an older page becoming empty. The real-store hosted test now visits the 101st entry
and returns to the latest 100, independently of device discovery.

Earlier v1/v2/v4 migration tests were updated to recreate their actual pre-v6 index
schema, and all existing publication, recovery, verification and incremental tests pass.
Final normal Debug and universal Release builds have no compiler warnings. Strict lint,
whitespace checks, actual Release/installed-bundle audits and ZIP validation pass.
The hosted test process still emits the known `linkd.autoShortcut` service diagnostics;
these did not fail a test or appear as compiler warnings.

## Native UI and existing data

The Debug-only **Development → Sample Backup History · 205 Sessions** opens an isolated
temporary database/window using the production list and paging controller. It never
writes sample sessions into the user's history or downloads originals. Native review
confirmed first-page rows 205–106, second-page starting at 105, final rows 5–1, disabled
forward navigation at the end, backwards navigation, scroll reset after scrolling,
and Unfinished filtering from an older page returning to page 1. The footer stayed
visible, with accessible Newer Backups/Older Backups names, in light and dark appearance.
The preview window was 720 points wide; the regular app's real history was also checked
in the compact 860-point dark layout.

The existing real database migrated successfully (`PRAGMA integrity_check`: `ok`).
Read-only before/after row digests matched for all 32 backup sessions, 18,229 verified
records, 18,193 journal rows, 18,232 session-resource rows, 5,173 assets, 9,110 resources
and 10 recovery-import rows. Real history still displayed both previously used iPhones
and their original outcomes. No physical transfer was started during these checks.

Installed the byte-identical audited **0.1.0 (12)** at `/Applications/CloakRoll.app`.
About shows build 12; saved history loaded before device discovery completed. The
2,078-item iPhone library then returned, along with its last backup details and the
regular folder's Access checked state. Left All Photos at the top with no selection.
Superseded installed/Debug/Release app bundles are recoverable in Trash. Existing
originals, history and preferences remain. This does not close cable/external-volume,
multiple-physical-device, sustained performance, full accessibility/macOS 14 runtime
or distribution acceptance; see [the release checklist](../RELEASE.md).

## Local artifact and logs

Archive: `apps/macos/build/releases/CloakRoll-0.1.0-12-local-universal.zip`.
SHA-256: `a11b16f361ef2b6b8542ca590023bb185324901122ff7088ddb801191eab45f3`.

Local logs: `/tmp/cloakroll-history-core.log`, `/tmp/cloakroll-history-app.log`,
`/tmp/cloakroll-history-debug.log`, `/tmp/cloakroll-history-release.log`,
`/tmp/cloakroll-history-lint.log`, `/tmp/cloakroll-history-package.log`.
Before/after row digests: `/tmp/cloakroll-history-before.json` and
`/tmp/cloakroll-history-after.json` (local, not committed).
