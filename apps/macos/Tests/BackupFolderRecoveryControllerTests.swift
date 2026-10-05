import BackupEngine
import BackupPersistence
import Foundation
import Testing
@testable import CloakRoll

@Suite("Folder recovery lifecycle", .timeLimit(.minutes(1)))
@MainActor
struct BackupFolderRecoveryControllerTests {
    @Test func automaticReceiptsRecoverIntoFreshHistoryAndRepeatWithoutDuplicates() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog(companion: true)
        try await fixture.accept(catalog)
        try await fixture.backup(catalog)
        let fresh = LibraryBackupPersistence(databaseURL: fixture.destinationFixture.folder.appendingPathComponent("Fresh/history.sqlite"))
        let selection = try #require(fixture.controller.destination.selection)
        let recovery = fixture.controller.recovery
        await recovery.run(mode: .indexed, selectedDestinationID: selection.id, destination: fixture.controller.destination,
                           persistence: fresh, context: nil, download: nil)
        #expect(recovery.phase == .completed && recovery.recovered == 2 && recovery.verified == 2)
        #expect(try await fresh.store().recentSessions().first?.completedAssets == 1)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
        await recovery.run(mode: .indexed, selectedDestinationID: selection.id, destination: fixture.controller.destination,
                           persistence: fresh, context: nil, download: nil)
        #expect(recovery.phase == .completed && recovery.recovered == 0 && recovery.verified == 2)
        #expect(try await fresh.store().recentSessions().count == 1)
    }

    @Test func wrongSelectionFailsBeforeFolderAccess() async throws {
        let fixture = try PersistentLibraryFixture()
        let recovery = fixture.controller.recovery
        await recovery.run(mode: .indexed, selectedDestinationID: UUID(), destination: fixture.controller.destination,
                           persistence: fixture.persistence, context: nil, download: nil)
        #expect(recovery.phase == .failed)
        #expect(fixture.destinationFixture.scope.counts.started == 0)
        #expect(recovery.errorMessage == BackupDestinationError.selectionChanged.message)
    }

    @Test func stopWaitsForAccessWorkBeforeReleasingLease() async throws {
        let fixture = try PersistentLibraryFixture()
        let selection = try #require(fixture.controller.destination.selection)
        let gate = PersistentLeaseGate()
        var operations = fixture.destinationFixture.scope.operations
        operations.validateFolder = { _ in gate.waitOnce(); return "Test Backup" }
        let destination = BackupDestinationStore(defaults: try PersistentTestDefaults(record: selection), operations: operations,
                                                selectFolder: { nil }, saveRecord: { _ in })
        let recovery = fixture.controller.recovery
        let task = Task { await recovery.run(mode: .indexed, selectedDestinationID: selection.id, destination: destination,
                                             persistence: fixture.persistence, context: nil, download: nil) }
        try await waitForPersistentState { gate.entered }
        #expect(fixture.controller.isBusy)
        fixture.controller.cancel()
        #expect(recovery.isRunning && fixture.destinationFixture.scope.counts.active == 1)
        gate.release()
        await task.value
        #expect(recovery.phase == .stopped && !fixture.controller.isBusy)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }

    @Test func USBStopKeepsTheLeaseUntilPhysicalCallbackAndBlocksNewBackup() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        try await fixture.accept(catalog)
        try Data([1, 1, 1]).write(to: fixture.destinationFixture.folder.appendingPathComponent("Old Photo.HEIC"))
        let selection = try #require(fixture.controller.destination.selection)
        let context = try #require(fixture.controller.recoveryContext)
        let recovery = fixture.controller.recovery
        let gate = FolderRecoverySourceGate()
        let task = Task {
            await recovery.run(mode: .usb, selectedDestinationID: selection.id, destination: fixture.controller.destination,
                               persistence: fixture.persistence, context: context) { request, _ in
                await gate.wait()
                return try writePersistentOriginal(request, byte: 1)
            }
        }
        await gate.waitUntilEntered()
        #expect(fixture.controller.isBusy)
        fixture.controller.start(assets: [catalog.asset], sessionID: catalog.source.sessionID) { _, _ in
            Issue.record("A backup must not start while recovery owns the source")
            throw BackupEngineError.invalidSelection
        }
        #expect(fixture.controller.snapshot == nil)
        fixture.controller.sourceBecameUnavailable()
        #expect(recovery.isStopping && fixture.destinationFixture.scope.counts.active == 1)
        await gate.release()
        await fixture.controller.waitUntilStopped()
        await task.value
        #expect(recovery.phase == .stopped && !fixture.controller.isBusy)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
        #expect(try await fixture.persistence.store().recentSessions().isEmpty)
    }
}

private actor FolderRecoverySourceGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered?.resume()
            entered = nil
        }
    }
    func waitUntilEntered() async {
        if continuation != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
