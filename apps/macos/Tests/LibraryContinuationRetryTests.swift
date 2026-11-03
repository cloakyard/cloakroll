import BackupEngine
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Same-connection continuation", .timeLimit(.minutes(1)))
@MainActor
struct LibraryContinuationRetryTests {
    @Test func sessionOnlyPhoneRetriesMissingCompanionWithoutCopyingTheStillAgain() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog(companion: true, persistent: false)
        try await fixture.accept(catalog)
        fixture.controller.start(assets: [catalog.asset], sessionID: catalog.source.sessionID) { request, _ in
            if request.resource.id == "old-motion" { throw MediaSourceError.missingResource }
            return try writePersistentOriginal(request, byte: 1)
        }
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == .failed)
        let originalID = try #require(fixture.controller.lastStoredSessionID)
        let candidates = try await fixture.candidates(catalog)
        let still = try #require(candidates.first?.record)
        #expect(candidates.count == 1)

        fixture.controller.start(assets: [catalog.asset], sessionID: catalog.source.sessionID,
                                 continuingSessionID: originalID) { request, _ in
            #expect(request.resource.id == "old-motion")
            return try writePersistentOriginal(request, byte: 2)
        }
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == .completed)
        #expect(fixture.controller.snapshot?.transferredBytes == 2)
        #expect(fixture.controller.snapshot?.verifiedResources == 2)
        let sessions = try await fixture.persistence.store().recentSessions()
        #expect(sessions.count == 2)
        #expect(sessions.first { $0.id == originalID }?.hasContinuation == true)
        #expect(sessions.first { $0.id == originalID }?.status == .failed)
        let stillURL = fixture.destinationFixture.folder.appendingPathComponent(still.relativePath)
        #expect(try Data(contentsOf: stillURL) == Data([1, 1, 1]))
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }
}
