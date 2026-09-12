import Foundation
import ImageCaptureCore

/// Only transports a retained framework reference to the main queue. The reference is never read
/// off that queue, never published, and never used as a generally Sendable camera handle.
struct CaptureDeviceReference: @unchecked Sendable {
    private let storage: ICDevice

    init(_ device: ICDevice) { storage = device }

    @MainActor var device: ICDevice { storage }
}

/// Retains a callback batch until the main actor can normalize it; no framework properties are
/// inspected by the callback queue and these handles never leave DeviceCapture.
struct CaptureItemsReference: @unchecked Sendable {
    private let storage: [ICCameraItem]

    init(_ items: [ICCameraItem]) { storage = items }

    @MainActor var items: [ICCameraItem] { storage }
}

enum BrowserCallback: Sendable {
    case added(CaptureDeviceReference)
    case removed(ObjectIdentifier)
    case changed(CaptureDeviceReference)
}

final class CaptureBrowserDelegate: NSObject, ICDeviceBrowserDelegate {
    private let receive: @Sendable (BrowserCallback) -> Void

    init(receive: @escaping @Sendable (BrowserCallback) -> Void) {
        self.receive = receive
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        receive(.added(CaptureDeviceReference(device)))
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        receive(.removed(ObjectIdentifier(device)))
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, deviceDidChangeName device: ICDevice) {
        receive(.changed(CaptureDeviceReference(device)))
    }
}

struct CaptureError: Equatable, Sendable {
    let domain: String
    let code: Int
    let message: String

    init(_ error: any Error) {
        let error = error as NSError
        domain = error.domain
        code = error.code
        message = error.localizedDescription
    }
}

enum CameraCallback: Sendable {
    case opened(CaptureError?)
    case closed(CaptureError?)
    case ready
    case catalogReady
    case itemsAdded(CaptureItemsReference)
    case itemsRemoved(CaptureItemsReference)
    case itemsRenamed(CaptureItemsReference)
    case removed
    case accessChanged(restricted: Bool)
    case capabilitiesChanged
    case failed(CaptureError)

    static func encounteredError(_ error: (any Error)?) -> CameraCallback? {
        error.map { .failed(CaptureError($0)) }
    }
}

/// Framework entry points only forward events. No file metadata or thumbnails are requested.
final class CaptureCameraDelegate: NSObject, ICCameraDeviceDelegate {
    private let receive: @Sendable (CameraCallback) -> Void
    private let shouldGetThumbnail: @Sendable (ObjectIdentifier) -> Bool

    init(
        shouldGetThumbnail: @escaping @Sendable (ObjectIdentifier) -> Bool = { _ in false },
        receive: @escaping @Sendable (CameraCallback) -> Void
    ) {
        self.shouldGetThumbnail = shouldGetThumbnail
        self.receive = receive
    }

    func didRemove(_ device: ICDevice) { receive(.removed) }

    func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        receive(.opened(error.map(CaptureError.init)))
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        receive(.closed(error.map(CaptureError.init)))
    }

    func device(_ device: ICDevice, didEncounterError error: (any Error)?) {
        guard let callback = CameraCallback.encounteredError(error) else { return }
        receive(callback)
    }

    func deviceDidBecomeReady(_ device: ICDevice) { receive(.ready) }

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) { receive(.catalogReady) }

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) { receive(.accessChanged(restricted: false)) }

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) { receive(.accessChanged(restricted: true)) }

    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) { receive(.capabilitiesChanged) }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        receive(.itemsAdded(CaptureItemsReference(items)))
    }

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        receive(.itemsRemoved(CaptureItemsReference(items)))
    }

    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
        receive(.itemsRenamed(CaptureItemsReference(items)))
    }

    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    func cameraDevice(
        _ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?,
        for item: ICCameraItem, error: (any Error)?
    ) {}

    func cameraDevice(
        _ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?,
        for item: ICCameraItem, error: (any Error)?
    ) {}

    func cameraDevice(_ cameraDevice: ICCameraDevice, shouldGetThumbnailOf item: ICCameraItem) -> Bool {
        shouldGetThumbnail(ObjectIdentifier(item))
    }

    func cameraDevice(_ cameraDevice: ICCameraDevice, shouldGetMetadataOf item: ICCameraItem) -> Bool { false }
}
