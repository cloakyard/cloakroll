# Apple API feasibility and platform constraints

Phase 0 research, verified September 12, 2026. This document separates public API and compile-time evidence from behavior that still requires a signed application and a physical iPhone.

## Evidence and deployment target

- Installed developer directory: `/Applications/Xcode.app/Contents/Developer`.
- Installed SDK: `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk`.
- Headers inspected: `System/Library/Frameworks/ImageCaptureCore.framework/Headers/ICDeviceBrowser.h`, `ICDevice.h`, `ICCameraDevice.h`, `ICCameraItem.h`, `ICCameraFile.h`, and `ImageCaptureConstants.h` beneath that SDK.
- A temporary, unexecuted Swift API probe passed `xcrun swiftc -typecheck -target arm64-apple-macosx14.0 /tmp/cloakroll-icc-api-check.swift`.
- No device APIs were executed as part of Phase 0. Successful typechecking against a current SDK with an older deployment target does not establish runtime behavior on macOS 14 or iPhone compatibility.

**macOS 14 is a viable baseline.** Discovery, sessions, asynchronous thumbnails, metadata, downloads, and original media presentation are available before macOS 14. `ICCameraFile.requestSecurityScopedURL(completion:)` is available on macOS 14, but applies to media on a mass-storage volume. The usual iPhone PTP transport is not a mounted filesystem. `requestFingerprint(completion:)` requires macOS 15 and must be guarded. See [ICCameraFile](https://developer.apple.com/documentation/imagecapturecore/iccamerafile) and [requestFingerprint(completion:)](https://developer.apple.com/documentation/imagecapturecore/iccamerafile/requestfingerprint%28completion%3A%29).

## Entitlements, permissions, and destination access

Apple's [ImageCaptureCore overview](https://developer.apple.com/documentation/imagecapturecore) explicitly requires `com.apple.security.device.usb` for sandboxed applications on macOS 14 and later. It also instructs macOS photo-import/tether applications to enable Hardened Runtime and the Photos Library entitlement.

| Setting or entitlement | Purpose and qualification |
| --- | --- |
| Hardened Runtime | Follow Apple's framework configuration instructions for the signed app. |
| `com.apple.security.app-sandbox` | Enable the app's sandbox. |
| `com.apple.security.device.usb` | Allow ImageCaptureCore access to USB devices on macOS 14+. |
| `com.apple.security.personal-information.photos-library` | Listed by Apple for macOS photo import/tethering; validate exact prompts for the signed importer. This does not mean CloakRoll should enumerate the Mac Photos library. |
| `com.apple.security.files.user-selected.read-write` | Allow writing to the folder selected with `NSOpenPanel`. |
| `com.apple.security.files.bookmarks.app-scope` | Persist security-scoped access to that destination between launches. |
| `NSPhotoLibraryUsageDescription` | Supply a meaningful purpose string when APIs/entitlements access the photo library. Apple's key documentation says it is required for library access. |

Resolve a saved bookmark with security scope, detect a stale bookmark, refresh it when possible, call `startAccessingSecurityScopedResource()` before using a resolved resource, and balance successful access with `stopAccessingSecurityScopedResource()`. Destination availability, writeability, and free space still need runtime checks. A bookmark does not guarantee an external disk is mounted.

Sources: [Sandbox entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html), [Enabling security-scoped bookmarks](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access), [Photos purpose string](https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryusagedescription).

The framework overview's `NSCameraUsageDescription` guidance specifically discusses **iOS tethering**. It does not establish that a native macOS USB importer must request `AVCaptureDevice` camera capture authorization. Do not introduce webcam, microphone, or broad filesystem permission requests without an applicable API requirement and observed need. Exact macOS privacy prompts remain signed-app/hardware validation work.

### Critical platform trap: browser authorization is unavailable on macOS

The installed `ICDeviceBrowser.h` marks all of these `IC_UNAVAILABLE(macos)`:

- `contentsAuthorizationStatus` and `requestContentsAuthorizationWithCompletion:`.
- `controlAuthorizationStatus` and `requestControlAuthorizationWithCompletion:`.
- Reset contents/control authorization methods.
- `ICAuthorizationStatusAuthorized`, `Denied`, `Restricted`, and `NotDetermined` constants.
- Browser suspension state and associated suspension delegates.

Some [Apple browser topic pages](https://developer.apple.com/documentation/imagecapturecore/icdevicebrowser) list these symbols without the platform distinction being clear in text extraction. Do not call them from the native macOS implementation or invent a macOS permission state from their iOS semantics. Represent actual access restrictions, session errors, and unavailable devices instead.

## Discovery and session lifecycle

Assign and retain the browser's delegate before calling `start()`. The header states that starting without a delegate is ignored. Browse camera-type devices at local locations and then inspect transport/classification; local devices are not necessarily iPhones.

The Swift mask expression passed typechecking:

```swift
browser.browsedDeviceTypeMask = ICDeviceTypeMask(
    rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
)!
```

Keep the browser, camera, and delegate alive for the connection. The browser supplies addition/removal callbacks, including `moreComing` and `moreGoing` hints when multiple devices change. Set the device delegate before requesting a session. `requestOpenSession()` completes through `device(_:didOpenSessionWithError:)`; `hasOpenSession` reports session state. Session opening is distinct from complete catalog readiness.

Relevant events and state:

| API/event | Interpretation |
| --- | --- |
| `deviceBrowser(_:didAdd:moreComing:)` | Device discovered; not proof that content is readable. |
| `deviceBrowser(_:didRemove:moreGoing:)` / `didRemove(_:)` | Device removed; invalidate connection-scoped handles and pending work. |
| `device(_:didOpenSessionWithError:)` | Session-open request finished. Inspect the error. |
| `cameraDevice(_:didAdd:)` | Incremental array of camera items arrived. |
| `cameraDevice(_:didRemove:)` | Items disappeared from the camera. |
| `contentCatalogPercentCompleted` | Catalog percentage, from 0 through 100. |
| `deviceDidBecomeReadyWithCompleteContentCatalog(_:)` | Complete content catalog is ready; a session must have been opened. |
| `device(_:didCloseSessionWithError:)` | Session closed or close failed. |
| `device(_:didEncounterError:)` | Surface the actual error and derive a recoverable state when justified. |
| `cameraDeviceDidChangeCapability(_:)` | Re-evaluate capabilities; they can change. |

`mediaFiles` is a flat view of image/movie/audio files. `contents` preserves reported storage/folder structure. A folder walk is useful for contextual identity and non-media companions; do not assume every item is an `ICCameraFile`. Process incremental batches into value records and coalesce UI updates. No documented configurable catalog batch-size or pagination API was found. Session option `.enumerationChronologicalOrder` is public, but it is not a batching control or a promise about globally sorted progressive UI data.

The headers explicitly say many callback-block APIs can execute on arbitrary available queues. Delegate APIs such as open/close and the item thumbnail/metadata delegates document main-thread callbacks. Preserve a consistent app isolation boundary and explicitly dispatch block results to it; avoid inferring one queue guarantee for the entire framework.

Sources: [ICDeviceBrowser](https://developer.apple.com/documentation/imagecapturecore/icdevicebrowser), [ICDevice](https://developer.apple.com/documentation/imagecapturecore/icdevice), [ICCameraDevice](https://developer.apple.com/documentation/imagecapturecore/iccameradevice), and the inspected SDK headers.

## iPhone identification and trust

There is no documented `isIPhone` property in the inspected public API. `usbVendorID`, `usbProductID`, `productKind`, `name`, and `transportType` provide evidence for classification, but a user-editable name containing “iPhone” is not a reliable identity. Unknown camera devices should not be silently treated as a known iPhone.

Public identity candidates are `persistentIDString`, `serialNumberString`, and Swift `uuidString`. These are nullable. Prefer a nonempty persistent identity when provided, store the identity kind, and validate reconnect stability on hardware. `usbLocationID` identifies USB location and must not be the persistent device key. `ptpObjectHandle` identifies an item within the transport; Apple does not promise that it remains stable across reconnects.

**Do not use `isLocked` as the iPhone trust signal.** The camera header documents it as deletion protection. `isAccessRestrictedAppleDevice` indicates an Apple device that is passcode-locked and connected to an untrusted host. `cameraDeviceDidEnableAccessRestriction(_:)` indicates media became unavailable; `cameraDeviceDidRemoveAccessRestriction(_:)` indicates the Apple device was unlocked, paired with the host, and media became available. Do not fabricate a more specific lock/trust diagnosis when only a generic connection error is available.

Sources: [ICDevice identity](https://developer.apple.com/documentation/imagecapturecore/icdevice), [Apple-device access restriction](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/isaccessrestrictedappledevice), and the SDK's `ICCameraDeviceDelegate` declarations.

## Original media presentation

The SDK documents converted HEIF-to-JPEG and HEVC-to-H.264 presentation as the default for capable devices. Set original presentation before enumeration/session opening when possible and re-evaluate capability changes. The following exact Swift names passed the macOS 14 deployment-target typecheck:

```swift
if camera.capabilities.contains(ICDeviceCapability.cameraDeviceSupportsHEIF.rawValue) {
    camera.mediaPresentation = .originalAssets
}
```

The imported `capabilities` collection contains strings, so compare the capability's `.rawValue`. The enum case is `.originalAssets`, not `.original`.

Original presentation still has limits: the header says burned-in renders are exported as JPEG and burned-in effects as MOV clips. It does not guarantee complete Photos asset history or that every asset resource is available through USB. Preserve the actual representation and filenames supplied by the device and label uncertain information honestly.

Sources: [mediaPresentation](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/mediapresentation), [ICMediaPresentation](https://developer.apple.com/documentation/imagecapturecore/icmediapresentation), and `ICCameraDevice.h`.

## Thumbnails and metadata

The modern block APIs are available since macOS 10.15:

```swift
file.requestThumbnailData(options: [.imageSourceThumbnailMaxPixelSize: 256]) { data, error in
    // Completion can run off the main thread.
}
file.requestMetadataDictionary(options: nil) { metadata, error in
    // Completion can run off the main thread.
}
```

Request thumbnails only for visible/prefetched items and use a bounded app-owned cache. The SDK discourages `.imageSourceShouldCache`: it overrides custom thumbnail sizing, framework caching is limited to embedded/standard EXIF thumbnails, and custom-size results are not cached. `flushThumbnailCache()` and `flushMetadataCache()` evict framework state.

For delegate-based requests, `cameraDevice(_:shouldGetThumbnailOf:)` and `cameraDevice(_:shouldGetMetadataOf:)` can reject requests that are no longer useful before they reach the device. Missing thumbnails or metadata are normal fallible outcomes and should not prevent a source file from being backed up.

Sources: [ICCameraFile request APIs](https://developer.apple.com/documentation/imagecapturecore/iccamerafile), [Metadata request filtering](https://developer.apple.com/documentation/imagecapturecore/iccameradevicedelegate/cameradevice%28_%3Ashouldgetmetadataof%3A%29), and `ICCameraItem.h`.

## Downloads, cancellation, and verification

The following API and option spellings passed typechecking:

```swift
let progress = file.requestDownload(options: [
    .downloadsDirectoryURL: stagingDirectory,
    .saveAsFilename: proposedFilename,
    .overwrite: false,
    .deleteAfterSuccessfulDownload: false,
    .sidecarFiles: false
]) { actualFilename, error in
    // Validate the result before recording a successful backup.
}
```

`requestDownload(options:completion:)` returns an optional `Progress`. `Progress.cancel()` can request cancellation; `camera.cancelDownload()` is documented to cancel the current download **if supported**. Neither cancellation request proves that all filesystem/device activity has already stopped. Wait for terminal results or retire the connection generation and keep staging isolated so a late callback cannot publish a cancelled transfer.

The delegate download API is also public. `ICCameraDeviceDownloadDelegate` supplies byte progress and completion options containing actual saved filenames; `ICSavedAncillaryFiles` can report companion files. The modern imported sidecar option is **`.sidecarFiles`**, not `.downloadSidecarFiles`. Explicit component downloads make per-resource verification tractable; if automatic sidecar downloads are enabled later, account for every returned ancillary file and avoid duplicate scheduling.

Download into an isolated staging directory on the selected destination volume, inspect the returned result, verify the final byte count and a streamed local cryptographic hash, then publish without overwriting. Treat a callback with no error as necessary but insufficient for claiming a durable verified backup. A destination SHA-256 records/verifies destination bytes; without a source digest it is not evidence of end-to-end source-byte equality.

Avoid `.truncateAfterSuccessfulDownload`: the header says it can strip padding from converted JPEGs without updating the camera item's `fileSize`, undermining a simple expected-size comparison. Original presentation also reduces conversion-related ambiguity. `requestReadData(atOffset:length:completion:)` is a public range-read facility but is not documented as persistent resumable-download support. Implement durable restart/resume at verified component boundaries unless stronger behavior is measured.

No delete-after-download, deletion API, clock synchronization, tethered capture, raw PTP command, or upload operation is needed for a read-only backup workflow.

Sources: [Download options](https://developer.apple.com/documentation/imagecapturecore/icdownloadoption), [Sidecar download option](https://developer.apple.com/documentation/imagecapturecore/icdownloadsidecarfiles), [Camera download APIs](https://developer.apple.com/documentation/imagecapturecore/iccameradevice), and `ICCameraItem.h` / `ICCameraFile.h`.

## On-demand camera EXIF in Media Info

`ICCameraFile.requestMetadataDictionary(options:completion:)` is public on macOS 10.15+,
including CloakRoll's macOS 14 baseline. Its completion may run on any queue. Normalize the
returned ImageIO `{Exif}` / `{TIFF}` dictionary into a Sendable value before crossing actors.
Use the optional `metadata` property only as a cache lookup; `metadataIfAvailable` can implicitly
request metadata and must not be used while enumerating the library.

The camera delegate denies metadata requests unless the exact framework file has an explicitly
pending Info request. A shared coordinator permits one physical metadata operation and eight
waiting callers. Cancellation, a 15-second caller deadline and session retirement release callers,
but retain the framework file and physical slot until the actual callback arrives. Stale sessions
and changed resource objects cannot publish results. No original-file download or conversion is
needed. Opening Info during a backup defers this optional request until the backup finishes.

Only camera make/model, lens, ISO, F-number, exposure time, focal length, 35 mm equivalent and
exposure bias are extracted. No GPS fields or raw metadata dictionaries are persisted. Absent
EXIF remains absent; numbers must be finite and physically positive except exposure bias,
where zero and negative values are valid. No APEX or filename-based guessing is used.

On 4 October 2026, the physical iPhone supplied all eight displayed camera fields for a Live
Photo via this API; a PNG supplied no camera fields and showed the quiet unavailable state.
See `verification/MEDIA-INFO.md` for actual validation and limits.

Sources: [requestMetadataDictionary](https://developer.apple.com/documentation/imagecapturecore/iccamerafile/requestmetadatadictionary%28options%3Acompletion%3A%29),
[metadata](https://developer.apple.com/documentation/imagecapturecore/iccameraitem/metadata),
[metadataIfAvailable](https://developer.apple.com/documentation/imagecapturecore/iccameraitem/metadataifavailable),
and [shouldGetMetadataOf](https://developer.apple.com/documentation/imagecapturecore/iccameradevicedelegate/cameradevice%28_%3Ashouldgetmetadataof%3A%29).

## Asset relationships and deduplication

Useful public relationship hints include:

| Property | Use and limitation |
| --- | --- |
| `sidecarFiles` | Associated files; may be absent. Inspect actual members rather than assuming exactly two. |
| `pairedRawImage` | RAW companion, a subset of sidecar relationships. |
| `groupUUID` | Group association when supplied. |
| `relatedUUID` | Related images/adjustment-sidecar association from Apple devices. |
| `originatingAssetID` | Originating asset identifier for applicable formats. |
| `burstUUID`, `burstFavorite`, `burstPicked`, `firstPicked` | Burst membership/selection hints; preserve members independently. |
| `originalFilename`, `createdFilename`, `name` | Naming evidence, not unique asset identity. |
| `fileSize`, dates, dimensions, duration | Candidate-match metadata and transfer expectations. |

Represent source components separately from logical photo groups. Prefer explicit supplied relationships, preserve ambiguous components, and never group solely by a repeated basename across the entire library. A Live Photo group is complete only when all required, discovered components have reached a verified terminal backup state; uncertainty should remain visible.

The macOS 15+ `requestFingerprint(completion:)` may provide an additional match signal. `fingerprint` and `fingerprintForFile(at:)` are also exposed in the current SDK, but the documentation does not promise a cryptographic algorithm or stability of its representation across OS versions. Do not equate Apple's fingerprint with SHA-256. Record its provenance and treat missing/failing fingerprints as optional evidence.

On macOS 14, metadata identity is a candidate match, not proof of content identity. Combine persistent device identity, resource relationship/context, original name, size, timestamps and representation; keep collision handling conservative and hash locally downloaded bytes. Do not use session-scoped object handles as durable deduplication keys.

Sources: [ICCameraFile](https://developer.apple.com/documentation/imagecapturecore/iccamerafile), [sidecarFiles](https://developer.apple.com/documentation/imagecapturecore/iccamerafile/sidecarfiles), [pairedRawImage](https://developer.apple.com/documentation/imagecapturecore/iccamerafile/pairedrawimage), [requestFingerprint(completion:)](https://developer.apple.com/documentation/imagecapturecore/iccamerafile/requestfingerprint%28completion%3A%29).

## iCloud and coverage limitations

`iCloudPhotosEnabled` only reports whether iCloud Photos is enabled. It does not establish that every original is resident or downloadable. The installed header repeats an unrelated access-restriction description for this property; Apple's dedicated [iCloudPhotosEnabled page](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/icloudphotosenabled) gives the correct meaning.

No public ImageCaptureCore API was found that forces an iCloud-only original to become resident or enumerates/counts assets omitted from USB presentation. Do not infer that every failed transfer is cloud-only, and do not report an unknown cloud-omission count as zero. The accurate scope is the device-accessible media exposed by the current session, with explicit unavailable/failed results.

Apple's [Image Capture guide](https://support.apple.com/guide/image-capture/welcome/mac) documents that, on macOS 15.4 and later, assets in a locked Hidden album are not imported. This is another reason a completed USB import is not proof of a complete iPhone Photos-library backup. Apple's [transfer guidance](https://support.apple.com/120267) also distinguishes iCloud synchronization from cable import, and documents required unlock/trust/accessory prompts.

## Hardware and release validation checklist

Every unchecked item below remains unverified. Mocks, compilation, and filesystem tests cannot close these checks.

- [ ] Signed sandboxed app on macOS 14: discover a supported physical iPhone and open a session.
- [ ] Signed app on newer macOS: repeat discovery/import and confirm no use of unavailable authorization methods.
- [ ] First connection: accessory permission, phone unlock, Trust This Computer, successful access restriction removal.
- [ ] Previously trusted but locked phone: observed access transitions and accurate recovery instructions.
- [ ] Denied/revoked permission or failed session: no fake “ready” state, app remains responsive, retry works.
- [ ] Reconnect the same phone, change ports/cables, restart the app and the phone: record which identifiers persist.
- [ ] Multiple attached camera devices and unknown devices: correct selection and no identity collision.
- [ ] A large library: progressive enumeration and responsive scrolling with bounded app thumbnail memory.
- [ ] HEIC, JPEG, PNG, HEVC/H.264 MOV/MP4, long/high-resolution video: original presentation, observed formats, size semantics, and readable output.
- [ ] Live Photos, edited Live Photos, RAW/JPEG or ProRAW companions, bursts, adjustments/sidecars: record actual relationship fields and component completeness.
- [ ] Filenames repeated across folders/assets, missing dates/IDs, unusual Unicode names: conservative identity and collision-safe destination paths.
- [ ] iCloud Photos with optimized storage: compare visible/importable resources with the phone library; record omissions and actual failure behavior without invented counts.
- [ ] Locked Hidden album on macOS 15.4+: confirm coverage explanation and observed omissions.
- [ ] Cancel and unplug during enumeration, thumbnails, an active large download, verification, and publication: no false success, safe staging, no source deletion.
- [ ] Device sleep/relock and Mac sleep/wake during a run: explicit interruption state and recoverable retry.
- [ ] Quit/crash and restart after a completed component: verified resources remain complete and unfinished resources retry safely.
- [ ] Select a destination with `NSOpenPanel`, relaunch using the bookmark, test stale/denied access and re-selection.
- [ ] External drive removed, disk full, destination read-only, filename conflict, and destination restored: no overwrite or false backup success.
- [ ] Re-run a completed backup and inspect the resulting manifest/destination: valid prior files are retained, changed/missing files are handled conservatively.
- [ ] Inspect the signed app's entitlements and actual privacy prompts; document the observed macOS/iOS/app build versions.

## Phase 0 conclusion

The public framework supports the required discovery, device-accessible media catalog, thumbnail, and download foundation on macOS 14. A robust implementation must own persistence, grouping, conservative deduplication, staging, verification, recovery, and destination authorization. The current evidence supports proceeding to implementation, with all hardware behavior and completeness claims limited as described above.
