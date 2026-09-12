# Restore backed-up media to a new iPhone

Research recorded September 12, 2026. **Status: BACKLOG — no implementation, no committed phase,
and no iOS companion app planned.** This is the requested future feature: choose a folder of
backed-up photos and videos on the Mac, review the items, and copy selected originals into a new
iPhone's Photos library. It does not affect the V1 backup gates in [PLAN.md](PLAN.md).

The user's constraint is mandatory: the workflow must not require installing an extra app on the
iPhone; otherwise it stays in backlog. No phone writes, restores, permission requests, or transfer
experiments were performed for this research. Current device integration remains read/import only.

## Feasibility decision

No supported public API path was validated for a sandboxed Mac app to perform an additive,
transaction-aware import into a connected iPhone's Photos library without an iPhone app.
This is the research conclusion, not a claim that Apple can never provide such a capability.

ImageCaptureCore does have a historical `requestUploadFile` method and a camera receive-file
capability; saying the framework has no upload API would be incorrect. The method is deprecated
from macOS 14. Apple gives the reason: **“Sandbox restrictions prohibit writing directly to device
hardware.”** Its camera-upload description does not establish iPhone Photos import support.
It is unsuitable for CloakRoll's sandboxed architecture. Do not remove the sandbox, send custom
PTP writes, automate private mobile-device tools, or adopt undocumented protocols to work around
this boundary. [Apple: requestUploadFile](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestuploadfile%28_%3Aoptions%3Auploaddelegate%3Adiduploadselector%3Acontextinfo%3A%29)

The installed macOS 27 SDK confirms that deprecation and marks the method unavailable on iOS:
`System/Library/Frameworks/ImageCaptureCore.framework/Headers/ICCameraDevice.h`, lines 310–318,
under the selected Xcode SDK. The `canReceiveFile` capability is generic camera functionality,
not an iPhone compatibility or Photos-transaction guarantee.

## Native Apple workflows requiring no additional iPhone app

These are external, user-managed options. They do not establish a CloakRoll restore engine.

| Option | Documented capability | Boundary for CloakRoll |
| --- | --- | --- |
| Finder photo synchronization | Finder can synchronize photos and videos from a Mac folder or the Mac Photos library over USB when the user is not using iCloud Photos. | Changes track the selected Mac content; disabling synchronization removes synced content. This is not the proposed additive restore contract. CloakRoll must not drive it automatically or label it a verified restore. |
| Mac Photos, followed by a user-selected Apple transfer method | Photos on Mac can import media from a local folder or external drive. | Import creates content in the Mac's library. It is not a direct import into the attached phone. Using iCloud Photos would add cloud synchronization, outside the local restore concept. |
| System AirDrop sharing | AppKit exposes a public AirDrop sharing service for item-provider contents. | Candidate for separately evaluated user-assisted sharing of a small selection. It does not itself establish reliable whole-library migration, related-resource preservation, duplicate reconciliation, or a destination Photos commit receipt. No such behavior has been verified. |

Sources: [Finder photo synchronization](https://support.apple.com/en-ca/102375),
[importing local media into Mac Photos](https://support.apple.com/en-gb/guide/photos/phtae4e05c67/mac),
[AppKit AirDrop sharing service](https://developer.apple.com/documentation/appkit/nssharingservice/name/sendviaairdrop).

A documentation-only guide could point users to Apple's Finder instructions after explaining its
different semantics. No Finder settings, iCloud settings, existing albums, or phone content should
be changed by CloakRoll. Do not use AppleScript or accessibility automation as a replacement for
a supported restore API. A manual completion reported by the user is not machine verification.

Finder **File Sharing** is a different feature: it copies files into a compatible app's documents,
not directly into Photos. Building a receiver for it would require the extra iPhone app that the
user excluded. [Apple: Finder File Sharing](https://support.apple.com/en-ie/119585)

## PhotoKit research retained as a rejected dependency

PhotoKit's `PHAssetCreationRequest` can construct an asset from its underlying resources inside
a `PHPhotoLibrary` change block. Apple explicitly describes this resource-based interface as useful
for backup and restore. A request can add local resource files and supported metadata; errors arrive
after the change block executes. This is a public import mechanism **in the library available to
the running app**, not a Mac API that selects a remote iPhone as its destination. Using it on the
phone would require iPhone software and therefore does not satisfy the current constraint.
[Asset creation](https://developer.apple.com/documentation/photos/phassetcreationrequest),
[photo-library ownership](https://developer.apple.com/documentation/photos/phphotolibrary),
[file resource import](https://developer.apple.com/documentation/photos/phassetcreationrequest/addresource%28with%3Afileurl%3Aoptions%3A%29)

For reference only, an adding-only app would request `PHAccessLevel.addOnly` at the import action
and provide `NSPhotoLibraryAddUsageDescription`. That authorization does not permit general
inspection of existing library content. A read/write authorization has a broader privacy cost and
still must respect limited access. **Neither permission nor an iOS target is being added.**
[Access levels](https://developer.apple.com/documentation/photos/phaccesslevel),
[additions purpose string](https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryaddusagedescription)

For any later research, `supportsAssetResourceTypes` validates a proposed combination of resource
roles; successful preflight is not proof that the supplied media bytes will import successfully.
`PHAssetResourceCreationOptions` supports original filenames and copy-versus-move behavior. Keep
backup sources immutable; never transfer ownership of the only backup to an import API. Current
SDK conveniences must be availability-checked: `contentType` is iOS/macOS 26+, and
`originalResourceChoice` is iOS/macOS 27+.
[Resource preflight](https://developer.apple.com/documentation/photos/phassetcreationrequest/supportsassetresourcetypes%28_%3A%29),
[resource options](https://developer.apple.com/documentation/photos/phassetresourcecreationoptions)

Finder File Sharing and a paired, authenticated local-network receiver were considered as ways
to deliver files before a PhotoKit import. Both app-managed designs require iPhone software, so
neither is planned. A local-network receiver would also introduce permission, pairing, transport
security, background-lifecycle and entitlement work that the backup app does not need.
[Apple: local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

## Conditional product design if a qualifying API becomes available

The following requirements preserve the requested feature in the backlog. They are not an
implementation commitment, new module list, or authorization to write to a phone.

### Discover, inspect, select

1. Choose a backup folder with the standard macOS picker. Read within security-scoped access;
   do not mutate the backup, resolve paths outside it, or silently follow unrelated symbolic links.
2. Build an incremental inventory off the UI actor. Prefer a validated CloakRoll manifest and
   stored resource relationships when available. Treat any manifest as untrusted input and verify
   its relative paths, sizes and resource presence. For an ordinary folder, inspect actual media
   formats and metadata; do not assume every extension or filename is correct.
3. Display a lazy chronological grid, item and original-resource counts, selected bytes, dates,
   media kinds, and missing/unsupported components. Distinguish items that can be restored from
   items only available as separate files. Allow selection by item, date range and media type.
4. Identify the target phone independently of the old phone's backup identity. The user reviews
   the target, selected items, space requirements, expected handling of pairs and duplicate
   uncertainty before choosing **Copy to iPhone**. No operation starts on connection alone.
5. Preserve all source originals. No transcoding, photo edits, replacement of existing target
   items, phone deletion, or automatic two-way synchronization is included.

### Duplicate strategy and identity

Use logical asset identity plus a normalized set of resource roles, file sizes and cryptographic
digests for the selected backup inventory. Preserve source-device provenance separately from
target identity. A folder path or filename alone must never become an identity. Byte-identical
files may still be intentionally separate assets; show an explicit policy rather than silently
collapsing them.

For a future controlled import, store an operation ID, the target-library identity available through
the chosen API, resource evidence, and durable per-item completion receipts. A repeated request
may be skipped only when its same-target completion is sufficiently established. A historical
receipt does not prove the item still exists if the user later deleted it or replaced the library.

Do not promise global duplicate elimination. Existing device media may have been imported by
another app, edited, optimized, or exposed through limited APIs. Metadata resemblance is a possible
duplicate, not proof. If target evidence is unavailable, let the user skip an uncertain item or
explicitly retry with a duplicate risk. Never silently retry an unknown commit outcome.

### Transactions, progress and interruptions

A prospective state model is:

```text
discovered → selected → validated → transferring → staged → import requested
                                                          ↓
                               failed / outcome unknown / destination confirmed
```

Keep source validation, measured transport bytes, target import completion, and any later
read-back verification as separate evidence. Receiving bytes does not prove that Photos created
an asset, and a successful import receipt does not by itself prove every original can be read back
unchanged. Display the actual assurance level rather than a generic verified badge.

Use bounded per-asset transactions so a failed Live Photo component does not become a silently
successful still-photo restore. Keep all required components until the destination has accepted
the logical asset. Preflight available space with room for staging and system processing, while
treating disk-full errors as possible even after a check. Progress must show measured bytes and
completed item counts; an opaque system import step stays indeterminate.

Persist an import intent before submission and its completion evidence afterward. If the connection
or process ends between destination commit and local receipt, mark the item **outcome unknown**.
Reconcile using a supported target lookup or durable receipt if the API permits it. If it does not,
pause for an informed retry choice. Do not simulate exactly-once semantics with filename matching.

Pause/cancel stops new submissions and cancels only operations the API explicitly permits. A
submitted system change may complete after the request to stop; preserve that result. Cancellation
never rolls back by deleting target media. Source-drive loss, phone lock/disconnect, denied access,
full storage, app termination and unavailable target-library evidence all require distinct recorded
outcomes. A phone reconnect resumes incomplete work only after the target and source are checked.

### Resource and metadata fidelity

| Material | Required treatment and limits |
| --- | --- |
| HEIC/JPEG and ordinary video | Pass original resource bytes if supported; preserve known capture date and embedded metadata. Report unsupported media instead of silently converting it. A Photos import may generate derivatives; that is different from changing the saved backup. |
| Live Photos | Keep the still and matching motion resource together. Apple documents a single asset created from photo plus paired video. Matching basenames alone do not validate their embedded pairing information; missing or incompatible pairs require explicit handling. |
| RAW + rendered companion | Preserve both files and known roles. Supported resource combinations and original/rendered choice vary with OS capabilities; do not claim that every RAW type or pairing will behave identically. |
| Edits, sidecars and special modes | Generic USB originals may lack Photos adjustment history, slow-motion edit ranges, depth/portrait semantics, or other library-only information. Do not invent these from filenames or promise an identical edited appearance. Preserve unsupported sidecars in the backup. |
| Dates, time zones and filenames | Use recorded evidence, not the date the folder was copied. Unknown dates remain unknown. Preserve original filenames separately from collision-safe local backup names. Filesystem timestamps are not necessarily capture timestamps. |
| Albums, favorites, hidden state and people | A directory tree does not encode the old Photos library. This feature is selected-media restoration, not device migration or a full library-state restore. Do not reconstruct private album or person relationships from folders. |
| iCloud Photos | System Photos settings may subsequently synchronize imported items through iCloud. A local transfer cannot promise those items will never be uploaded by Apple's independently configured service. No cloud download or account integration is proposed. |

Sources for supported resource concepts:
[Live Photo creation](https://developer.apple.com/documentation/avfoundation/capturing-and-saving-live-photos),
[paired-video resource](https://developer.apple.com/documentation/photos/phassetresourcetype/pairedvideo),
[resource types](https://developer.apple.com/documentation/photos/phassetresourcetype).
The remaining cells state CloakRoll's proposed fidelity requirements and conservative limitations,
not a tested compatibility matrix.

## Conditions to promote the backlog item

All of these are required before adding an implementation phase:

- A documented public, sandbox-compatible approach works without an extra iPhone app. No private
  framework, direct undocumented USB/PTP protocol, external-app automation or sandbox removal.
- A physical-device prototype demonstrates additive creation without deleting or replacing existing
  target media, and distinguishes target import success from transport completion.
- A test matrix covers HEIC/JPEG, supported videos, valid/invalid Live Photo pairs, RAW companions,
  dates, orientation, iCloud-enabled devices and unavailable source components on supported OSes.
- Repeating and interrupting the same restore demonstrates conservative reconciliation; ambiguous
  outcomes are visible, and no unsupported guarantee of duplicate-free or exactly-once import is made.
- A library of realistic size has measured storage, memory, throughput, foreground/background and
  cancellation behavior. The original backup remains intact throughout.
- The plan is reviewed after the core backup work. If the only viable route still requires an iPhone
  app, the feature stays in backlog under the current user requirement.

The current outcome meets none of the hardware/import acceptance conditions. Only documentation
and public SDK declarations were inspected. Core backup development should continue in its
existing order; this research adds no release gate and no runtime dependency.
