import BackupPersistence
import BackupEngine
import Foundation
import GRDB
import Testing

@Suite("Persistent backup history")
struct BackupStoreTests {
    @Test func freshStoreHasNoSessionsAndCreatesItsParent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await BackupStore(databaseURL: directory.appendingPathComponent("nested/history.sqlite"))
        #expect(try await store.recentSessions().isEmpty)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("nested/history.sqlite").path))
    }

    @Test func reopeningMigratesOnceAndInterruptsOnlyUnfinishedSessions() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let fixture = HistoryFixture()
        var completedID: UUID?
        var partialID: UUID?
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            let completed = try await fixture.begin(store)
            try await store.recordVerified(sessionID: completed, record: fixture.record(0))
            try await store.recordVerified(sessionID: completed, record: fixture.record(1))
            try await store.finishSession(id: completed, result: BackupSnapshot(
                phase: .completed, completedAssets: 1, verifiedResources: 2, verifiedBytes: 8, transferredBytes: 8
            ))
            completedID = completed
            let partial = try await fixture.begin(store)
            try await store.recordVerified(sessionID: partial, record: fixture.record(0))
            partialID = partial
        }
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        let sessions = try await reopened.recentSessions()
        #expect(sessions.first { $0.id == completedID }?.status == .completed)
        let interrupted = try #require(sessions.first { $0.id == partialID })
        #expect(interrupted.status == .interrupted)
        #expect(interrupted.verifiedResources == 1)
        #expect(interrupted.completedAssets == 0)
        #expect(interrupted.finishedAt != nil)
        #expect(try await fixture.candidates(reopened).count == 2)
        let migrations = try await directory.database().read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
        }
        #expect(migrations == ["v1_original_backup_history", "v2_publication_journal", "v3_session_asset_lookup", "v4_folder_recovery", "v5_device_last_backup", "v6_history_pages"])
    }

    @Test func duplicateResourceCallbackIsIdempotentAndPartialAssetCannotComplete() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        let record = try fixture.record()
        try await store.recordVerified(sessionID: id, record: record)
        try await store.recordVerified(sessionID: id, record: record)
        await #expect(throws: BackupStoreError.invalidCompletion) {
            try await store.finishSession(id: id, result: BackupSnapshot(
                phase: .completed, completedAssets: 1, verifiedResources: 2, verifiedBytes: 8
            ))
        }
        let active = try #require(try await store.recentSessions().first)
        #expect(active.status == .running)
        #expect(active.verifiedResources == 1)
        #expect(active.verifiedBytes == 3)
        #expect(active.completedAssets == 0)
        try await store.finishSession(id: id, result: BackupSnapshot(phase: .failed, transferredBytes: 6))
        let failed = try #require(try await store.recentSessions().first)
        #expect(failed.status == .failed)
        #expect(failed.transferredBytes == 6)
        #expect(try await fixture.candidates(store).count == 1)
    }

    @Test func databaseWriteFailureRollsBackResourceAndCounts() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        let database = try directory.database()
        try await database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_history_count BEFORE UPDATE ON backup_session
                BEGIN SELECT RAISE(ABORT, 'simulated destination history failure'); END;
                """
            )
        }
        await #expect(throws: BackupStoreError.unavailable) {
            try await store.recordVerified(sessionID: id, record: fixture.record())
        }
        #expect(try await fixture.candidates(store).isEmpty)
        #expect(try await store.recentSessions().first?.verifiedResources == 0)
        try await database.write { try $0.execute(sql: "DROP TRIGGER reject_history_count") }
        try await store.recordVerified(sessionID: id, record: fixture.record())
        #expect(try await fixture.candidates(store).count == 1)
    }

    @Test func malformedDatabaseIsNeverReplaced() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let sentinel = Data("unrelated bytes".utf8)
        try sentinel.write(to: directory.databaseURL)
        await #expect(throws: BackupStoreError.unavailable) { try await BackupStore(databaseURL: directory.databaseURL) }
        #expect(try Data(contentsOf: directory.databaseURL) == sentinel)
    }
}
