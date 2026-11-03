# Next beta feature checklist

Requested 3 November 2026. Implement in the order below on `dev`. Software verification
and native UI checks precede physical device testing. A software check does not accept
an iPhone, removable-drive, sleep/wake or power-loss scenario.

| Order | Priority | Feature | Status |
| --- | --- | --- | --- |
| 1 | P0 | Backup health overview | Software checks passed; UI acceptance pending |
| 2 | P0 | Continue an unfinished backup after relaunch | In progress |
| 3 | P1 | Browse saved originals without an iPhone | Pending |
| 4 | P1 | Review storage and destination before a backup | Pending |
| 5 | P2 | Optional local notifications and backup reminders | Pending |
| 6 | P0 acceptance | Physical device and removable-drive testing | Deferred until all software stages |

## 1. Backup health

- [x] List remembered iPhones/destinations and their latest backup outcomes.
- [x] Persist the result/date of a completed saved-file integrity check; never invent an earlier check.
- [x] Distinguish historical completion, present file health, folder access and unknown USB coverage.
- [x] Provide Check Saved Files and a safe route to back up missing items.
- [ ] Verify database upgrades, empty/partial history and native light/dark/keyboard behavior.

## 2. Persistent continuation

- [ ] Preserve the original job selection and folder organization across relaunch.
- [ ] Match the same persistent phone, destination and unambiguous resource identities.
- [ ] Recheck completed originals and restart unfinished components; never imply byte-range resume.
- [ ] Explain unavailable/changed items and require explicit Continue; never start automatically.
- [ ] Test relaunch, changed identities, partial Live Photos and destination mismatches using isolated fixtures.

## 3. Saved-original browser

- [ ] Browse recorded local originals with date/type filters and bounded thumbnail loading.
- [ ] Preview and reveal originals while retaining read-only folder access.
- [ ] Distinguish an unavailable drive from missing media; reject unsafe paths and unrelated roots.
- [ ] Preserve companions and do not infer verification from a thumbnail or filename.
- [ ] Test paging, access lifetime, missing files and cancellation with generated local media.

## 4. Backup preview

- [ ] Show selection, original-component count, destination, estimated additional bytes and free capacity.
- [ ] Account for verified incremental reuse and companion files; make unknown capacity explicit.
- [ ] Revalidate source/destination before Start and retain per-file capacity protection.
- [ ] Test shortfall, changed selection/folder, partial reuse and arithmetic boundaries.

## 5. Local notifications

- [ ] Add opt-in completion/attention notifications and a configurable overdue-backup reminder.
- [ ] Ask for OS authorization only when enabled; show denied permission and allow retry.
- [ ] Keep names, filenames and paths out of notifications; no server, analytics or automatic uploads.
- [ ] Cancel obsolete reminders after successful backups or disabling the preference.
- [ ] Test scheduling/content with an injected notification client; inspect native Settings.

## 6. Physical acceptance — last

- [ ] Real iPhone disconnect/reconnect and relaunch continuation, including a partial Live Photo.
- [ ] External-drive removal/remount, full disk, replaced folder and restored access.
- [ ] Independent saved-file hashes after import/continuation and zero-transfer repeat.
- [ ] Sleep/wake, new captures, two physical phones and sustained large-library performance.
- [ ] Real OS notification delivery and real-library accessibility acceptance.

Developer ID/notarization and minimum-OS/clean-Mac acceptance remain separate release gates.
This checklist does not authorize publication, installation over the user's app or production deployment.
