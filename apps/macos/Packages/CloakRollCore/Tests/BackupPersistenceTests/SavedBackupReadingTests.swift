import BackupEngine
import BackupPersistence
import Foundation
import GRDB
import Testing

@Suite("Saved files for historical checks")
struct SavedBackupReadingTests {
    @Test func readsOnlyCommittedFilesInTheExactSettledSessionAndDestination() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let session = try await fixture.begin(store)
        try await store.recordVerified(sessionID: session, record: fixture.record(0))
        await #expect(throws: BackupStoreError.unknownSession) {
            try await store.savedFiles(sessionID: session, destinationID: fixture.destinationID)
        }
        try await store.finishSession(id: session, result: BackupSnapshot(phase: .cancelled, transferredBytes: 3))
        let before = try await store.recentSessions()
        let records = try await store.savedFiles(sessionID: session, destinationID: fixture.destinationID)
        #expect(records == [try fixture.record(0)])
        #expect(try await store.recentSessions() == before)
        #expect(before.first?.status == .cancelled && before.first?.completedAssets == 0)
        await #expect(throws: BackupStoreError.unknownSession) {
            try await store.savedFiles(sessionID: session, destinationID: UUID())
        }
        await #expect(throws: BackupStoreError.unknownSession) {
            try await store.savedFiles(sessionID: UUID(), destinationID: fixture.destinationID)
        }
    }

    @Test func zeroVerifiedAndInconsistentRecordsAreNotSilentlyCompleted() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let session = try await fixture.begin(store)
        try await store.finishSession(id: session, result: BackupSnapshot(phase: .failed))
        #expect(try await store.savedFiles(sessionID: session, destinationID: fixture.destinationID).isEmpty)
        let db = try directory.database()
        try await db.write { try $0.execute(sql: "UPDATE backup_session SET verified_resources = 1 WHERE id = ?", arguments: [session.uuidString]) }
        await #expect(throws: BackupStoreError.invalidRecord) {
            try await store.savedFiles(sessionID: session, destinationID: fixture.destinationID)
        }
    }
}
