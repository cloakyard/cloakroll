import Foundation
import ImageCaptureCore
import MediaModels
import OSLog

/// Owns ImageCaptureCore objects on the main actor and emits value-only connection state.
/// Phase 2 opens sessions only: no metadata, thumbnail or original download requests.
@MainActor
public final class DeviceBrowserService: DeviceBrowsing {
    public let events: AsyncStream<DeviceEvent>
    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private let logger = Logger(subsystem: "com.cloakroll.core", category: "DeviceCapture")
    private var browser: ICDeviceBrowser?
    private var browserDelegate: CaptureBrowserDelegate?
    private var browserGeneration: UUID?
    private var camera: ICCameraDevice?
    private var cameraDelegate: CaptureCameraDelegate?
    private var candidates: [ObjectIdentifier: ICCameraDevice] = [:]
    private var candidateOrder: [ObjectIdentifier] = []
    private var lifecycle = DeviceLifecycle()
    private var lastPublished: DeviceConnection?

    public init() {
        let stream = AsyncStream<DeviceEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        events = stream.stream
        continuation = stream.continuation
    }

    public func start() {
        guard browser == nil else { return }
        let generation = UUID()
        browserGeneration = generation
        let delegate = CaptureBrowserDelegate { [weak self] event in
            DispatchQueue.main.async { self?.receive(event, generation: generation) }
        }
        let browser = ICDeviceBrowser()
        let mask = ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: mask) ?? .camera
        browser.delegate = delegate
        self.browser = browser
        browserDelegate = delegate
        publish()
        logger.info("Starting local camera discovery")
        browser.start()
    }

    public func stop() {
        browserGeneration = nil
        browser?.delegate = nil
        retireCamera()
        browser?.stop()
        browser = nil
        browserDelegate = nil
        candidates.removeAll()
        candidateOrder.removeAll()
        lifecycle.reset()
        publish()
        logger.info("Stopped camera discovery")
    }

    public func retry() {
        guard browser != nil else {
            start()
            return
        }
        stop()
        start()
    }

    private func receive(_ event: BrowserCallback, generation: UUID) {
        guard generation == browserGeneration else { return }
        switch event {
        case .added(let reference), .changed(let reference):
            guard let discovered = reference.device as? ICCameraDevice else { return }
            let key = ObjectIdentifier(discovered)
            let supported = DeviceClassification.isSupported(
                productKind: discovered.productKind,
                usbVendorID: Int(discovered.usbVendorID),
                transportType: discovered.transportType
            )
            logger.notice("Camera discovery callback; supported mobile device: \(supported, privacy: .public)")
            guard supported else { return }
            if candidates[key] == nil { candidateOrder.append(key) }
            candidates[key] = discovered
            connectNextIfNeeded()
        case .removed(let key):
            removeCandidate(key)
        }
    }

    private func connectNextIfNeeded() {
        guard camera == nil,
              let selected = candidateOrder.compactMap({ candidates[$0] }).first else { return }
        let token = UUID()
        let identity = DeviceIdentityResolver.resolve(
            persistentID: selected.persistentIDString,
            serialNumber: selected.serialNumberString,
            uuid: selected.uuidString,
            sessionID: token
        )
        let name = selected.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = ConnectedDevice(
            identity: identity,
            name: name.flatMap { $0.isEmpty ? nil : $0 } ?? "Apple mobile device",
            productKind: selected.productKind
        )
        let delegate = CaptureCameraDelegate { [weak self] event in
            DispatchQueue.main.async { self?.receive(event, token: token) }
        }
        camera = selected
        cameraDelegate = delegate
        selected.delegate = delegate
        preferOriginals(selected)
        lifecycle.begin(device: value, token: token)
        lifecycle.accessChanged(token: token, restricted: selected.isAccessRestrictedAppleDevice)
        publish()
        logger.info("Opening mobile camera session; identity kind: \(identity.kind.rawValue, privacy: .public)")
        selected.requestOpenSession()
    }

    private func receive(_ event: CameraCallback, token: UUID) {
        guard lifecycle.activeToken == token, let camera else { return }
        switch event {
        case .opened(let error):
            logDeviceError(error)
            let message = error.map { _ in
                "The device session could not open. Unlock your iPhone, reconnect it, then try again."
            }
            lifecycle.opened(token: token, errorMessage: message, restricted: camera.isAccessRestrictedAppleDevice)
        case .closed(let error):
            logDeviceError(error)
            lifecycle.failed(token: token, message: "The connection closed. Reconnect and unlock your iPhone, then try again.")
        case .ready:
            lifecycle.accessChanged(token: token, restricted: camera.isAccessRestrictedAppleDevice)
            lifecycle.ready(token: token)
        case .removed:
            removeCandidate(ObjectIdentifier(camera))
            return
        case .accessChanged(let restricted):
            lifecycle.accessChanged(token: token, restricted: restricted)
        case .capabilitiesChanged:
            preferOriginals(camera)
            lifecycle.accessChanged(token: token, restricted: camera.isAccessRestrictedAppleDevice)
        case .failed(let error):
            logDeviceError(error)
            lifecycle.failed(token: token, message: "The connection was interrupted. Reconnect and unlock your iPhone, then try again.")
        }
        publish()
    }

    private func removeCandidate(_ key: ObjectIdentifier) {
        candidates[key] = nil
        candidateOrder.removeAll { $0 == key }
        guard let camera, ObjectIdentifier(camera) == key else { return }
        if let token = lifecycle.activeToken { lifecycle.removed(token: token) }
        retireCamera()
        publish()
        connectNextIfNeeded()
    }

    private func retireCamera() {
        // Invalidate the session token before a close can deliver any late events.
        lifecycle.reset()
        camera?.delegate = nil
        camera?.requestCloseSession()
        camera = nil
        cameraDelegate = nil
    }

    private func preferOriginals(_ camera: ICCameraDevice) {
        if camera.capabilities.contains(ICDeviceCapability.cameraDeviceSupportsHEIF.rawValue),
           camera.mediaPresentation != .originalAssets {
            camera.mediaPresentation = .originalAssets
        }
    }

    private func publish() {
        guard lastPublished != lifecycle.connection else { return }
        lastPublished = lifecycle.connection
        continuation.yield(.stateChanged(lifecycle.connection))
        logger.info("Connection state: \(self.lifecycle.connection.state.rawValue, privacy: .public)")
    }

    private func logDeviceError(_ error: CaptureError?) {
        guard let error else { return }
        logger.error("Camera error domain: \(error.domain, privacy: .public), code: \(error.code, privacy: .public)")
        logger.error("Camera error detail: \(error.message, privacy: .private)")
    }

    deinit {
        continuation.finish()
    }
}
