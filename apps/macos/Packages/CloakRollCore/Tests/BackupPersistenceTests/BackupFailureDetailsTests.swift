import BackupEngine
import BackupPersistence
import Foundation
import GRDB
import Testing

@Suite("Durable incomplete-backup explanations")
struct BackupFailureDetailsTests {
    @Test func partialFailureSurvivesReopenWithoutPromotingMissingCompanion() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let fixture = HistoryFixture()
        let message = "An original is unavailable. Reconnect the iPhone and refresh its library."
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            let id = try await fixture.begin(store)
            try await store.recordVerified(sessionID: id, record: fixture.record(0))
            try await store.finishSession(id: id, result: BackupSnapshot(
                phase: .failed, unavailableOriginals: [
                    .init(id: "old-motion", filename: "IMG_0001.MOV"),
                    .init(id: "old-motion", filename: "IMG_0001.MOV")
                ], message: message
            ))
        }
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        let session = try #require(try await reopened.sessionPage().sessions.first)
        #expect(session.status == .failed && session.failureMessage == message)
        #expect(session.unavailableOriginalsCount == 1)
        #expect(session.verifiedResources == 1 && session.completedAssets == 0 && session.verifiedBytes == 3)
        #expect(try await fixture.candidates(reopened).map(\.resourceID) == ["old-still"])
    }

    @Test func v6UpgradePreservesRecordsAndLeavesOldFailureReasonUnknown() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let fixture = HistoryFixture()
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            let id = try await fixture.begin(store)
            try await store.recordVerified(sessionID: id, record: fixture.record())
            try await store.finishSession(id: id, result: BackupSnapshot(phase: .failed))
        }
        try await directory.database().write { try removeFailureDetailsMigration($0) }
        let upgraded = try await BackupStore(databaseURL: directory.databaseURL)
        let session = try #require(try await upgraded.recentSessions().first)
        #expect(session.status == .failed && session.failureMessage == nil && session.unavailableOriginalsCount == 0)
        #expect(session.verifiedResources == 1 && session.completedAssets == 0)
        #expect(try await fixture.candidates(upgraded).count == 1)
    }

    @Test func explanationIsBoundedAndCancellationDoesNotStoreTransientProgress() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let fixture = HistoryFixture()
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let failedID = try await fixture.begin(store)
        try await store.finishSession(id: failedID, result: BackupSnapshot(phase: .failed, message: String(repeating: "x", count: 4_000)))
        let cancelledID = try await fixture.begin(store)
        try await store.finishSession(id: cancelledID, result: BackupSnapshot(phase: .cancelled, message: "Verifying…"))
        let sessions = try await store.recentSessions()
        #expect(sessions.first { $0.id == failedID }?.failureMessage?.count == 2_048)
        #expect(sessions.first { $0.id == cancelledID }?.failureMessage == nil)
        #expect(sessions.allSatisfy { $0.verifiedResources == 0 && $0.unavailableOriginalsCount == 0 })
    }
}
