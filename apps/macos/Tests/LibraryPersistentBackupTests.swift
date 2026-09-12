import BackupEngine
import BackupPersistence
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Persistent library backup integration", .timeLimit(.minutes(1)))
@MainActor
struct LibraryPersistentBackupTests {
    @Test func reopeningHistoryRebasesReconnectIdentitiesAndReverifiesLocalBytes() async throws {
        let fixture = try PersistentLibraryFixture()
        let old = PersistentLibraryCatalog(companion: true)
        try await fixture.accept(old)
        try await fixture.backup(old)
        let reconnected = PersistentLibraryCatalog(prefix: "reconnected", companion: true)
        let reopened = LibraryBackupPersistence(databaseURL: fixture.databaseURL)
        let controller = LibraryBackupController(destination: fixture.controller.destination, persistence: reopened)
        try await fixture.accept(reconnected, controller: controller)
        #expect(controller.projection(assets: [reconnected.asset], sessionID: reconnected.source.sessionID).statuses == [reconnected.asset.id: .backedUp])
        #expect(controller.projection(assets: [old.asset], sessionID: old.source.sessionID).statuses.isEmpty)
        let context = try await LibraryBackupPersistence.prepare(
            source: reconnected.source, assets: [reconnected.asset], device: reconnected.device
        )
        let lease = try await controller.destination.acquireLease()
        defer { lease.release() }
        let result = try await reopened.verifyHistory(context: context, lease: lease)
        #expect(result.records.map(\.resourceID) == reconnected.asset.resources.map(\.id))
        #expect(result.records.allSatisfy { $0.sourceSessionID == reconnected.source.sessionID })
        #expect(reopened.recentSessions.first?.status == .completed)
        let otherDestination = DestinationLease(url: lease.url, destinationID: UUID(), relinquish: nil)
        let isolated = try await reopened.verifyHistory(context: context, lease: otherDestination)
        otherDestination.release()
        #expect(isolated.records.isEmpty)
        #expect(isolated.snapshot.completedAssetIDs.isEmpty)
        lease.release()
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }

    @Test func missingLocalOriginalClearsCompleteStatusAndDownloadsAgain() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        try await fixture.accept(catalog)
        try await fixture.backup(catalog)
        let candidate = try #require(try await fixture.candidates(catalog).first)
        let original = fixture.destinationFixture.folder.appendingPathComponent(candidate.record.relativePath)
        try FileManager.default.removeItem(at: original)
        fixture.controller.retryHistoryCheck()
        try await waitForPersistentState { !fixture.controller.isCheckingHistory }
        #expect(fixture.controller.projection(assets: [catalog.asset], sessionID: catalog.source.sessionID).statuses.isEmpty)
        try await fixture.backup(catalog, byte: 9)
        #expect(fixture.controller.snapshot?.transferredBytes == 3)
        #expect(try Data(contentsOf: original) == Data([9, 9, 9]))
    }

    @Test func sourceOnlyIdentityChangeDiscardsOldInMemoryRetryEvidence() async throws {
        let fixture = try PersistentLibraryFixture()
        let old = PersistentLibraryCatalog()
        try await fixture.accept(old)
        try await fixture.backup(old)
        let changed = PersistentLibraryCatalog(sessionID: old.source.sessionID, contextFolder: "101APPLE")
        #expect(changed.asset == old.asset)
        try await fixture.accept(changed)
        #expect(try await fixture.candidates(changed).isEmpty)
        #expect(fixture.controller.projection(assets: [changed.asset], sessionID: changed.source.sessionID).statuses.isEmpty)
        try await fixture.backup(changed, byte: 9)
        #expect(fixture.controller.snapshot?.transferredBytes == 3)
        let current = try #require(try await fixture.candidates(changed).first)
        #expect(try Data(contentsOf: fixture.destinationFixture.folder.appendingPathComponent(current.record.relativePath)) == Data([9, 9, 9]))
    }

    @Test func firstComponentIsCommittedBeforeNextTransferAndCompleteStatus() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog(companion: true)
        try await fixture.accept(catalog)
        let source = ControlledBackupOriginals()
        fixture.controller.start(assets: [catalog.asset], sessionID: catalog.source.sessionID) { request, progress in
            try await source.download(request, progress: progress)
        }
        await source.waitForStart("old-still")
        #expect(try await fixture.candidates(catalog).isEmpty)
        try await source.finish("old-still", bytes: Data([1, 2, 3]))
        await source.waitForStart("old-motion")
        #expect(try await fixture.candidates(catalog).map(\.resourceID) == ["old-still"])
        #expect(fixture.controller.projection(assets: [catalog.asset], sessionID: catalog.source.sessionID).statuses.isEmpty)
        try await source.finish("old-motion", bytes: Data([4, 5]))
        await fixture.controller.waitUntilStopped()
        #expect(try await fixture.candidates(catalog).count == 2)
        #expect(fixture.controller.projection(assets: [catalog.asset], sessionID: catalog.source.sessionID).statuses == [catalog.asset.id: .backedUp])
        #expect(fixture.persistence.recentSessions.first?.verifiedResources == 2)
        #expect(fixture.persistence.recentSessions.first?.status == .completed)
    }

    @Test func cancelledHistoryGenerationRetainsItsLeaseUntilAcquisitionActuallySettles() async throws {
        let fixture = try PersistentLibraryFixture()
        let old = PersistentLibraryCatalog()
        try await fixture.accept(old)
        try await fixture.backup(old)
        let selection = try #require(fixture.controller.destination.selection)
        let gate = PersistentLeaseGate()
        defer { gate.release() }
        let scope = BackupScopeProbe(folder: fixture.destinationFixture.folder)
        var operations = scope.operations
        let validate = operations.validateFolder
        operations.validateFolder = { url in gate.waitOnce(); return try validate(url) }
        let destination = BackupDestinationStore(
            defaults: try PersistentTestDefaults(record: selection), operations: operations,
            selectFolder: { nil }, saveRecord: { _ in }
        )
        let controller = LibraryBackupController(destination: destination, persistence: fixture.persistence)
        controller.acceptCatalog(source: old.source, assets: [old.asset], device: old.device)
        try await waitForPersistentState { gate.entered }
        #expect(scope.counts.active == 1)
        controller.suspendHistory(resetSource: true)
        #expect(!controller.isCheckingHistory)
        #expect(scope.counts.active == 1)
        let changed = PersistentLibraryCatalog(sessionID: old.source.sessionID, contextFolder: "101APPLE")
        try await fixture.accept(changed, controller: controller)
        #expect(scope.counts.active == 1)
        #expect(controller.projection(assets: [changed.asset], sessionID: changed.source.sessionID).statuses.isEmpty)
        gate.release()
        try await waitForPersistentState { scope.counts.active == 0 }
        #expect(controller.projection(assets: [changed.asset], sessionID: changed.source.sessionID).statuses.isEmpty)
        #expect(controller.historyErrorMessage == nil)
    }

    @Test func incompleteCatalogCannotCreatePersistentBackupRecords() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        let incomplete = DeviceMediaSnapshot(
            sessionID: catalog.source.sessionID, deviceID: catalog.device.id, revision: 1,
            records: catalog.source.records, state: .scanning
        )
        fixture.controller.acceptCatalog(source: incomplete, assets: [catalog.asset], device: catalog.device)
        fixture.controller.start(assets: [catalog.asset], sessionID: catalog.source.sessionID) { _, _ in
            Issue.record("An incomplete catalog must not request an original")
            throw PersistentLibraryTestError.timeout
        }
        await fixture.controller.waitUntilStopped()
        #expect(try await fixture.persistence.store().recentSessions().isEmpty)
        #expect(fixture.controller.projection(assets: [catalog.asset], sessionID: catalog.source.sessionID).statuses.isEmpty)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }

    @Test func selectedAssetMustMatchThePreparedFullMetadataBeforeJournalRegistration() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        try await fixture.accept(catalog)
        let changed = MediaAsset(
            id: catalog.asset.id, deviceID: catalog.asset.deviceID, resources: catalog.asset.resources,
            kind: catalog.asset.kind, createdAt: catalog.asset.createdAt?.addingTimeInterval(1),
            pixelWidth: catalog.asset.pixelWidth, pixelHeight: catalog.asset.pixelHeight
        )
        fixture.controller.start(assets: [changed], sessionID: catalog.source.sessionID) { _, _ in
            Issue.record("Changed source metadata must not use a stale prepared identity")
            throw PersistentLibraryTestError.timeout
        }
        await fixture.controller.waitUntilStopped()
        #expect(try await fixture.persistence.store().recentSessions().isEmpty)
        #expect(fixture.controller.errorMessage != nil)
        #expect(fixture.controller.projection(assets: [changed], sessionID: catalog.source.sessionID).statuses.isEmpty)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }
}
