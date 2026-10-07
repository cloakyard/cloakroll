# Backup activity and idle sleep — 7 October 2026

## Scope

CloakRoll holds a native Foundation user-initiated activity during original backup,
explicit saved-file checks and history rebuilding. A backup starts its activity after
the folder picker has returned and before folder access/registration. It retains it
through copying, verification, journal finalization, history refresh and lease cleanup.
Stop, source loss and deferred Quit do not release it ahead of outstanding work.

The activity is scoped to an asynchronous operation, with an unconditional `defer`
that ends exactly that operation's token. Overlapping operations own separate tokens.
Already-cancelled work does not acquire one. There is no post-operation cancellation
check in the wrapper: an already-committed recovery result remains successful.
Ordinary browsing and automatic history refresh do not request this activity.

The public API is [`ProcessInfo.beginActivity(options:reason:)`](https://developer.apple.com/documentation/foundation/processinfo/beginactivity(options:reason:)),
paired with [`endActivity(_:)`](https://developer.apple.com/documentation/foundation/processinfo/endactivity(_:)).
The macOS SDK and [ActivityOptions documentation](https://developer.apple.com/documentation/foundation/processinfo/activityoptions)
confirm that `.userInitiated` includes idle-system-sleep protection while leaving
display sleep enabled. Explicit Sleep, lid closure, disconnect and power loss remain
interruption cases; this is not a clamshell-mode or power-loss guarantee.

The compact glass bar retains its layout. Its existing Details popover adds a quiet
explanation, and native Help explains display sleep and keeping the lid open. Help's
folder-organization wording now also reflects the existing One Folder setting.

## Software verification

- **380 core and 186 hosted app tests pass.** Six new tests cover independent tokens,
  cancellation while work is suspended, pre-cancellation, source success/failure,
  no activity for an empty selection or dismissed picker, failed folder access,
  history saving and zero-transfer incremental verification.
- Existing Stop, deferred-Quit, saved-file-check and indexed/USB-recovery lifecycle
  tests now also assert token ownership and balanced release. Simulated late USB
  callbacks continue holding the activity until the callback settles.
- The actual production helper was compiled into an isolated local probe. During
  its asynchronous work, `pmset -g assertions` showed a `PreventUserIdleSystemSleep`
  assertion named `CloakRoll activity validation`; no display-sleep assertion was
  requested. After the operation returned, no matching assertion remained.
- Strict SwiftLint: zero violations in 130 files. Normal Debug and universal Release
  builds pass without compiler warnings. Existing hosted-test `linkd.autoShortcut`
  diagnostics remain non-failing.
- Release and installed-bundle audits pass signature, exact sandbox entitlements,
  hardened runtime, privacy manifests, icon and arm64/x86_64 checks. No entitlement,
  dependency or core-module change was needed.

The OS probe uses the production helper in a separate process; it is not a prolonged
sandboxed iPhone transfer or real sleep/wake acceptance. The tests use controlled
source callbacks and temporary local files, not physical iPhones.

## Installed preview and UI

Installed the audited, byte-identical universal Release as `/Applications/CloakRoll.app`.
Native About shows **0.1.0 (9) · Development preview**. Backup settings retain the
previous destination and **One Folder**. Previous installed and build app copies are
recoverable in Trash; backup originals, history and preferences were retained.

The installed Help sheet was inspected in the current light appearance: the added
section wraps correctly, the native scrollbar stays at the edge, scrolling reaches
all content, and Escape dismisses the sheet. The app was left in All Photos. No device
transfer was initiated. The new Details caption has build coverage; its live-transfer
visual check remains part of the deferred hardware pass.

Local archive: `apps/macos/build/releases/CloakRoll-0.1.0-9-local-universal.zip`.
SHA-256: `abf27eca450548e796d28acfe3680afae15977fc5565ecc84b6146a35c3f0f93`.
The archive passed ZIP integrity and isolated bundle checks. Nothing was published.

Logs: `/tmp/cloakroll-activity-{core,tests,lint,debug,release,native,audit,package,install}.log`.

## Deferred acceptance

Per the user's 7 October request, hardware validation follows software work. Include
a long backup with the app backgrounded and the display asleep, cancellation and
assertion release, plus explicit sleep/wake recovery in that final matrix. The existing
cable-removal, external-volume, two-physical-phone mapping, reconnect/thumbnail,
sustained performance, accessibility, older-OS and distribution gates remain open.
No full phase is promoted by this software stage.

## 7 October physical follow-up

The user subsequently resumed hardware testing. During an actual 18-video transfer
in the installed sandboxed build 9, ten OS samples observed the expected idle-system-
sleep assertion; the completed sample had no such assertion. The Details popover's
new guidance was inspected with real 64% progress and wrapped correctly. That batch
finished in 11.12 seconds, so prolonged background/display-sleep and interruption
behavior remain unaccepted. See [hardware evidence](HARDWARE-2026-10-07.md).
