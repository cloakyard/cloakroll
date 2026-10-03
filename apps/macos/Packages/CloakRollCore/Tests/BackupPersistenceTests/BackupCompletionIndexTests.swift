import BackupEngine
import BackupPersistence
import Foundation
import GRDB
import Testing

@Suite("Indexed logical-asset completion")
struct BackupCompletionIndexTests {
    @Test func populatedV2UpgradeRetainsVerifiedComponentAndPendingCompanion() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let fixture = HistoryFixture()
        let first = try fixture.publication(0)
        let companion = try fixture.publication(1)
        var previousID: UUID?
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            let id = try await fixture.begin(store)
            previousID = id
            for intent in [first, companion] {
                try await store.recordStaging(sessionID: id, intent: intent.staging)
                try await store.recordPublication(sessionID: id, intent: intent)
            }
            try await store.recordVerified(sessionID: id, record: first.verifiedRecord)
            #expect(try await store.recentSessions().first?.completedAssets == 0)
        }
        // Drop only the additive v3 index/registration, leaving the real populated v2 schema,
        // verified original and pending companion journal intact for the migration under test.
        try await directory.database().write { db in
            try db.execute(sql: "DROP INDEX session_resource_asset_lookup")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v3_session_asset_lookup'")
        }
        let oldID = try #require(previousID)
        let beforePlan = try await completionPlan(directory, sessionID: oldID, assetID: fixture.assets[0].id)
        #expect(!beforePlan.contains { $0.contains("session_resource_asset_lookup") })

        do {
            let migrated = try await BackupStore(databaseURL: directory.databaseURL)
            let session = try #require(try await migrated.recentSessions().first)
            #expect(session.id == oldID && session.status == .interrupted)
            #expect(session.verifiedResources == 1 && session.verifiedBytes == 3 && session.completedAssets == 0)
            #expect(try await fixture.candidates(migrated).map(\.record) == [first.verifiedRecord])
            let pending = try #require(try await migrated.pendingJournal(destinationID: fixture.destinationID).first)
            #expect(pending.sessionID == oldID && pending.publication == companion)
            #expect(try await directory.journalCounts().resolved == 1)
            try await migrated.reconcilePublication(sessionID: oldID, intent: companion, record: companion.verifiedRecord)
            try await migrated.reconcilePublication(sessionID: oldID, intent: companion, record: companion.verifiedRecord)
            let recovered = try #require(try await migrated.recentSessions().first)
            #expect(recovered.status == .interrupted && recovered.finishedAt == session.finishedAt)
            #expect(recovered.completedAssets == 1 && recovered.verifiedResources == 2 && recovered.verifiedBytes == 8)
            #expect(try await migrated.pendingJournal(destinationID: fixture.destinationID).isEmpty)
        }
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        let recovered = try #require(try await reopened.recentSessions().first)
        #expect(recovered.id == oldID && recovered.status == .interrupted)
        #expect(recovered.completedAssets == 1 && recovered.verifiedResources == 2 && recovered.verifiedBytes == 8)
        #expect(try await fixture.candidates(reopened).count == 2)
        #expect(try await directory.journalCounts().resolved == 2)
        let plan = try await completionPlan(directory, sessionID: oldID, assetID: fixture.assets[0].id)
        #expect(plan.contains {
            $0.contains("USING INDEX session_resource_asset_lookup")
                && $0.contains("session_id=? AND runtime_asset_id=?")
        })
        let migrations = try await directory.database().read {
            try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations")
        }
        #expect(migrations == ["v1_original_backup_history", "v2_publication_journal", "v3_session_asset_lookup"])
    }

    @Test func indexedActiveCompletionCountsAnAssetOnlyAfterItsLastDistinctResource() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let fixture = HistoryFixture()
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            let id = try await fixture.begin(store)
            try await store.recordVerified(sessionID: id, record: fixture.record(0))
            try await store.recordVerified(sessionID: id, record: fixture.record(0))
            #expect(try await store.recentSessions().first?.completedAssets == 0)
            try await store.recordVerified(sessionID: id, record: fixture.record(1))
            try await store.recordVerified(sessionID: id, record: fixture.record(1))
            let complete = try #require(try await store.recentSessions().first)
            #expect(complete.completedAssets == 1 && complete.verifiedResources == 2 && complete.verifiedBytes == 8)
            try await store.finishSession(id: id, result: BackupSnapshot(
                phase: .completed, completedAssets: 1, verifiedResources: 2, verifiedBytes: 8, transferredBytes: 8
            ))
        }
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        let complete = try #require(try await reopened.recentSessions().first)
        #expect(complete.status == .completed && complete.completedAssets == 1 && complete.verifiedResources == 2)
        #expect(try await fixture.candidates(reopened).count == 2)
    }

    private func completionPlan(_ directory: HistoryDirectory, sessionID: UUID, assetID: String) async throws -> [String] {
        try await directory.database().read { db in
            // This is the completion query used when a verified resource updates session counts.
            try Row.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN
                SELECT COUNT(*) = COUNT(b.id) FROM session_resource r LEFT JOIN backup_record b
                    ON b.session_id = r.session_id AND b.runtime_resource_id = r.runtime_resource_id
                WHERE r.session_id = ? AND r.runtime_asset_id = ?
                """, arguments: [sessionID.uuidString, assetID]).map { $0["detail"] as String }
        }
    }
}
