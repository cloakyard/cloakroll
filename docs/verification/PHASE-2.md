# Phase 2 verification — 12 September 2026

Status: COMPLETE. Software and normal-sandbox physical disconnect/reconnect gate verified.

## Implemented

- A public ImageCaptureCore browser/session adapter, hidden behind `DeviceBrowsing` and immutable
  `DeviceEvent`/`DeviceConnection` values. The production filter requires Apple USB mobile product
  metadata; unrelated cameras and display-name-only matches are excluded.
- Explicit persistent/serial/UUID/session-only identity evidence. Framework handles remain internal.
- Normal app startup uses actual discovery; Debug samples remain isolated and explicitly labeled.
- Restricted/opening/ready/unavailable/removal handling with stale-session protection and retry.
- USB and Photos-library entitlements per Apple's framework guidance; no network entitlement.
- Original media presentation requested when supported. No explicit metadata, thumbnail or
  original-download request is made in Phase 2. Framework catalog enumeration occurs as part
  of session opening; the app does not publish media yet.

## Automated checks

- 56 headless core tests passed (33 foundation, 23 device/lifecycle/error tests).
- Four hosted AppModel tests passed: event mirroring, sample/live isolation, active range cursor,
  and query changes during a new sample source load.
- Normal Debug build succeeded without build warnings/errors. Strict SwiftLint passed.
- The first hosted-test configuration redundantly linked package products, producing an Xcode
  metadata extractor warning; removing those redundant test dependencies fixed it.
- System `com.apple.linkd.autoShortcut` connection diagnostics appear in test-host runtime logs;
  tests succeed and the app contains no AppIntents feature. These are not compiler warnings.
- After hosted tests, a normal `build` was run again. The inspected app signature contains only
  App Sandbox, USB, Photos library, and Debug get-task-allow. Xcode's temporary test-host filesystem
  and Mach exceptions are absent from this normal app build. Rebuild normally before manual QA.

## Real iPhone observations

- A physically attached iPhone was identified by the production filter with persistent identity
  evidence and its correct display name. Personal names/identifiers are not recorded here.
- The first hardware run uncovered an error: a passcode-restricted session reported errors,
  then successful unlock/readiness, but a terminal unavailable state ignored the recovery.
- Fixed that reducer behavior and added regression tests. Nil framework error callbacks are now
  ignored; actual error domain/code is diagnostic, while localized details remain private in logs.
- The corrected run observed `restricted → ready`; the UI displayed Connected. This observation
  preceded the final normal-build relaunch (the preceding hosted-test build had test permissions).
  The final normal-build launch is awaiting a fresh physical reconnect, so its full sandboxed
  hardware gate remains open. The public framework
  error `-9943` is `ICReturnDeviceIsPasscodeLocked` in the installed SDK. No delete/mutation API is used.
- The user was asked to unplug for roughly five seconds, reconnect and unlock the phone. A full
  real `ready → removed/no device → rediscovered/ready` sequence still needs to be recorded before
  declaring Phase 2 complete. Startup/session restart is not a substitute for physical removal.

## Remaining gate and limits

Confirm physical removal updates the live UI, then reconnect the same phone and confirm it is ready.
Until then Phase 3 is not started. First-ever Trust prompts, permission denial, multiple physical
phones and macOS 14 runtime behavior require separate hardware checks. Tests do not establish
original transfer, cloud completeness, backup integrity, Developer ID signing or notarization.

## Shutdown follow-up

Added an explicit main-actor applicationWillTerminate → AppModel.shutdown → browser.stop path.
A normal Quit was manually observed to emit Stopped camera discovery at 13:49:45. The new normal
build and strict lint pass. A privacy-safe notice now records whether a camera discovery callback
was accepted, without device names or identifiers, to distinguish missing callbacks from filtering.
No additional sandbox permissions were added. The app was reopened for the pending hardware check.

## Physical gate completed — 12 September 2026

The normal app process launched after the final non-test build was observed through the complete
physical cycle: ready at 13:57:37.012 → disconnected at 13:57:56.784 → camera rediscovered at
13:58:00.519 → access restricted → ready at 13:59:22.088. The live accessibility tree then showed
the correct iPhone name and Connected. Logs contain the same process ID through the cycle; app
restart was not substituted for physical removal. Personal identifiers are omitted here.

The app signature was inspected with only sandbox, USB, Photos Library and Debug get-task-allow
entitlements. No test-host temporary filesystem/Mach exceptions were present in that normal build.
A fresh validation reran all 56 core and 4 hosted app tests successfully, then restored the normal
app build; build completed without warnings/errors. The Phase 2 gate is now complete.

User-directed UI refinement is the next gate before Phase 3: toolbar sizing, sidebar density,
state hierarchy and light/dark/small-window visual checks, with a separate verified commit.
