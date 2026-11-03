# Nonphysical acceptance and beta preparation — 3 November 2026

The user requested completion of the remaining work except physical testing, confirmed that
the existing ad-hoc beta process should continue without a paid Apple developer account, and
confirmed that no additional macOS 26/clean test environment is available. Work stays on `dev`;
this authorizes the next GitHub prerelease and DMG, not a production website deployment.

## Keyboard and accessibility corrections

Native testing exposed two control-traversal defects: Backup Health's list skipped its action
row, and Saved Originals' list could not reach Preview/Reveal with Tab. Adding selection to
the latter enabled expansion but still skipped the inner buttons and introduced poor selected-row
contrast. The final implementation uses native grouped forms and disclosure controls. Saved
pages remain bounded to 60 items and thumbnail work retains its existing concurrency limit.
The abandoned list-selection state is removed.

Adjacent backup facts were also merged by the native form's accessibility representation,
omitting some field labels. The shared `BackupDetailValue` exposes each label/value separately
in Health, continuation and storage review. Preview/Reveal labels name the corresponding
original. Continuation and storage-review sheets have explicit default and Escape shortcuts.

With macOS keyboard navigation enabled temporarily, the actual generated-data app passed:

- Tab/Space into Health's Continue and Check Saved Files controls.
- Return into storage review, Escape back through both sheets, and restored invoking focus.
- Return to start a reviewed generated continuation: Health showed Completed, 3 of 3 originals.
- A read-only generated saved-file check reported 2 of 2 matching files.
- Tab/Space expands a saved item and opens Quick Look; the generated illustration rendered.
  Escape returned focus to Preview. Tab/Space on Reveal selected the generated original in Finder.
- Keyboard type-filter selection, capture-date toggle, dated empty state and restoration of all items.
- Light and dark native form presentation at the compact 860-point window width; all health
  actions fit and labels remain visible. AX inspection confirmed separate backup facts and
  individually exposed preview/reveal buttons.

Keyboard navigation was originally off and restored to off. The app's temporary dark override
was returned to System. No personal original was opened, transferred, modified or deleted.

## Real macOS local-notification check

Added **Send Test Notification** and **Check Test Delivery** to Notifications settings. The
test requires existing OS permission, never asks for it itself, and uses a separate identifier
without changing backup history or the reminder anchor. A fresh test removes its preceding
pending/delivered test. Disabling both opt-ins removes the test as well. Superseded operations
cannot publish a stale result. Delivery status deliberately distinguishes scheduling from
macOS-reported Notification Centre delivery; it does not assert that a banner was presented.

The real system client, not the generated-preview client, requested authorization. The macOS
permission prompt was accepted, Settings reported Allowed by macOS, and the test was scheduled
five seconds ahead. After switching to Finder and waiting, Check Test Delivery reported:
**“macOS reports the test in Notification Centre.”** This uses the public notification centre's
delivered-notifications API. Direct banner inspection timed out in the control tool, so visual
banner presentation is not claimed. No backup or iPhone connection was needed.

Completion notices and reminders were originally off and restored to off, removing the test.
macOS authorization is now allowed after this explicit test; app-level notifications remain opt-in.

## Verification and unresolved external acceptance

- 418 core and 246 hosted app tests passed: **664 Swift tests**. The new notification tests cover
  no unsolicited authorization, separate/private test content, reminder preservation, pending
  versus delivered status, replacing an old delivered test and disabling cleanup.
- Normal arm64 Debug build, strict SwiftLint across 167 files and `git diff --check` passed.
- The final clean-commit beta pipeline and packaged-app inspection passed as recorded below;
  no artifact is attributed to an uncommitted source revision.

VoiceOver's original off state was recorded, enabled, and restored to off. VoiceOver Utility
already had its caption panel enabled and that preference was left unchanged. The feedback
surface timed out again; no speech/caption output was observable. Full VoiceOver spoken-feedback
acceptance remains blocked by that observation limitation, rather than being inferred from AX.

Developer ID signing/notarization is deferred by the user's account decision. macOS 26 runtime
and clean-Mac acceptance are deferred because that environment is unavailable. The current host
is macOS 27.2/Xcode 27.2. Physical iPhone, removable-drive, sleep/wake and sustained real-library
checks remain the final stage in [FEATURE-TODO.md](../FEATURE-TODO.md). Restore-to-iPhone remains
the separate conditional backlog; it has no validated supported workflow under the existing
no-extra-iPhone-app constraint.

References: [Apple VoiceOver caption panels](https://support.apple.com/guide/voiceover/unac078/mac),
[Apple notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
Local ignored logs: `apps/macos/build/acceptance-*`.

## Final beta pipeline and publication

Ran `scripts/prepare_beta.sh --build 20261103` from the clean source commit
`ac275dbb4162063f2d5366065daa67c609c7677b`, which remained unchanged throughout every stage.
The pipeline passed all 418 core and 246 hosted tests, five release-tool regression tests,
strict lint across 167 files, fresh arm64 Debug/Release builds, the Release scale-probe build
and generated 10,000-item smoke check. The signed bundle passed architecture, minimum-OS,
entitlement, hardened-runtime, license and privacy-manifest checks. All 19 bundle entries
matched the read-only DMG; artwork, saved Finder layout, guide and Applications symlink checks passed.

The final DMG was mounted read-only. Finder's artwork, app/Applications items and Install Guide
were visually inspected. Navigating into it through the existing Finder window retained that
window's sidebar and required scrolling to see the guide/footer; the stored installer layout
was separately validated by the packaging tool. The packaged app launched directly from the
mounted image with no iPhone connected. About showed **0.1.0 (20261103) · Beta** and **Buy me a
coffee** with the destination `https://ko-fi.com/sumitsahoo21`. The app was quit and the volume
ejected; the installed app was not replaced.

| Artifact | Value |
| --- | --- |
| DMG | `CloakRoll-v0.1.0-beta.20261103.dmg` |
| Size | 6,905,017 bytes |
| SHA-256 | `a4e50990e4e03bc0c07a4c454b8fa195c4b3d858311f606569c39a0107e8165a` |
| Build environment | macOS 27.2; Xcode 27.2 (27B52); macOS 27.2 SDK |
| Distribution | arm64; macOS 26+; ad-hoc; not notarized |

Created a draft prerelease, uploaded the DMG and a public `SHA256SUMS.txt` containing only its
checksum, downloaded both assets and compared them byte-for-byte with the originals. Published
[v0.1.0-beta.20261103](https://github.com/cloakyard/cloakroll/releases/tag/v0.1.0-beta.20261103)
at 11:54:05 UTC on 3 November 2026. GitHub reports `isDraft: false`, `isPrerelease: true`, and the
tag resolves to the exact source commit above. The uploaded DMG's reported SHA-256 also matches.
Both published asset URLs were downloaded without authentication and again matched the local
DMG and checksum byte-for-byte.
Private local logs/manifests were not attached. GitHub Website checks and the Cloudflare dev
preview passed for the source commit; no production promotion or deployment was performed.

Local artifacts and individual stage logs remain under `apps/macos/build/Beta-0.1.0-20261103/`.
The build manifest's `published: false` records the packaging stage; publication is recorded here
without altering the tested artifacts. [PR #13](https://github.com/cloakyard/cloakroll/pull/13)
remains a draft from `dev` to `main` pending the explicit acceptance limits above.
