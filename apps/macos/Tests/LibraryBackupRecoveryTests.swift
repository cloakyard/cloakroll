import BackupEngine
import BackupPersistence
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Published original recovery integration", .timeLimit(.minutes(1)))
@MainActor
struct LibraryBackupRecoveryTests {
    @Test func controllerCommitsStagingBeforeRequestingTheOriginal() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        try await fixture.accept(catalog)
        let databaseURL = fixture.databaseURL
        let folder = fixture.destinationFixture.folder
        fixture.controller.start(assets: [catalog.asset], sessionID: catalog.source.sessionID) { request, _ in
            let journal = try RecoveryJournalReader.read(databaseURL, resourceID: request.resource.id)
            #expect(journal.staging.sourceSessionID == request.sessionID)
            #expect(journal.staging.expectedByteCount == request.resource.byteCount)
            #expect(journal.publication == nil)
            #expect(!journal.isResolved)
            #expect(folder.appendingPathComponent(journal.staging.stagingRelativePath)
                == request.directory.appendingPathComponent(request.filename))
            return try writePersistentOriginal(request, byte: 1)
        }
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == .completed)
        let journal = try RecoveryJournalReader.read(databaseURL, resourceID: catalog.asset.resources[0].id)
        #expect(journal.publication != nil)
        #expect(journal.isResolved)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }

    @Test func reopeningRecoversPublishedOriginalAndRebasesBeforeRetryWithoutUSB() async throws {
        let fixture = try RecoveryLibraryFixture()
        let old = PersistentLibraryCatalog()
        let intent = try await fixture.publishWithoutRecord(old)
        let (persistence, controller) = fixture.reopen()
        let reconnected = PersistentLibraryCatalog(prefix: "reconnected")
        try await fixture.library.accept(reconnected, controller: controller)
        #expect(controller.projection(assets: [reconnected.asset], sessionID: reconnected.source.sessionID).statuses
            == [reconnected.asset.id: .backedUp])
        #expect(controller.projection(assets: [old.asset], sessionID: old.source.sessionID).statuses.isEmpty)
        let context = try await LibraryBackupPersistence.prepare(
            source: reconnected.source, assets: [reconnected.asset], device: reconnected.device
        )
        let lease = try await controller.destination.acquireLease()
        let recovered = try await persistence.verifyHistory(context: context, lease: lease)
        lease.release()
        let record = try #require(recovered.records.first)
        #expect(record.relativePath == intent.relativePath)
        #expect(record.sha256 == intent.sha256)
        #expect(record.assetID == reconnected.asset.id)
        #expect(record.resourceID == reconnected.asset.resources[0].id)
        #expect(record.sourceSessionID == reconnected.source.sessionID)
        #expect(persistence.recentSessions.first?.status == .interrupted)
        #expect(persistence.recentSessions.first?.completedAssets == 1)
        let source = fixture.source
        controller.start(assets: [reconnected.asset], sessionID: reconnected.source.sessionID) { request, _ in
            try await source.copy(request)
        }
        await controller.waitUntilStopped()
        #expect(controller.snapshot?.phase == .completed)
        #expect(controller.snapshot?.transferredBytes == 0)
        #expect(await source.calls == 1)
        #expect(fixture.library.destinationFixture.scope.counts.active == 0)
    }

    @Test(arguments: RecoveryOriginalMutation.allCases)
    func changedOrReplacedPublishedOriginalRemainsUnverified(_ mutation: RecoveryOriginalMutation) async throws {
        let fixture = try RecoveryLibraryFixture()
        let old = PersistentLibraryCatalog()
        let intent = try await fixture.publishWithoutRecord(old)
        let final = fixture.library.destinationFixture.folder.appendingPathComponent(intent.relativePath)
        try mutation.apply(to: final)
        let bytes = try Data(contentsOf: final)
        let (persistence, controller) = fixture.reopen()
        let reconnected = PersistentLibraryCatalog(prefix: "reconnected")
        try await fixture.library.accept(reconnected, controller: controller)
        #expect(controller.projection(assets: [reconnected.asset], sessionID: reconnected.source.sessionID).statuses.isEmpty)
        let destinationID = try #require(controller.destination.selection?.id)
        let pending = try await persistence.store().pendingJournal(destinationID: destinationID)
        #expect(pending.map(\.publication) == [intent])
        #expect(persistence.recentSessions.first?.verifiedResources == 0)
        #expect(persistence.recentSessions.first?.completedAssets == 0)
        #expect(try Data(contentsOf: final) == bytes)
        #expect(await fixture.source.calls == 1)
        #expect(fixture.library.destinationFixture.scope.counts.active == 0)
    }

    @Test func failedSourceKeepsStagingJournalWithoutCompletingTheItem() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        try await fixture.accept(catalog)
        let source = ControlledBackupOriginals()
        fixture.controller.start(assets: [catalog.asset], sessionID: catalog.source.sessionID) { request, progress in
            try await source.download(request, progress: progress)
        }
        await source.waitForStart("old-still")
        try await source.fail("old-still")
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == .failed)
        #expect(fixture.controller.snapshot?.completedAssets == 0)
        #expect(try await fixture.candidates(catalog).isEmpty)
        let destinationID = try #require(fixture.controller.destination.selection?.id)
        let before = try await fixture.persistence.store().pendingJournal(destinationID: destinationID)
        #expect(before.count == 1)
        #expect(before.first?.publication == nil)
        let persistence = LibraryBackupPersistence(databaseURL: fixture.databaseURL)
        let reopened = LibraryBackupController(destination: fixture.controller.destination, persistence: persistence)
        try await fixture.accept(catalog, controller: reopened)
        #expect(try await persistence.store().pendingJournal(destinationID: destinationID) == before)
        #expect(reopened.projection(assets: [catalog.asset], sessionID: catalog.source.sessionID).statuses.isEmpty)
        #expect(persistence.recentSessions.first?.status == .failed)
        #expect(persistence.recentSessions.first?.verifiedResources == 0)
        #expect(await source.totalCalls == 1)
    }

    @Test func cancelledOldHistoryCannotApplyRecoveredEvidenceToNewCatalog() async throws {
        let fixture = try RecoveryLibraryFixture()
        let old = PersistentLibraryCatalog()
        _ = try await fixture.publishWithoutRecord(old)
        let selection = try #require(fixture.library.controller.destination.selection)
        let gate = PersistentLeaseGate()
        defer { gate.release() }
        let scope = BackupScopeProbe(folder: fixture.library.destinationFixture.folder)
        var operations = scope.operations
        let validate = operations.validateFolder
        operations.validateFolder = { url in gate.waitOnce(); return try validate(url) }
        let destination = BackupDestinationStore(
            defaults: try PersistentTestDefaults(record: selection), operations: operations,
            selectFolder: { nil }, saveRecord: { _ in }
        )
        let persistence = LibraryBackupPersistence(databaseURL: fixture.library.databaseURL)
        let controller = LibraryBackupController(destination: destination, persistence: persistence)
        controller.acceptCatalog(source: old.source, assets: [old.asset], device: old.device)
        try await waitForPersistentState { gate.entered }
        #expect(scope.counts.active == 1)
        let changed = PersistentLibraryCatalog(prefix: "new", contextFolder: "101APPLE")
        try await fixture.library.accept(changed, controller: controller)
        #expect(controller.projection(assets: [changed.asset], sessionID: changed.source.sessionID).statuses.isEmpty)
        gate.release()
        try await waitForPersistentState { scope.counts.active == 0 }
        #expect(controller.projection(assets: [changed.asset], sessionID: changed.source.sessionID).statuses.isEmpty)
        #expect(controller.projection(assets: [old.asset], sessionID: old.source.sessionID).statuses.isEmpty)
        #expect(controller.historyErrorMessage == nil)
        #expect(await fixture.source.calls == 1)
    }
}
