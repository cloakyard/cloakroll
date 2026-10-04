import Foundation
import ImageCaptureCore
import MediaModels
import Testing
@testable import DeviceCapture

@Suite("Multiple device selection", .timeLimit(.minutes(1)))
@MainActor
struct DeviceSelectionTests {
    @Test func identicalNamesHaveDistinctOpaqueAddressesAndOnlyOneSessionOpens() async throws {
        let fixture = SelectionFixture()
        defer { fixture.service.stop() }
        fixture.service.start()
        try await selectionWait { fixture.service.inventory.devices.count == 2 }
        let inventory = fixture.service.inventory
        #expect(inventory.devices.map(\.displayName) == ["iPhone", "iPhone"])
        #expect(Set(inventory.devices.map(\.id)).count == 2)
        #expect(inventory.selectedID == inventory.devices.first?.id)
        #expect(fixture.first.openCount == 1 && fixture.second.openCount == 0)
        #expect(fixture.service.selectedConnection.device?.id == "persistent:phone-a")
        #expect(fixture.service.selectedSessionID != nil)
        #expect(inventory.devices.allSatisfy { $0.id.uuidString != "phone-a" && $0.id.uuidString != "phone-b" })
    }

    @Test func explicitSwitchUsesFreshSessionAndRetainsPersistentDeviceIdentity() async throws {
        let fixture = SelectionFixture()
        defer { fixture.service.stop() }
        fixture.service.start()
        try await selectionWait { fixture.service.inventory.devices.count == 2 }
        let initial = fixture.service.inventory
        let firstID = try #require(initial.selectedID)
        let secondID = initial.devices[1].id
        let initialSession = fixture.service.selectedSessionID
        #expect(!fixture.service.selectDevice(id: UUID()))
        #expect(fixture.service.selectDevice(id: firstID))
        #expect(fixture.first.openCount == 1 && fixture.first.closeCount == 0)
        #expect(fixture.service.selectDevice(id: secondID))
        #expect(fixture.first.closeCount == 1 && fixture.second.openCount == 1)
        #expect(fixture.service.inventory.selectedID == secondID)
        #expect(fixture.service.selectedConnection.device?.id == "persistent:phone-b")
        #expect(fixture.service.selectedSessionID != initialSession)
        let secondSession = fixture.service.selectedSessionID
        #expect(fixture.service.selectDevice(id: firstID))
        #expect(fixture.second.closeCount == 1 && fixture.first.openCount == 2)
        #expect(fixture.service.selectedConnection.device?.id == "persistent:phone-a")
        #expect(fixture.service.selectedSessionID != initialSession && fixture.service.selectedSessionID != secondSession)
        #expect(fixture.service.inventory.devices.map(\.id) == initial.devices.map(\.id))
    }

    @Test func renamePreservesSelectionAddressAndUnrelatedCameraIsExcluded() async throws {
        let fixture = SelectionFixture()
        defer { fixture.service.stop() }
        fixture.service.start()
        try await selectionWait { fixture.service.inventory.devices.count == 2 }
        let original = fixture.service.inventory.devices[1].id
        fixture.second.suppliedName = "Renamed phone"
        fixture.browser.rename(fixture.second)
        let unrelated = SelectionCamera(identity: "unrelated", product: "Camera")
        fixture.browser.add(unrelated)
        try await selectionWait { fixture.service.inventory.devices.last?.displayName == "Renamed phone" }
        #expect(fixture.service.inventory.devices.count == 2)
        #expect(fixture.service.inventory.devices.last?.id == original)
        #expect(unrelated.openCount == 0)
    }

    @Test func lateCallbacksFromThePreviousCameraCannotChangeSelectedConnection() async throws {
        let fixture = SelectionFixture()
        defer { fixture.service.stop() }
        fixture.service.start()
        try await selectionWait { fixture.service.inventory.devices.count == 2 }
        let oldDelegate = try #require(fixture.first.delegate as? CaptureCameraDelegate)
        let secondID = fixture.service.inventory.devices[1].id
        #expect(fixture.service.selectDevice(id: secondID))
        let session = fixture.service.selectedSessionID
        let connection = fixture.service.selectedConnection
        oldDelegate.deviceDidBecomeReady(fixture.first)
        oldDelegate.device(fixture.first, didOpenSessionWithError: nil)
        oldDelegate.cameraDeviceDidEnableAccessRestriction(fixture.first)
        oldDelegate.device(fixture.first, didCloseSessionWithError: nil)
        oldDelegate.didRemove(fixture.first)
        // The forwarding delegates enqueue to the main queue; wait behind those exact callbacks.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(fixture.service.selectedSessionID == session)
        #expect(fixture.service.selectedConnection == connection)
        #expect(fixture.service.inventory.selectedID == secondID && fixture.service.inventory.devices.count == 2)
        #expect(fixture.second.openCount == 1 && fixture.second.closeCount == 0)
    }

    @Test func removingAnInactivePhoneKeepsActiveSessionAndRejectsItsOldAddress() async throws {
        let fixture = SelectionFixture()
        defer { fixture.service.stop() }
        fixture.service.start()
        try await selectionWait { fixture.service.inventory.devices.count == 2 }
        let removed = fixture.service.inventory.devices[1].id
        let session = fixture.service.selectedSessionID
        fixture.browser.remove(fixture.second)
        try await selectionWait { fixture.service.inventory.devices.count == 1 }
        #expect(!fixture.service.selectDevice(id: removed))
        #expect(fixture.service.selectedSessionID == session)
        #expect(fixture.first.openCount == 1 && fixture.first.closeCount == 0)
        fixture.browser.add(fixture.second)
        try await selectionWait { fixture.service.inventory.devices.count == 2 }
        #expect(fixture.service.inventory.devices[1].id != removed)
    }

    @Test func stopResetsInventoryAndQueuedOldDiscoveryCannotReviveIt() async throws {
        let fixture = SelectionFixture()
        fixture.service.start()
        try await selectionWait { fixture.service.inventory.devices.count == 2 }
        let previous = fixture.service.inventory.devices.map(\.id)
        fixture.browser.add(SelectionCamera(identity: "late"))
        fixture.service.stop()
        await Task.yield()
        #expect(fixture.service.inventory == DeviceInventory())
        #expect(fixture.service.selectedSessionID == nil)
        #expect(fixture.service.selectedConnection.state == .disconnected)
        #expect(!fixture.service.selectDevice(id: previous[0]))
        fixture.service.start()
        defer { fixture.service.stop() }
        try await selectionWait { fixture.service.inventory.devices.count == 2 }
        #expect(Set(fixture.service.inventory.devices.map(\.id)).isDisjoint(with: previous))
    }

    @Test func switchingWaitsForCancelledPhysicalOriginalAndCleanup() async throws {
        let fixture = SelectionFixture()
        defer { fixture.service.stop() }
        fixture.service.start()
        try await selectionWait { fixture.service.inventory.devices.count == 2 }
        let secondID = fixture.service.inventory.devices[1].id
        let token = try #require(fixture.service.selectedSessionID)
        let operation = SelectionOriginal()
        fixture.context.originalDownloads.begin(sessionID: token)
        let request = Task {
            try await fixture.context.originalDownloads.download(sessionID: token, progress: { _ in }, operation: operation.start)
        }
        try await selectionWait { operation.callback != nil }
        #expect(!fixture.service.selectDevice(id: secondID))
        request.cancel()
        try await selectionWait { operation.cancelCount == 1 }
        #expect(!fixture.service.selectDevice(id: secondID))
        #expect(fixture.second.openCount == 0 && fixture.first.closeCount == 0 && operation.cleanupCount == 0)
        operation.finish()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(operation.cleanupCount == 1)
        #expect(fixture.service.selectDevice(id: secondID))
        #expect(fixture.second.openCount == 1)
    }

    @Test func automaticFallbackWaitsForRemovedPhonesActualCallback() async throws {
        let fixture = SelectionFixture()
        defer { fixture.service.stop() }
        fixture.service.start()
        try await selectionWait { fixture.service.inventory.devices.count == 2 }
        let token = try #require(fixture.service.selectedSessionID)
        let operation = SelectionOriginal()
        fixture.context.originalDownloads.begin(sessionID: token)
        let request = Task {
            try await fixture.context.originalDownloads.download(sessionID: token, progress: { _ in }, operation: operation.start)
        }
        try await selectionWait { operation.callback != nil }
        fixture.browser.remove(fixture.first)
        try await selectionWait { fixture.service.inventory.devices.count == 1 }
        #expect(fixture.service.inventory.selectedID == nil && fixture.service.selectedSessionID == nil)
        #expect(fixture.service.selectedConnection.state == .disconnected)
        #expect(fixture.second.openCount == 0 && operation.cleanupCount == 0 && operation.cancelCount == 1)
        let remainingID = try #require(fixture.service.inventory.devices.first?.id)
        #expect(!fixture.service.selectDevice(id: remainingID))
        operation.finish()
        await #expect(throws: MediaSourceError.staleSession) { try await request.value }
        try await selectionWait { fixture.second.openCount == 1 }
        #expect(operation.cleanupCount == 1)
        #expect(fixture.service.inventory.selectedID == remainingID)
        #expect(fixture.service.selectedConnection.device?.id == "persistent:phone-b")
    }

    @Test func replacementBrowserResumesOnlyAfterSharedPhysicalSlotSettles() async throws {
        let old = SelectionFixture()
        old.service.start()
        try await selectionWait { old.service.inventory.devices.count == 2 }
        let token = try #require(old.service.selectedSessionID)
        let operation = SelectionOriginal()
        old.context.originalDownloads.begin(sessionID: token)
        let request = Task {
            try await old.context.originalDownloads.download(sessionID: token, progress: { _ in }, operation: operation.start)
        }
        try await selectionWait { operation.callback != nil }
        old.service.stop()
        let replacement = SelectionFixture(context: old.context)
        replacement.service.start()
        defer { replacement.service.stop() }
        try await selectionWait { replacement.service.inventory.devices.count == 2 }
        #expect(replacement.service.inventory.selectedID == nil)
        #expect(replacement.first.openCount == 0 && operation.cleanupCount == 0)
        operation.finish()
        await #expect(throws: MediaSourceError.staleSession) { try await request.value }
        try await selectionWait { replacement.first.openCount == 1 }
        #expect(operation.cleanupCount == 1 && old.first.openCount == 1)
        #expect(replacement.service.selectedSessionID != token)
    }

    @Test func unstartedBrowserCannotStealAnActiveBrowsersDeferredSelection() async throws {
        let current = SelectionFixture()
        current.service.start()
        defer { current.service.stop() }
        try await selectionWait { current.service.inventory.devices.count == 2 }
        let token = try #require(current.service.selectedSessionID)
        let operation = SelectionOriginal()
        current.context.originalDownloads.begin(sessionID: token)
        let request = Task {
            try await current.context.originalDownloads.download(sessionID: token, progress: { _ in }, operation: operation.start)
        }
        try await selectionWait { operation.callback != nil }
        current.browser.remove(current.first)
        try await selectionWait { current.service.inventory.selectedID == nil }
        let unused = SelectionFixture(context: current.context)
        #expect(unused.service.inventory.devices.isEmpty)
        operation.finish()
        await #expect(throws: MediaSourceError.staleSession) { try await request.value }
        try await selectionWait { current.second.openCount == 1 }
        #expect(unused.first.openCount == 0 && operation.cleanupCount == 1)
    }

    @Test func stoppingAnOlderBrowserCannotClearTheNewBrowsersSettlementListener() async throws {
        let old = SelectionFixture()
        old.service.start()
        try await selectionWait { old.service.inventory.devices.count == 2 }
        let token = try #require(old.service.selectedSessionID)
        let operation = SelectionOriginal()
        old.context.originalDownloads.begin(sessionID: token)
        let request = Task {
            try await old.context.originalDownloads.download(sessionID: token, progress: { _ in }, operation: operation.start)
        }
        try await selectionWait { operation.callback != nil }
        let current = SelectionFixture(context: old.context)
        current.service.start()
        defer { current.service.stop() }
        try await selectionWait { current.service.inventory.devices.count == 2 }
        old.service.stop()
        #expect(current.first.openCount == 0)
        operation.finish()
        await #expect(throws: MediaSourceError.staleSession) { try await request.value }
        try await selectionWait { current.first.openCount == 1 }
        #expect(old.first.openCount == 1 && operation.cleanupCount == 1)
    }
}

@MainActor
private final class SelectionFixture {
    let first = SelectionCamera(identity: "phone-a")
    let second = SelectionCamera(identity: "phone-b")
    let context: DeviceCaptureContext
    let browser: SelectionBrowser
    let service: DeviceBrowserService

    init(context: DeviceCaptureContext = DeviceCaptureContext()) {
        self.context = context
        let browser = SelectionBrowser()
        self.browser = browser
        browser.initialCameras = [first, second]
        service = DeviceBrowserService(context: context, makeBrowser: { browser })
    }
}

/// These framework subclasses override every operation used by the fixture. No USB browser,
/// session or original download API is called by these tests.
private final class SelectionBrowser: ICDeviceBrowser {
    var initialCameras: [SelectionCamera] = []
    override func start() { initialCameras.forEach(add) }
    override func stop() {}
    func add(_ camera: SelectionCamera) { delegate?.deviceBrowser(self, didAdd: camera, moreComing: false) }
    func remove(_ camera: SelectionCamera) { delegate?.deviceBrowser(self, didRemove: camera, moreGoing: false) }
    func rename(_ camera: SelectionCamera) {
        (delegate as? CaptureBrowserDelegate)?.deviceBrowser(self, deviceDidChangeName: camera)
    }
}

private final class SelectionCamera: ICCameraDevice {
    var suppliedName = "iPhone"
    let suppliedIdentity: String
    let suppliedProduct: String
    var openCount = 0
    var closeCount = 0

    init(identity: String, product: String = "iPhone") {
        suppliedIdentity = identity
        suppliedProduct = product
        super.init()
    }

    override var name: String? { suppliedName }
    override var persistentIDString: String? { suppliedIdentity }
    override var productKind: String? { suppliedProduct }
    override var usbVendorID: Int32 { 0x05ac }
    override var transportType: String? { ICDeviceTransport.transportTypeUSB.rawValue }
    override var capabilities: [String] { [] }
    override var contentCatalogPercentCompleted: Int { 0 }
    override var isAccessRestrictedAppleDevice: Bool { false }
    override var iCloudPhotosEnabled: Bool { false }
    override func requestOpenSession() { openCount += 1 }
    override func requestCloseSession() { closeCount += 1 }
}

@MainActor
private final class SelectionOriginal {
    var callback: OriginalDownloadCoordinator.Callback?
    var cancelCount = 0
    var cleanupCount = 0

    func start(_ receive: @escaping OriginalDownloadCoordinator.Callback) -> OriginalDownloadHandle {
        callback = receive
        return OriginalDownloadHandle(cancel: { self.cancelCount += 1 }, cleanup: { self.cleanupCount += 1 })
    }

    func finish() {
        callback?(.completed(.success(DownloadedOriginal(
            url: URL(fileURLWithPath: "/unused-selection-fixture/original.HEIC"), expectedByteCount: 3
        ))))
    }
}

@MainActor
private func selectionWait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("The controlled device selection did not settle")
    throw MediaSourceError.unavailable
}
