import BackupEngine
import BackupPersistence
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Missing source history and retry", .timeLimit(.minutes(1)))
@MainActor
struct LibraryMissingSourceTests {
    @Test func missingStillKeepsMotionAndReconnectedRetryCopiesOnlyMissingOriginal() async throws {
        let fixture = try PersistentLibraryFixture()
        let old = PersistentLibraryCatalog(companion: true)
        try await fixture.accept(old)
        fixture.controller.start(assets: [old.asset], sessionID: old.source.sessionID) { request, _ in
            if request.resource.id == "old-still" { throw MediaSourceError.missingResource }
            return try writePersistentOriginal(request, byte: 7)
        }
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == .failed)
        #expect(fixture.controller.snapshot?.unavailableOriginals.map(\.filename) == ["IMG.HEIC"])
        #expect(fixture.persistence.recentSessions.first?.status == .failed)
        #expect(fixture.persistence.recentSessions.first?.verifiedResources == 1)
        #expect(fixture.persistence.recentSessions.first?.completedAssets == 0)
        #expect(fixture.persistence.recentSessions.first?.unavailableOriginalsCount == 1)
        #expect(fixture.persistence.recentSessions.first?.failureMessage == fixture.controller.snapshot?.message)
        #expect(try await fixture.candidates(old).map(\.resourceID) == ["old-motion"])
        #expect(fixture.controller.projection(assets: [old.asset], sessionID: old.source.sessionID).statuses.isEmpty)

        let current = PersistentLibraryCatalog(prefix: "new", companion: true)
        let reopened = LibraryBackupPersistence(databaseURL: fixture.databaseURL)
        try await reopened.refreshSessions()
        #expect(reopened.recentSessions.first?.unavailableOriginalsCount == 1)
        #expect(reopened.recentSessions.first?.failureMessage == fixture.controller.snapshot?.message)
        let controller = LibraryBackupController(destination: fixture.controller.destination, persistence: reopened)
        try await fixture.accept(current, controller: controller)
        controller.start(assets: [current.asset], sessionID: current.source.sessionID) { request, _ in
            #expect(request.resource.id == "new-still")
            return try writePersistentOriginal(request, byte: 8)
        }
        await controller.waitUntilStopped()
        #expect(controller.snapshot?.phase == .completed)
        #expect(controller.snapshot?.transferredBytes == 3)
        #expect(controller.snapshot?.verifiedResources == 2)
        #expect(controller.snapshot?.unavailableOriginals.isEmpty == true)
        #expect(controller.projection(assets: [current.asset], sessionID: current.source.sessionID).statuses == [current.asset.id: .backedUp])
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }
}
