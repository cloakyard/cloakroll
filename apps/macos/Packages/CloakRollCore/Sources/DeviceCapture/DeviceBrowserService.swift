import Foundation
import ImageCaptureCore
import MediaModels
import OSLog

/// Owns ImageCaptureCore objects on the main actor and emits value-only connection/catalog state.
/// Enumeration reads supplied file properties; thumbnails are requested only by visible consumers.
@MainActor
public final class DeviceBrowserService: DeviceMediaSource, DeviceSelectionBrowsing, ThumbnailProviding, OriginalMediaDownloading {
    private let context: DeviceCaptureContext
    public let events: AsyncStream<DeviceEvent>
    public let catalogs: AsyncStream<DeviceMediaSnapshot>
    public var thumbnailDiagnostics: ThumbnailRequestDiagnostics { context.thumbnailDiagnostics }
    public var inventory: DeviceInventory { selection.inventory }
    public var selectedSessionID: UUID? { lifecycle.activeToken }
    public var selectedConnection: DeviceConnection { lifecycle.connection }
    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private let catalogContinuation: AsyncStream<DeviceMediaSnapshot>.Continuation
    private let catalog: CameraCatalog
    private let thumbnailPermissions = ThumbnailRequestPermissions()
    private let logger = Logger(subsystem: "com.cloakroll.core", category: "DeviceCapture")
    private var browser: ICDeviceBrowser?
    private var browserDelegate: CaptureBrowserDelegate?
    private var browserGeneration: UUID?
    private var camera: ICCameraDevice?
    private var cameraDelegate: CaptureCameraDelegate?
    private var candidates: [ObjectIdentifier: ICCameraDevice] = [:]
    private var selection = DeviceSelectionRegistry()
    private var lifecycle = DeviceLifecycle()
    private var lastPublished: DeviceConnection?
    private var lastInventory: DeviceInventory?
    private let makeBrowser: @MainActor () -> ICDeviceBrowser

    public convenience init(context: DeviceCaptureContext = DeviceCaptureContext()) {
        self.init(context: context, makeBrowser: { ICDeviceBrowser() })
    }

    init(context: DeviceCaptureContext, makeBrowser: @escaping @MainActor () -> ICDeviceBrowser) {
        self.context = context
        self.makeBrowser = makeBrowser
        let stream = AsyncStream<DeviceEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        events = stream.stream
        continuation = stream.continuation
        let catalogs = AsyncStream<DeviceMediaSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.catalogs = catalogs.stream
        catalogContinuation = catalogs.continuation
        catalog = CameraCatalog { catalogs.continuation.yield($0) }
    }

    public func start() {
        guard browser == nil else { return }
        let generation = UUID()
        browserGeneration = generation
        let delegate = CaptureBrowserDelegate { [weak self] event in
            DispatchQueue.main.async { self?.receive(event, generation: generation) }
        }
        let browser = makeBrowser()
        let mask = ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: mask) ?? .camera
        browser.delegate = delegate
        self.browser = browser
        browserDelegate = delegate
        context.originalDownloads.onSettled = { [weak self] in
            guard let self, browserGeneration == generation else { return }
            connectNextIfNeeded()
        }
        publishInventory()
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
        selection.reset()
        lifecycle.reset()
        publishInventory()
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

    @discardableResult
    public func selectDevice(id: UUID) -> Bool {
        guard browser != nil, let key = selection.key(for: id), candidates[key] != nil,
              selection.select(id, originalIsBusy: context.originalDownloads.isBusy) else { return false }
        if let camera, ObjectIdentifier(camera) == key { return true }
        retireCamera()
        connectNextIfNeeded()
        return true
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
            candidates[key] = discovered
            selection.upsert(key, name: displayName(discovered), productKind: discovered.productKind)
            connectNextIfNeeded()
            publishInventory()
        case .removed(let key):
            removeCandidate(key)
        }
    }

    private func connectNextIfNeeded() {
        guard browser != nil, camera == nil, !context.originalDownloads.isBusy,
              let identifier = selection.selectedID ?? selection.firstID,
              let key = selection.key(for: identifier), let selected = candidates[key],
              selection.select(identifier, originalIsBusy: false) else { return }
        let token = UUID()
        let identity = DeviceIdentityResolver.resolve(
            persistentID: selected.persistentIDString,
            serialNumber: selected.serialNumberString,
            uuid: selected.uuidString,
            sessionID: token
        )
        let value = ConnectedDevice(
            identity: identity, name: displayName(selected),
            productKind: selected.productKind
        )
        let delegate = CaptureCameraDelegate(
            shouldGetThumbnail: { [thumbnailPermissions] identifier in thumbnailPermissions.contains(identifier) },
            receive: { [weak self] event in
                DispatchQueue.main.async { self?.receive(event, token: token) }
            }
        )
        camera = selected
        cameraDelegate = delegate
        selected.delegate = delegate
        preferOriginals(selected)
        lifecycle.begin(device: value, token: token)
        publishInventory()
        context.thumbnailRequests.begin(sessionID: token)
        catalog.begin(
            sessionID: token, deviceID: value.id, percent: Int(selected.contentCatalogPercentCompleted),
            iCloudPhotosEnabled: selected.iCloudPhotosEnabled
        )
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
            if lifecycle.connection.state == .unavailable { catalog.interrupt(sessionID: token) }
        case .closed(let error):
            logDeviceError(error)
            catalog.interrupt(sessionID: token)
            lifecycle.closed(token: token, message: "The connection closed. Reconnect and unlock your iPhone, then try again.")
        case .ready:
            lifecycle.accessChanged(token: token, restricted: camera.isAccessRestrictedAppleDevice)
            lifecycle.ready(token: token)
        case .catalogReady:
            lifecycle.accessChanged(token: token, restricted: camera.isAccessRestrictedAppleDevice)
            lifecycle.ready(token: token)
            catalog.complete(
                (camera.contents ?? []) + (camera.mediaFiles ?? []), sessionID: token,
                percent: Int(camera.contentCatalogPercentCompleted), iCloudPhotosEnabled: camera.iCloudPhotosEnabled
            )
        case .itemsAdded(let reference), .itemsRenamed(let reference):
            catalog.add(
                reference.items, sessionID: token, percent: Int(camera.contentCatalogPercentCompleted),
                iCloudPhotosEnabled: camera.iCloudPhotosEnabled
            )
        case .itemsRemoved(let reference):
            catalog.remove(
                reference.items, sessionID: token, percent: Int(camera.contentCatalogPercentCompleted),
                iCloudPhotosEnabled: camera.iCloudPhotosEnabled
            )
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
            if lifecycle.connection.state == .unavailable { catalog.interrupt(sessionID: token) }
        }
        publish()
    }

    private func removeCandidate(_ key: ObjectIdentifier) {
        candidates[key] = nil
        selection.remove(key)
        guard let camera, ObjectIdentifier(camera) == key else { publishInventory(); return }
        retireCamera()
        publishInventory()
        publish()
        connectNextIfNeeded()
    }

    private func retireCamera() {
        // Invalidate the session token before a close can deliver any late events.
        if let token = lifecycle.activeToken {
            context.thumbnailRequests.retire(sessionID: token)
            context.originalDownloads.retire(sessionID: token)
            catalog.interrupt(sessionID: token)
        }
        lifecycle.reset()
        camera?.delegate = nil
        camera?.requestCloseSession()
        camera = nil
        cameraDelegate = nil
    }

    /// Resolves only current, readable source handles for explicit thumbnail or original requests.
    func catalogFile(for resourceID: String, sessionID: UUID) throws -> ICCameraFile {
        guard lifecycle.activeToken == sessionID else { throw MediaSourceError.staleSession }
        guard lifecycle.connection.state == .ready, camera?.hasOpenSession == true else {
            throw MediaSourceError.unavailable
        }
        return try catalog.file(for: resourceID, sessionID: sessionID)
    }

    public func thumbnailData(for resourceID: String, sessionID: UUID, maximumPixelSize: Int) async throws -> Data {
        // Validate before queuing and again when a physical slot becomes available.
        _ = try catalogFile(for: resourceID, sessionID: sessionID)
        let pixelSize = min(512, max(64, maximumPixelSize))
        return try await context.thumbnailRequests.data(sessionID: sessionID) { [weak self] completion in
            guard let self else { throw MediaSourceError.unavailable }
            let file = try catalogFile(for: resourceID, sessionID: sessionID)
            let identifier = ObjectIdentifier(file)
            let permissions = thumbnailPermissions
            permissions.insert(identifier)
            file.requestThumbnailData(options: [.imageSourceThumbnailMaxPixelSize: pixelSize]) { data, error in
                completion(ThumbnailResponse(data: data, error: error))
            }
            return {
                permissions.remove(identifier)
                // Keep the framework file alive on its actor until the real callback, even after
                // the catalog registry has retired. No source media or original data is accessed.
                withExtendedLifetime(file) {}
            }
        }
    }

    public func downloadOriginal(
        resourceID: String, sessionID: UUID, to directory: URL, filename: String,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadedOriginal {
        guard directory.isFileURL else { throw OriginalDownloadError.invalidDestination }
        guard OriginalDownloadPaths.isFilename(filename) else { throw OriginalDownloadError.invalidFilename }
        let result = try await context.originalDownloads.download(sessionID: sessionID, progress: progress) { [weak self] receive in
            guard let self else { throw MediaSourceError.unavailable }
            let file = try catalogFile(for: resourceID, sessionID: sessionID)
            guard let camera else { throw MediaSourceError.unavailable }
            if camera.capabilities.contains(ICDeviceCapability.cameraDeviceSupportsHEIF.rawValue),
               camera.mediaPresentation != .originalAssets {
                throw OriginalDownloadError.originalPresentationUnavailable
            }
            return OriginalDownloadOperation.start(camera: camera, file: file, directory: directory, filename: filename, receive: receive)
        }
        try Task.checkCancellation()
        _ = try catalogFile(for: resourceID, sessionID: sessionID)
        return result
    }

    private func preferOriginals(_ camera: ICCameraDevice) {
        if camera.capabilities.contains(ICDeviceCapability.cameraDeviceSupportsHEIF.rawValue),
           camera.mediaPresentation != .originalAssets {
            camera.mediaPresentation = .originalAssets
        }
    }

    private func displayName(_ camera: ICCameraDevice) -> String {
        let name = camera.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? "Apple mobile device"
    }

    private func publishInventory() {
        let value = selection.inventory
        guard lastInventory != value else { return }
        lastInventory = value
        continuation.yield(.inventoryChanged(value))
    }

    private func publish() {
        guard lastPublished != lifecycle.connection else { return }
        if let token = lifecycle.activeToken {
            switch lifecycle.connection.state {
            case .ready:
                context.thumbnailRequests.begin(sessionID: token)
                context.originalDownloads.begin(sessionID: token)
            case .restricted, .unavailable:
                context.thumbnailRequests.retire(sessionID: token)
                context.originalDownloads.retire(sessionID: token)
            case .disconnected, .opening:
                break
            }
        }
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
        catalogContinuation.finish()
    }
}
