# Per-iPhone backup folders — 5 October 2026

## Implemented behavior

Build **0.1.0 (8)** remembers a selected backup folder for each persistent iPhone identity.
Names are presentation only: identically named phones retain separate choices, and renaming
a phone does not discard its mapping. Session-only identities are remembered only during
the running process. Disconnect leaves the last folder visible for offline history; a new
unmapped phone is asked to choose its own folder.

On reconnect, the app resolves the saved security-scoped bookmark and checks the folder.
Unavailable or inaccessible folders remain remembered, with an explanation and a native
**Choose Folder…** action in the compact backup bar. Settings → Backup explains which
phone owns the choice. Every operation still acquires and validates its own access lease.

Versioned preferences publish the selection, all remembered bookmarks and device mappings
together. Switching folders and returning to the same original folder preserves the
destination UUID used by incremental history. Filesystem identity includes volume UUID,
inode and birth time when available; a different folder at the old path is rejected.
Matching never relies on a display path. Legacy bookmarks can be upgraded; an older
installation auto-associates a folder only when the current phone's completed history
points to a bookmark still retained by the app. Otherwise the user chooses explicitly.
Previously discarded bookmarks are not recreated from history paths.

Device changes invalidate pending picker and lease results. Cancellation or failed
preference saves preserve the prior choice. Unsupported/corrupt archives fail closed.
Remembered destination identity is not proof that the media is still present: incremental
reuse continues to require fresh size/SHA-256 validation of the actual originals.

## Automated verification

All **380 core and 180 hosted app tests** pass. Added coverage includes:

- A → B → relaunch → A/B folder identity recall; renaming a folder and replacing its old path.
- Two identically named phones with separate folders, phone renames, reconnect and session-only identity.
- Missing folders, stale/unresolvable bookmarks, failed persistence and a phone change while the picker is open.
- Exact-phone legacy migration and invalid archive versions, duplicate IDs and dangling mappings.
- Real temporary files and GRDB reopen: two phones use separate roots; a verified repeat transfers
  zero bytes; deleting one Live Photo companion copies only that missing component and preserves
  the other phone's status. These source devices are fixtures, not physical iPhones.

Strict SwiftLint reports zero violations in 129 files. Normal Debug and universal Release
builds pass, with no compiler warnings. The actual Release bundle and isolated ZIP pass
signature, hardened-runtime, sandbox/entitlement, architecture, privacy-manifest and archive
checks. Existing test-host `linkd.autoShortcut` diagnostics remain non-failing.

Logs: `/tmp/cloakroll-recall-core.log`, `/tmp/cloakroll-recall-tests.log`,
`/tmp/cloakroll-recall-debug.log`, `/tmp/cloakroll-recall-release.log`,
`/tmp/cloakroll-recall-lint.log`, `/tmp/cloakroll-recall-audit.log` and
`/tmp/cloakroll-recall-package.log`.

## Native and physical-device checks

The connected iPhone exposed **2,073 items**. Its chosen original destination was mapped
through the native Settings folder picker. A second, uniquely named empty test folder was
then selected. After quitting, removing only that empty test directory and relaunching,
the real phone was detected and its missing folder remained selected with **Needs attention**.
The library explained the unavailable folder, and the backup bar offered **Choose Folder…**.

That action opened the native picker. Selecting the original folder restored **Access checked**
and the backup action. A read-only preferences comparison confirmed its destination UUID
was identical before and after the switch/relaunch/restore sequence. Native Backup Settings
showed the device-specific caption and retained **One Folder** organization. The existing
compact glass bar and native grouped Settings surfaces were preserved.

An initial automation attempt sent the Go to Folder shortcut before observing the picker
and required an app relaunch. The repeated backup-bar flow above was completed successfully
after observing each native panel transition. No code workaround or phase acceptance is
inferred from the initial attempt.

No physical backup transfer or source-media modification was initiated in this stage.
The empty test directory was removed; the original destination was restored. Existing
backup originals and database history were retained.

## Limits and local package

Two-physical-phone switching, external-volume removal/remount, transfer cable interruption,
older-OS/Intel runtime, full accessibility and instrumented sustained scrolling remain
separate acceptance gates. The automated fixture tests do not close them. No public
distribution, notarization or whole-phase completion is claimed.

Local preview ZIP: `apps/macos/build/releases/CloakRoll-0.1.0-8-local-universal.zip`.
SHA-256: `c6fb1161ec6bfdbc9087357ee592601f35f175c9dacafc1f30a6c990d8d22eff`.

The byte-identical audited Release was installed at `/Applications/CloakRoll.app`.
Native About reports **0.1.0 (8) · Development preview**. On launch, the connected phone
again exposed 2,073 items and automatically restored its original destination with
**Access checked**. Backup Settings retained the per-phone caption and **One Folder**.
The installed bundle passes the Release audit. Superseded installed/build app copies
are recoverable in Trash; media, saved history and preferences were retained. The app
was left in All Photos. Install log: `/tmp/cloakroll-recall-install.log`.
