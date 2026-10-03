import BackupEngine
import BackupPersistence
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Interrupted backup recovery presentation", .timeLimit(.minutes(1)))
@MainActor
struct LibraryBackupInterruptionTests {
    @Test func interruptedCompanionKeepsVerifiedEvidenceAndReconnectRecordsAnIncompleteSession() async throws {
        let fixture = try PersistentLibraryFixture()
        let old = PersistentLibraryCatalog(companion: true)
        try await fixture.accept(old)
        let source = ControlledBackupOriginals()
        fixture.controller.start(assets: [old.asset], sessionID: old.source.sessionID) { request, progress in
            try await source.download(request, progress: progress)
        }
        await source.waitForStart("old-still")
        try await source.finish("old-still", bytes: Data([1, 2, 3]))
        await source.waitForStart("old-motion")
        fixture.controller.sourceBecameUnavailable()
        await source.waitForCancellation("old-motion")
        #expect(fixture.controller.isBusy)
        #expect(fixture.destinationFixture.scope.counts.active == 1)
        fixture.controller.cancel() // A later Stop must not replace the original interruption cause.
        try await source.finish("old-motion", bytes: Data([4, 5]))
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.wasInterrupted)
        #expect(fixture.controller.stopReason == .sourceUnavailable)
        #expect(fixture.controller.snapshot?.phase == .failed)
        #expect(fixture.controller.snapshot?.verifiedResources == 1)
        #expect(fixture.controller.snapshot?.verifiedBytes == 3)
        #expect(fixture.controller.snapshot?.completedAssets == 0)
        #expect(fixture.persistence.recentSessions.first?.status == .failed)
        #expect(fixture.persistence.recentSessions.first?.verifiedResources == 1)
        #expect(fixture.destinationFixture.scope.counts.active == 0)

        let current = PersistentLibraryCatalog(prefix: "new", companion: true)
        try await fixture.accept(current)
        #expect(fixture.controller.snapshot?.phase == .failed)
        #expect(fixture.controller.projection(assets: [current.asset], sessionID: current.source.sessionID).statuses.isEmpty)
        let attempt = try #require(fixture.controller.lastAttempt)
        #expect(!attempt.matches(sessionID: current.source.sessionID) { _ in current.asset })
        fixture.controller.start(assets: [current.asset], sessionID: current.source.sessionID) { request, progress in
            try await source.download(request, progress: progress)
        }
        await source.waitForStart("new-motion")
        #expect(await source.callCount("new-still") == 0)
        try await source.finish("new-motion", bytes: Data([4, 5]))
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == .completed)
        #expect(fixture.controller.snapshot?.verifiedResources == 2)
        #expect(fixture.controller.snapshot?.transferredBytes == 2)
        #expect(!fixture.controller.wasInterrupted)
        #expect(fixture.controller.stopReason == nil)
        #expect(fixture.persistence.recentSessions.first?.status == .completed)
        #expect(fixture.persistence.recentSessions.contains { $0.status == .failed && $0.verifiedResources == 1 })
    }

    @Test func explicitStopKeepsItsMeaningWhenTheDeviceLaterDisconnects() async throws {
        let fixture = try BackupControllerFixture()
        let asset = BackupLibraryFixture.asset()
        fixture.start([asset], session: UUID())
        await fixture.source.waitForStart("still")
        fixture.controller.cancel()
        fixture.controller.sourceBecameUnavailable()
        await fixture.source.waitForCancellation("still")
        try await fixture.source.finish("still", bytes: Data([1, 2, 3]))
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.stopReason == .user)
        #expect(!fixture.controller.wasInterrupted)
        #expect(fixture.controller.snapshot?.phase == .cancelled)
        #expect(fixture.controller.snapshot?.verifiedResources == 0)
        #expect(fixture.controller.snapshot?.message == nil)
    }

    @Test func preparationFailureKeepsTheExactAttemptAndCanRetryAfterTheFolderReturns() async throws {
        let fixture = try BackupControllerFixture()
        let asset = BackupLibraryFixture.asset()
        let session = UUID()
        try FileManager.default.removeItem(at: fixture.folder)
        fixture.start([asset], session: session)
        await fixture.controller.waitUntilStopped()
        #expect(await fixture.source.totalCalls == 0)
        #expect(fixture.controller.snapshot?.phase == .failed)
        #expect(fixture.controller.snapshot?.totalAssets == 1)
        #expect(fixture.controller.snapshot?.verifiedResources == 0)
        #expect(fixture.controller.snapshot?.message != nil)
        #expect(fixture.controller.errorMessage == nil)
        #expect(fixture.controller.lastAttempt?.assets == [asset])
        #expect(fixture.controller.lastAttempt?.sessionID == session)

        try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
        fixture.start([asset], session: session)
        await fixture.source.waitForStart("still")
        try await fixture.source.finish("still", bytes: Data([1, 2, 3]))
        await fixture.controller.waitUntilStopped()
        let completed = try #require(fixture.controller.snapshot)
        #expect(completed.phase == .completed)
        fixture.controller.sourceBecameUnavailable()
        #expect(fixture.controller.snapshot == completed)
        #expect(!fixture.controller.wasInterrupted)
        #expect(fixture.scope.counts.active == 0)
    }

    @Test func exactRetryRejectsNewSessionsReusedRuntimeIDsAndChangedCompanions() {
        let asset = BackupLibraryFixture.asset()
        let session = UUID()
        let attempt = LibraryBackupController.Attempt(assets: [asset], sessionID: session)
        #expect(attempt.matches(sessionID: session) { _ in asset })
        #expect(!attempt.matches(sessionID: UUID()) { _ in asset })
        #expect(!attempt.matches(sessionID: nil) { _ in asset })
        #expect(!attempt.matches(sessionID: session) { _ in nil })
        #expect(!attempt.matches(sessionID: session) { _ in BackupLibraryFixture.asset(companion: true) })
        let changed = BackupLibraryFixture.asset(resource: MediaResource(id: "still", filename: "IMG.HEIC", byteCount: 4))
        #expect(!attempt.matches(sessionID: session) { _ in changed })
    }
}
