import Foundation
import ImageCaptureCore

/// Only transports a retained framework reference to the main queue. The reference is never read
/// off that queue, never published, and never used as a generally Sendable camera handle.
struct CaptureDeviceReference: @unchecked Sendable {
    private let storage: ICDevice

    init(_ device: ICDevice) { storage = device }

    @MainActor var device: ICDevice { storage }
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
    case removed
    case accessChanged(restricted: Bool)
    case capabilitiesChanged
    case failed(CaptureError)

    static func encounteredError(_ error: (any Error)?) -> CameraCallback? {
        error.map { .failed(CaptureError($0)) }
    }
}

/// Framework entry points only forward immutable events. No file metadata or thumbnails are requested.
final class CaptureCameraDelegate: NSObject, ICCameraDeviceDelegate {
    private let receive: @Sendable (CameraCallback) -> Void

    init(receive: @escaping @Sendable (CameraCallback) -> Void) {
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

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) { receive(.ready) }

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) { receive(.accessChanged(restricted: false)) }

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) { receive(.accessChanged(restricted: true)) }

    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) { receive(.capabilitiesChanged) }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}

    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}

    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    func cameraDevice(
        _ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?,
        for item: ICCameraItem, error: (any Error)?
    ) {}

    func cameraDevice(
        _ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?,
        for item: ICCameraItem, error: (any Error)?
    ) {}

    func cameraDevice(_ cameraDevice: ICCameraDevice, shouldGetThumbnailOf item: ICCameraItem) -> Bool { false }

    func cameraDevice(_ cameraDevice: ICCameraDevice, shouldGetMetadataOf item: ICCameraItem) -> Bool { false }
}
