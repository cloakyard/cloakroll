# Multiple iPhones and device-organized backups

Date: 4 October 2026. This stage extends Phases 5–8. Physical two-phone switching and cable
removal remain separate acceptance checks from generated-source tests.

## Intended behavior

When multiple supported phones are discovered, the sidebar exposes a native menu picker.
Each choice has an opaque browser-local address; the backup database continues to use its
existing persistent device identity. Identical display names receive distinct menu labels.
Only one phone is browsed and backed up at a time. Switching is disabled during a backup or
folder selection, and the capture adapter independently rejects switching while a physical
original operation remains outstanding.

Accepted switches clear the previous selection, info, catalog projection, thumbnail session and
in-memory history before the new library becomes actionable. The current adapter session and
connection are authoritative when consuming independent event/catalog streams. A delayed old
catalog or completed background preparation cannot restore the previous phone's items.

New originals use `iPhone <stable token>/Year/Month`; unknown dates retain `Date Unknown`.
The token is the first 128 bits of a versioned SHA-256 derivation of the device key. Raw serial
numbers/device identifiers and mutable phone names are not used as filesystem components.
Renaming a persistently identified phone therefore leaves its folder unchanged. A phone without
persistent identity remains session-scoped and must not silently share another session's folder
or incremental history.

Existing verified files at legacy Year/Month paths remain eligible for fresh verification and
reuse. Nothing is moved, renamed or overwritten during this layout upgrade. Newly copied items
use the device folder, including a missing legacy original copied again. The added directory
layer uses the existing descriptor-based no-symlink publication checks and exact journal path.
Mixed-device selections fail before staging or source work. No migration, new entitlement,
network service, source mutation or restore-to-iPhone feature is introduced.

Settings and optional Help explain the folder organization and one-phone-at-a-time workflow.
The native picker follows Apple's recommendation to use pop-up selection for mutually exclusive
choices. It retains system interaction, keyboard and accessibility behavior rather than custom
menu chrome. [Apple pop-up button guidance](https://developer.apple.com/design/human-interface-guidelines/pop-up-buttons)

## Validation

All **305 core tests** and **93 hosted app tests** pass. The normal Debug rebuild, strict
SwiftLint, whitespace and actual signature/entitlement checks pass without compiler warnings.
Normal sandbox entitlements are unchanged after rebuilding without test-host additions.

Core coverage includes eleven new selection tests with controlled public-framework subclasses:
duplicate names and opaque IDs; repeated/current/unknown selection; selected and unselected
removal; fresh tokens; late old delegates; outstanding original cancellation and deferred fallback;
shared context across browser replacement; an unstarted replacement cannot steal the settlement
listener, and stopping an old browser cannot invalidate a newer started browser's listener.
The latter listener-ownership flaw was found in independent review and fixed before acceptance.

Folder tests verify different phones with identical names/runtime IDs, isolated missing-file
re-copy, legacy-path reuse, mixed-device rejection before I/O, exact prefixed journal recovery,
and symlink refusal. Hosted tests cover authoritative state across both stream orderings,
delayed old catalogs, rejected/current selection, busy/stopping backup guards, same-name labels,
sample retirement, and persistent two-phone reconnect/rename/missing-file isolation.

Actual normal-build hardware evidence: the first phone exposed 5,146 logical items / 9,077
resources. Its remaining legacy photo alone was marked backed up after cleanup. A selected
Live Photo copied two originals / **4,154,954 bytes** into its correct device folder. The phone
then disconnected while idle and another physical phone was discovered in the same app process.
The second exposed 2,071 logical items and correctly showed zero backed up after cleanup.
A selected photo copied **2,089,017 bytes** into a different device folder. Independent hashes
and device-key-derived path checks passed for both phones' new files.

A mixed selection on the second phone then verified three originals for two items, totaling
**9,450,889 bytes**, while transferring only the two new Live Photo components / **7,361,872 bytes**.
All four pre-existing test files remained unchanged. The identical two-item repeat verified
three originals and transferred **zero bytes**. This is actual sequential two-phone separation
and incremental reuse, not simultaneous connected-device picker acceptance.

Physical cable removal during an active transfer and simultaneous two-phone picker interaction
remain pending. The observed idle disconnect must not be counted as interruption acceptance.
Full accessibility variants and older-macOS runtime gates remain open. Real cleanup, Stop and
Quit evidence is recorded in [4 October hardware checks](OCTOBER-4-HARDWARE.md).

Local logs: `/tmp/cloakroll-multi-device-core-tests.log`,
`/tmp/cloakroll-multiple-phones-app-tests.log`, `/tmp/cloakroll-multiple-phones-normal-build.log`.
No private paths, device identifiers, filenames, personal screenshots or database exports are
committed with this evidence.

## Final refinement — check saved originals without reconnecting

The native Library menu now offers **Check Saved Originals** for an idle, complete live
library with a chosen destination. It performs the existing fresh local verification and updates
badges without downloading media or replacing the current selection/session. It is unavailable
during transfer, stopping, catalog/history preparation, folder selection, sample browsing and
offline/history views. A prior access error does not disable retry. History Refresh remains a
separate operation that reads recorded session outcomes.

Three additional hosted tests cover deletion while connected, overlapping command rejection,
selection/session preservation, disabled states, and failed folder access followed by recovery.
Review also found that an idle completed summary could linger when switching to another phone;
switching now dismisses that summary, while an active interrupted operation retains its outcome.
The selector test now proves the completed old-phone summary is cleared.

Actual final-command build: the second phone reappeared after normal relaunch with 2,071 items
and its two backed-up test items. All six remaining known test media files / **14,139,137 bytes**
were freshly matched to stored size and digest evidence, then removed as the final requested
space cleanup. **Check Saved Originals** changed Backed Up from two to zero and Not Backed Up
from 2,069 to 2,071 without reconnecting. The destination contains no media/staging files; the
sixteen historical sessions remain. Two cancelled staging intents remain conservative metadata,
not verified media or reusable files. Source iPhones were never modified.

Native Backup Settings displays `iPhone / Year / Month` without clipping. The revised Help sheet
was visually inspected, scrolled to its final guidance/actions and dismissed with Escape. General
Settings, System appearance, Medium size and the live All Photos view were restored. Simultaneous
chooser interaction, full VoiceOver/system appearance combinations and active cable-pull acceptance
remain open; the real Stop/Quit results do not substitute for them.

Final validation: **305 core tests and 96 hosted app tests pass**. The last hosted rerun includes
the idle-summary switch regression. The final normal build is warning-free; strict lint, diff,
signature and normal sandbox entitlement checks pass. No core source changed after its full run.
Final logs: `/tmp/cloakroll-check-originals-app-tests-final.log` and
`/tmp/cloakroll-check-originals-normal-build-final.log`.
