import BackupEngine
import BackupPersistence
import Foundation
import Testing

@Suite("Persistent verification timestamp representation")
struct BackupTimestampReplayTests {
    private let preciseDate = Date(timeIntervalSinceReferenceDate: 812345678.1234568)

    @Test func duplicateVerifiedCallbackUsesTheDatabaseTimestampRepresentation() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let fixture = HistoryFixture(date: preciseDate)
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let id = try await fixture.begin(store)
        let record = try fixture.record(verifiedAt: preciseDate)
        #expect(Date(timeIntervalSince1970: preciseDate.timeIntervalSince1970) != preciseDate)
        try await store.recordVerified(sessionID: id, record: record)
        try await store.recordVerified(sessionID: id, record: record)
        let session = try #require(try await store.recentSessions().first)
        #expect(session.verifiedResources == 1 && session.verifiedBytes == 3)
        let saved = try #require(try await fixture.candidates(store).first?.record)
        #expect(saved.verifiedAt == Date(timeIntervalSince1970: preciseDate.timeIntervalSince1970))
        #expect(saved.sourceModifiedAt == Date(timeIntervalSince1970: preciseDate.timeIntervalSince1970))
        #expect(saved.sourceMetadataSignature == record.sourceMetadataSignature)
        #expect(saved.sha256 == record.sha256 && saved.relativePath == record.relativePath)
    }

    @Test func recoveredPublicationReplayPreservesExactJournalAndIsIdempotent() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let fixture = HistoryFixture(date: preciseDate)
        let intent = try fixture.publication(verifiedAt: preciseDate)
        var oldID: UUID?
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            let id = try await fixture.begin(store)
            oldID = id
            try await store.recordStaging(sessionID: id, intent: intent.staging)
            try await store.recordPublication(sessionID: id, intent: intent)
        }
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        let pending = try #require(try await reopened.pendingJournal(destinationID: fixture.destinationID).first)
        #expect(pending.publication == intent)
        try await reopened.reconcilePublication(sessionID: pending.sessionID, intent: intent, record: intent.verifiedRecord)
        try await reopened.reconcilePublication(sessionID: pending.sessionID, intent: intent, record: intent.verifiedRecord)
        let session = try #require(try await reopened.recentSessions().first { $0.id == oldID })
        #expect(session.status == .interrupted && session.verifiedResources == 1 && session.verifiedBytes == 3)
        #expect(try await reopened.pendingJournal(destinationID: fixture.destinationID).isEmpty)
        let alteredEvidence = intent.changing(digest: String(repeating: "a", count: 64))
        await #expect(throws: BackupStoreError.invalidRecord) {
            try await reopened.reconcilePublication(
                sessionID: pending.sessionID, intent: alteredEvidence, record: alteredEvidence.verifiedRecord
            )
        }
    }
}
