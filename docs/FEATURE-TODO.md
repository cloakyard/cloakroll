# Next beta feature checklist

Requested 3 November 2026. Implement in the order below on `dev`. Software verification
and native UI checks precede physical device testing. A software check does not accept
an iPhone, removable-drive, sleep/wake or power-loss scenario.

| Order | Priority | Feature | Status |
| --- | --- | --- | --- |
| 1 | P0 | Backup health overview | Implemented; automated and generated-data UI checks passed |
| 2 | P0 | Continue an unfinished backup after relaunch | Implemented; automated and generated-data UI checks passed |
| 3 | P1 | Browse saved originals without an iPhone | Implemented; automated and generated-data UI checks passed |
| 4 | P1 | Review storage and destination before a backup | Implemented; automated and generated-data UI checks passed |
| 5 | P2 | Optional local notifications and backup reminders | Implemented; injected-client tests and Settings UI checks passed |
| 6 | P0 acceptance | Physical device and removable-drive testing | Final stage; pending available hardware |

Actual evidence and limits: [3 November audit](verification/NEXT-BETA-2026-11-03.md).
Implementation is complete; the physical and full accessibility gates below remain open.

Follow-up development: [unused-code and async-lifetime audit](verification/CODE-CLEANUP-2026-11-03.md).
This preserves physical testing as the final acceptance stage.

## 1. Backup health

- [x] List remembered iPhones/destinations and their latest backup outcomes.
- [x] Persist the result/date of a completed saved-file integrity check; never invent an earlier check.
- [x] Distinguish historical completion, present file health, folder access and unknown USB coverage.
- [x] Provide Check Saved Files and a safe route to back up missing items.
- [x] Verify database upgrades, empty/partial history and native light/dark compact presentation.

## 2. Persistent continuation

- [x] Preserve the original job selection and folder organization across relaunch.
- [x] Match the same persistent phone, destination and unambiguous resource identities.
- [x] Recheck completed originals and restart unfinished components; never imply byte-range resume.
- [x] Explain unavailable/changed items and require explicit Continue; never start automatically.
- [x] Test relaunch, changed identities, partial Live Photos and destination mismatches using isolated fixtures.

## 3. Saved-original browser

- [x] Browse recorded local originals with date/type filters and bounded thumbnail loading.
- [x] Preview and reveal originals while retaining read-only folder access.
- [x] Distinguish an unavailable drive from missing media; reject unsafe paths and unrelated roots.
- [x] Preserve companions and do not infer verification from a thumbnail or filename.
- [x] Test paging and unsafe/missing paths with generated local media; inspect native Quick Look and Escape dismissal.

## 4. Backup preview

- [x] Show selection, original-component count, destination, estimated additional bytes and free capacity.
- [x] Account for verified incremental reuse and companion files; make unknown capacity explicit.
- [x] Revalidate source/destination before Start and retain per-file capacity protection.
- [x] Test shortfall, changed selection/folder, partial reuse and arithmetic boundaries.

## 5. Local notifications

- [x] Add opt-in completion/attention notifications and a configurable overdue-backup reminder.
- [x] Ask for OS authorization only when enabled; show denied permission and allow retry.
- [x] Keep names, filenames and paths out of notifications; no server, analytics or automatic uploads.
- [x] Cancel obsolete reminders after successful backups or disabling the preference.
- [x] Test scheduling/content with an injected notification client; inspect native Settings.

## 6. Physical acceptance — last

- [ ] Real iPhone disconnect/reconnect and relaunch continuation, including a partial Live Photo.
- [ ] External-drive removal/remount, full disk, replaced folder and restored access.
- [ ] Independent saved-file hashes after import/continuation and zero-transfer repeat.
- [ ] Sleep/wake, new captures, two physical phones and sustained large-library performance.
- [ ] Real OS notification delivery and real-library accessibility acceptance.
- [ ] Complete keyboard/VoiceOver acceptance of the new list actions and sustained preview cancellation/access-lifetime checks.

Developer ID/notarization and minimum-OS/clean-Mac acceptance remain separate release gates.
This checklist does not authorize publication, installation over the user's app or production deployment.
