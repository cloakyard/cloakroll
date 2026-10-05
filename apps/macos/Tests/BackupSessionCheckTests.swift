import BackupEngine
import BackupPersistence
import Foundation
import Testing
@testable import CloakRoll

@Suite("Offline backup session check", .timeLimit(.minutes(1)))
@MainActor
struct BackupSessionCheckTests {
    @Test func checkNeedsNoDeviceAndDoesNotChangeBackupHistory() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog(companion: true)
        try await fixture.accept(catalog)
        try await fixture.backup(catalog)
        fixture.controller.suspendHistory(resetSource: true)
        let sessions = try await fixture.persistence.store().recentSessions()
        let session = try #require(sessions.first)
        let checker = BackupSessionCheckController()
        await checker.run(session: session, selectedDestinationID: session.destinationID, destination: fixture.controller.destination, persistence: fixture.persistence)
        #expect(checker.phase == .completed && !checker.isRunning)
        #expect(checker.progress.matchingFiles == 2 && checker.progress.unverifiedFiles == 0)
        #expect(try await fixture.persistence.store().recentSessions() == sessions)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }

    @Test func missingOriginalAndSuccessfulRecheckAreDistinctFromHistoricalCompletion() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        try await fixture.accept(catalog)
        try await fixture.backup(catalog)
        let session = try #require(try await fixture.persistence.store().recentSessions().first)
        let record = try #require(try await fixture.candidates(catalog).first?.record)
        let original = fixture.destinationFixture.folder.appendingPathComponent(record.relativePath)
        try FileManager.default.removeItem(at: original)
        let checker = BackupSessionCheckController()
        await checker.run(session: session, selectedDestinationID: session.destinationID, destination: fixture.controller.destination, persistence: fixture.persistence)
        #expect(checker.phase == .completed && checker.progress.unverifiedFiles == 1)
        #expect(checker.progress.matchingFiles == 0 && checker.progress.unverifiedPaths == [record.relativePath])
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(try await fixture.persistence.store().recentSessions().first?.status == .completed)
        try Data([1, 1, 1]).write(to: original)
        await checker.run(session: session, selectedDestinationID: session.destinationID, destination: fixture.controller.destination, persistence: fixture.persistence)
        #expect(checker.phase == .completed && checker.progress.matchingFiles == 1)
        #expect(checker.progress.unverifiedPaths.isEmpty && checker.errorMessage == nil)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }

    @Test func wrongDestinationIsRejectedBeforeAcquiringAccess() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        try await fixture.accept(catalog)
        try await fixture.backup(catalog)
        let session = try #require(try await fixture.persistence.store().recentSessions().first)
        let other = try BackupControllerFixture()
        let checker = BackupSessionCheckController()
        await checker.run(session: session, selectedDestinationID: session.destinationID, destination: other.controller.destination, persistence: fixture.persistence)
        #expect(checker.phase == .failed && checker.errorMessage == BackupDestinationError.selectionChanged.message)
        #expect(other.scope.counts.started == 0)
    }

    @Test func reselectedOriginalFolderCanBeCheckedWithANewSelectionIdentifier() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        try await fixture.accept(catalog)
        try await fixture.backup(catalog)
        let session = try #require(try await fixture.persistence.store().recentSessions().first)
        let previous = try #require(fixture.controller.destination.selection)
        let reselected = BackupDestination(id: UUID(), displayName: previous.displayName,
                                           lastKnownPath: previous.lastKnownPath, bookmarkData: previous.bookmarkData)
        let destination = BackupDestinationStore(defaults: try PersistentTestDefaults(record: reselected),
                                                operations: fixture.destinationFixture.scope.operations,
                                                selectFolder: { nil }, saveRecord: { _ in })
        let checker = BackupSessionCheckController()
        await checker.run(session: session, selectedDestinationID: reselected.id,
                          destination: destination, persistence: fixture.persistence)
        #expect(checker.phase == .completed && checker.progress.matchingFiles == 1)
        #expect(try await fixture.persistence.store().recentSessions().first?.destinationID == session.destinationID)
        #expect(destination.selection?.id == reselected.id)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }

    @Test func explicitlySelectedDifferentFolderFailsFilesystemIdentityCheck() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        try await fixture.accept(catalog)
        try await fixture.backup(catalog)
        let session = try #require(try await fixture.persistence.store().recentSessions().first)
        let other = try BackupControllerFixture()
        let selection = try #require(other.controller.destination.selection)
        let checker = BackupSessionCheckController()
        await checker.run(session: session, selectedDestinationID: selection.id,
                          destination: other.controller.destination, persistence: fixture.persistence)
        #expect(checker.phase == .failed && checker.errorMessage == SavedBackupCheckError.differentFolder.errorDescription)
        #expect(checker.progress.checkedFiles == 0 && other.scope.counts.active == 0)
    }

    @Test(arguments: [false, true])
    func cancellationWaitsForFolderWorkAndReleasesAccess(parentCancellation: Bool) async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        try await fixture.accept(catalog)
        try await fixture.backup(catalog)
        let session = try #require(try await fixture.persistence.store().recentSessions().first)
        let record = try #require(fixture.controller.destination.selection)
        let gate = PersistentLeaseGate()
        var operations = fixture.destinationFixture.scope.operations
        operations.validateReadableFolder = { _ in gate.waitOnce(); return "Test Backup" }
        let destination = BackupDestinationStore(defaults: try PersistentTestDefaults(record: record), operations: operations,
                                                selectFolder: { nil }, saveRecord: { _ in })
        let checker = BackupSessionCheckController()
        let task = Task { await checker.run(session: session, selectedDestinationID: session.destinationID, destination: destination, persistence: fixture.persistence) }
        try await waitForPersistentState { gate.entered }
        if parentCancellation { task.cancel() } else { checker.stop() }
        #expect(checker.isRunning && fixture.destinationFixture.scope.counts.active == 1)
        gate.release()
        await task.value
        #expect(checker.phase == .stopped && !checker.isRunning)
        #expect(checker.progress.checkedFiles == 0 && checker.errorMessage == nil)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }

    @Test func readLeaseAllowsReadOnlyFolderWithoutClaimingItIsWritable() async throws {
        let fixture = try BackupControllerFixture()
        let record = try #require(fixture.controller.destination.selection)
        var operations = fixture.scope.operations
        operations.validateFolder = { _ in throw BackupDestinationError.notWritable }
        let destination = BackupDestinationStore(defaults: try PersistentTestDefaults(record: record), operations: operations,
                                                selectFolder: { nil }, saveRecord: { _ in })
        await destination.checkFolder()
        #expect(destination.readiness == .unavailable(BackupDestinationError.notWritable.message))
        let lease = try await destination.acquireLease(readOnly: true)
        #expect(fixture.scope.counts.active == 1)
        #expect(destination.readiness == .unavailable(BackupDestinationError.notWritable.message))
        lease.release()
        await #expect(throws: BackupDestinationError.notWritable) { try await destination.acquireLease() }
        #expect(fixture.scope.counts.active == 0)
    }

    @Test func readLeaseDoesNotInvalidateAnOngoingFolderReadinessCheck() async throws {
        let fixture = try BackupControllerFixture()
        let record = try #require(fixture.controller.destination.selection)
        let gate = PersistentLeaseGate()
        var operations = fixture.scope.operations
        operations.validateFolder = { _ in gate.waitOnce(); return "Test Backup" }
        operations.validateReadableFolder = { _ in "Test Backup" }
        let destination = BackupDestinationStore(defaults: try PersistentTestDefaults(record: record), operations: operations,
                                                selectFolder: { nil }, saveRecord: { _ in })
        let check = Task { await destination.checkFolder() }
        try await waitForPersistentState { gate.entered }
        let lease = try await destination.acquireLease(readOnly: true)
        #expect(destination.readiness == .checking)
        lease.release()
        gate.release()
        await check.value
        #expect(destination.readiness == .available && fixture.scope.counts.active == 0)
    }
}
