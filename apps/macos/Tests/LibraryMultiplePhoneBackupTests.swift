import BackupEngine
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Multiple iPhone backup integration", .timeLimit(.minutes(1)))
@MainActor
struct LibraryMultiplePhoneBackupTests {
    @Test func phonesWithTheSameNameAndMediaRemainSeparateAcrossReconnectRenameAndMissingFiles() async throws {
        let fixture = try PersistentLibraryFixture()
        let first = PersistentLibraryCatalog(deviceKey: "first", deviceName: "iPhone")
        let second = PersistentLibraryCatalog(deviceKey: "second", deviceName: "iPhone")
        try await fixture.accept(first)
        try await fixture.backup(first, byte: 1)
        let firstRecord = try #require(try await fixture.candidates(first).first?.record)

        try await fixture.accept(second)
        #expect(fixture.controller.projection(assets: [second.asset], sessionID: second.source.sessionID).statuses.isEmpty)
        #expect(try await fixture.candidates(second).isEmpty)
        try await fixture.backup(second, byte: 2)
        let secondRecord = try #require(try await fixture.candidates(second).first?.record)
        #expect(firstRecord.relativePath != secondRecord.relativePath)
        #expect(firstRecord.relativePath.hasPrefix(try BackupFolderLayout.deviceFolderName(for: first.device.id) + "/"))
        #expect(secondRecord.relativePath.hasPrefix(try BackupFolderLayout.deviceFolderName(for: second.device.id) + "/"))
        #expect(fixture.persistence.recentSessions.count == 2)

        let reconnected = PersistentLibraryCatalog(prefix: "fresh", deviceKey: "first", deviceName: "Renamed iPhone")
        let reopened = LibraryBackupPersistence(databaseURL: fixture.databaseURL)
        let controller = LibraryBackupController(destination: fixture.controller.destination, persistence: reopened)
        try await fixture.accept(reconnected, controller: controller)
        #expect(controller.projection(assets: [reconnected.asset], sessionID: reconnected.source.sessionID).statuses
                == [reconnected.asset.id: .backedUp])
        controller.start(assets: [reconnected.asset], sessionID: reconnected.source.sessionID) { _, _ in
            Issue.record("A reconnected, renamed phone must reuse its freshly verified original")
            throw PersistentLibraryTestError.timeout
        }
        await controller.waitUntilStopped()
        #expect(controller.snapshot?.phase == .completed)
        #expect(controller.snapshot?.transferredBytes == 0)
        #expect(reopened.recentSessions.first?.deviceName == "Renamed iPhone")

        let firstURL = fixture.destinationFixture.folder.appendingPathComponent(firstRecord.relativePath)
        let secondURL = fixture.destinationFixture.folder.appendingPathComponent(secondRecord.relativePath)
        #expect(try Data(contentsOf: firstURL) == Data([1, 1, 1]))
        #expect(try Data(contentsOf: secondURL) == Data([2, 2, 2]))
        try FileManager.default.removeItem(at: firstURL)
        controller.retryHistoryCheck()
        try await waitForPersistentState { !controller.isCheckingHistory }
        #expect(controller.projection(assets: [reconnected.asset], sessionID: reconnected.source.sessionID).statuses.isEmpty)
        controller.start(assets: [reconnected.asset], sessionID: reconnected.source.sessionID) { request, _ in
            try writePersistentOriginal(request, byte: 1)
        }
        await controller.waitUntilStopped()
        #expect(controller.snapshot?.phase == .completed && controller.snapshot?.transferredBytes == 3)
        #expect(try Data(contentsOf: firstURL) == Data([1, 1, 1]))
        #expect(try Data(contentsOf: secondURL) == Data([2, 2, 2]))
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }
}
