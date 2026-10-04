import BackupEngine
import DeviceCapture
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Check saved originals command", .timeLimit(.minutes(1)))
@MainActor
struct CheckSavedOriginalsTests {
    @Test func commandClearsMissingOriginalBadgeWithoutReconnectOrTransfer() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        let browser = MockDeviceBrowserService()
        let model = AppModel(makeBrowser: { browser }, backup: fixture.controller)
        defer { model.shutdown() }
        try await load(catalog, into: model, browser: browser)
        let asset = try #require(model.assets.first)
        fixture.controller.start(assets: [asset], sessionID: catalog.source.sessionID) { request, _ in
            try writePersistentOriginal(request, byte: 1)
        }
        await fixture.controller.waitUntilStopped()
        try await waitForPersistentState { !model.isProjecting }
        #expect(model.status(for: asset) == .backedUp)
        model.select(asset, extendingRange: false, toggling: false)
        let context = try await LibraryBackupPersistence.prepare(source: catalog.source, assets: [asset], device: catalog.device)
        let destinationID = try #require(fixture.controller.destination.selection?.id)
        let candidates = try await fixture.persistence.store().candidates(
            deviceKey: catalog.device.id, destinationID: destinationID, identity: context.identity
        )
        let candidate = try #require(candidates.first)
        let original = fixture.destinationFixture.folder.appendingPathComponent(candidate.record.relativePath)
        try FileManager.default.removeItem(at: original)

        #expect(model.canCheckSavedOriginals)
        model.checkSavedOriginals()
        #expect(fixture.controller.isCheckingHistory)
        #expect(!model.canCheckSavedOriginals)
        model.checkSavedOriginals() // A repeated menu action cannot start overlapping verification.
        try await waitForPersistentState { !fixture.controller.isCheckingHistory && !model.isProjecting }
        #expect(model.status(for: asset) == .notBackedUp)
        #expect(model.catalogSessionID == catalog.source.sessionID)
        #expect(model.selection.selectedIDs == [asset.id])
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(fixture.persistence.recentSessions.count == 1)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }

    @Test func commandRequiresAnIdleCompleteLiveLibrary() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        let browser = MockDeviceBrowserService()
        let model = AppModel(makeBrowser: { browser }, backup: fixture.controller)
        defer { model.shutdown() }
        #expect(!model.canCheckSavedOriginals)
        try await load(catalog, into: model, browser: browser)
        model.navigation = .backupHistory
        #expect(!model.canCheckSavedOriginals)
        model.checkSavedOriginals()
        #expect(!fixture.controller.isCheckingHistory)
        model.navigation = .library(.all)
        model.deviceState = .disconnected
        #expect(!model.canCheckSavedOriginals)
        model.deviceState = .ready
        #expect(model.canCheckSavedOriginals)

        let source = ControlledBackupOriginals()
        fixture.controller.start(assets: model.assets, sessionID: catalog.source.sessionID) { request, progress in
            try await source.download(request, progress: progress)
        }
        await source.waitForStart("old-still")
        #expect(!model.canCheckSavedOriginals)
        model.checkSavedOriginals()
        #expect(!fixture.controller.isCheckingHistory)
        fixture.controller.cancel()
        #expect(!model.canCheckSavedOriginals)
        try await source.finish("old-still", bytes: Data([1, 1, 1]))
        await fixture.controller.waitUntilStopped()

        browser.sendCatalog(DeviceMediaSnapshot(
            sessionID: catalog.source.sessionID, deviceID: catalog.device.id, revision: 2,
            records: catalog.source.records, state: .scanning
        ))
        try await waitForPersistentState { model.mediaScanState == .scanning }
        #expect(!model.canCheckSavedOriginals)
        await model.loadSample(count: 1)
        #expect(!model.canCheckSavedOriginals)
    }

    @Test func commandRemainsAvailableAfterAHistoryAccessErrorAndCanRecover() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        let access = SavedOriginalsAccess()
        let record = try #require(fixture.controller.destination.selection)
        var operations = fixture.destinationFixture.scope.operations
        let validate = operations.validateFolder
        operations.validateFolder = { url in
            guard access.isAvailable else { throw BackupDestinationError.unavailable }
            return try validate(url)
        }
        let destination = BackupDestinationStore(
            defaults: try PersistentTestDefaults(record: record), operations: operations,
            selectFolder: { nil }, saveRecord: { _ in }
        )
        let controller = LibraryBackupController(destination: destination, persistence: fixture.persistence)
        let browser = MockDeviceBrowserService()
        let model = AppModel(makeBrowser: { browser }, backup: controller)
        defer { model.shutdown() }
        try await load(catalog, into: model, browser: browser)
        access.setAvailable(false)
        model.checkSavedOriginals()
        try await waitForPersistentState { !controller.isCheckingHistory && !model.isProjecting }
        #expect(controller.historyErrorMessage != nil)
        #expect(model.canCheckSavedOriginals)
        access.setAvailable(true)
        model.checkSavedOriginals()
        try await waitForPersistentState { !controller.isCheckingHistory && !model.isProjecting }
        #expect(controller.historyErrorMessage == nil)
        #expect(model.canCheckSavedOriginals)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }

    private func load(_ catalog: PersistentLibraryCatalog, into model: AppModel, browser: MockDeviceBrowserService) async throws {
        model.startLive()
        browser.send(DeviceConnection(device: catalog.device, state: .ready))
        try await waitForPersistentState { model.deviceState == .ready }
        browser.sendCatalog(catalog.source)
        try await waitForPersistentState { model.canCheckSavedOriginals }
        #expect(model.backup.historyErrorMessage == nil)
    }
}

private final class SavedOriginalsAccess: @unchecked Sendable {
    private let lock = NSLock()
    private var available = true
    var isAvailable: Bool { lock.withLock { available } }
    func setAvailable(_ value: Bool) { lock.withLock { available = value } }
}
