import BackupEngine
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Destination recall and incremental backups", .timeLimit(.minutes(1)))
@MainActor
struct DestinationIncrementalTests {
    @Test func twoPhonesReconnectToTheirOwnFoldersAndOnlyMissingCompanionIsCopied() async throws {
        let fixture = try DestinationRecallFixture()
        let database = fixture.root.appendingPathComponent("History.sqlite")
        let persistence = LibraryBackupPersistence(databaseURL: database)
        var chosen = fixture.first
        let destination = fixture.store { chosen }
        let controller = LibraryBackupController(destination: destination, persistence: persistence)
        let first = PersistentLibraryCatalog(companion: true, deviceKey: "first", deviceName: "iPhone")
        let second = PersistentLibraryCatalog(companion: true, deviceKey: "second", deviceName: "iPhone")
        controller.useDevice(first.device)
        await controller.chooseDestination()
        try await accept(first, controller)
        try await backup(first, controller)
        let firstID = try #require(destination.selection?.id)

        controller.suspendHistory(resetSource: true)
        controller.useDevice(second.device)
        #expect(destination.selection == nil)
        chosen = fixture.second
        await controller.chooseDestination()
        try await accept(second, controller)
        try await backup(second, controller)
        let secondID = try #require(destination.selection?.id)
        #expect(firstID != secondID)

        let reopened = LibraryBackupController(destination: fixture.store { nil },
                                               persistence: LibraryBackupPersistence(databaseURL: database))
        let reconnected = PersistentLibraryCatalog(prefix: "new", companion: true, deviceKey: "first", deviceName: "Renamed")
        reopened.useDevice(reconnected.device)
        #expect(reopened.destination.selection?.id == firstID)
        try await accept(reconnected, reopened)
        #expect(reopened.projection(assets: [reconnected.asset], sessionID: reconnected.source.sessionID).statuses[reconnected.asset.id] == .backedUp)
        reopened.start(assets: [reconnected.asset], sessionID: reconnected.source.sessionID) { _, _ in
            Issue.record("A recalled verified folder must not redownload originals")
            throw PersistentLibraryTestError.timeout
        }
        await reopened.waitUntilStopped()
        #expect(reopened.snapshot?.phase == .completed && reopened.snapshot?.transferredBytes == 0)

        let prepared = try await LibraryBackupPersistence.prepare(source: reconnected.source, assets: [reconnected.asset], device: reconnected.device)
        let records = try await persistence.store().candidates(deviceKey: reconnected.device.id, destinationID: firstID, identity: prepared.identity)
        let motion = try #require(records.first { $0.resourceID == "new-motion" })
        let still = try #require(records.first { $0.resourceID == "new-still" })
        let stillURL = fixture.first.appendingPathComponent(still.record.relativePath)
        let stillBytes = try Data(contentsOf: stillURL)
        try FileManager.default.removeItem(at: fixture.first.appendingPathComponent(motion.record.relativePath))
        reopened.retryHistoryCheck()
        try await waitForPersistentState { !reopened.isCheckingHistory }
        #expect(reopened.projection(assets: [reconnected.asset], sessionID: reconnected.source.sessionID).statuses[reconnected.asset.id] != .backedUp)
        reopened.start(assets: [reconnected.asset], sessionID: reconnected.source.sessionID) { request, _ in
            #expect(request.resource.id == "new-motion")
            return try writePersistentOriginal(request, byte: 4)
        }
        await reopened.waitUntilStopped()
        #expect(reopened.snapshot?.phase == .completed && reopened.snapshot?.transferredBytes == 2)
        #expect(try Data(contentsOf: stillURL) == stillBytes)
        reopened.suspendHistory(resetSource: true)
        reopened.useDevice(second.device)
        #expect(reopened.destination.selection?.id == secondID)
        try await accept(second, reopened)
        #expect(reopened.projection(assets: [second.asset], sessionID: second.source.sessionID).statuses[second.asset.id] == .backedUp)
    }

    @Test func completedHistoryMigratesLegacySingleFolderForItsExactPhone() async throws {
        let fixture = try DestinationRecallFixture()
        let persistence = LibraryBackupPersistence(databaseURL: fixture.root.appendingPathComponent("History.sqlite"))
        let destination = fixture.store { fixture.first }
        #expect(await destination.chooseFolder())
        let controller = LibraryBackupController(destination: destination, persistence: persistence)
        let catalog = PersistentLibraryCatalog()
        try await accept(catalog, controller)
        try await backup(catalog, controller)
        let legacy = try #require(destination.selection)
        fixture.defaults.set(try JSONEncoder().encode(legacy), forKey: BackupDestinationStore.storageKey)
        let reopened = LibraryBackupController(destination: fixture.store { nil }, persistence: persistence)
        reopened.useDevice(catalog.device)
        #expect(reopened.destination.selection == nil)
        try await accept(catalog, reopened)
        #expect(reopened.destination.selection?.id == legacy.id)
        #expect(reopened.projection(assets: [catalog.asset], sessionID: catalog.source.sessionID).statuses[catalog.asset.id] == .backedUp)
        let other = PersistentLibraryCatalog(deviceKey: "other")
        reopened.suspendHistory(resetSource: true)
        reopened.useDevice(other.device)
        try await accept(other, reopened)
        #expect(reopened.destination.selection == nil)
    }

    private func accept(_ catalog: PersistentLibraryCatalog, _ controller: LibraryBackupController) async throws {
        controller.acceptCatalog(source: catalog.source, assets: [catalog.asset], device: catalog.device)
        try await waitForPersistentState { !controller.isCheckingHistory }
        #expect(controller.historyErrorMessage == nil)
    }

    private func backup(_ catalog: PersistentLibraryCatalog, _ controller: LibraryBackupController) async throws {
        controller.start(assets: [catalog.asset], sessionID: catalog.source.sessionID) { request, _ in
            try writePersistentOriginal(request, byte: 4)
        }
        try #require(controller.isBackingUp)
        await controller.waitUntilStopped()
        #expect(controller.snapshot?.phase == .completed)
    }
}
