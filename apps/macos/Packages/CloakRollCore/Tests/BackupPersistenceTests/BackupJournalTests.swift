import BackupEngine
import BackupPersistence
import Foundation
import GRDB
import Testing

@Suite("Durable original publication journal")
struct BackupJournalTests {
    @Test func registrationRejectsUnsafeOrMismatchedEvidenceWithoutCreatingRows() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        let staging = try fixture.staging()
        let invalid = [
            staging.changing(path: "../escape/file"), staging.changing(path: "/absolute/file"),
            staging.changing(path: ".cloakroll-staging-\(UUID().uuidString.lowercased())/\(UUID())/file"),
            staging.changing(bytes: 0), staging.changing(bytes: 999),
            staging.changing(sourceSessionID: UUID()), staging.changing(signature: "changed")
        ]
        for intent in invalid {
            await #expect(throws: BackupStoreError.invalidRecord) { try await store.recordStaging(sessionID: id, intent: intent) }
        }
        #expect(try await directory.journalCounts().pending == 0)
        try await store.recordStaging(sessionID: id, intent: staging)
        await #expect(throws: BackupStoreError.invalidRecord) { try await store.recordStaging(sessionID: id, intent: fixture.staging()) }
        #expect(try await directory.journalCounts().pending == 1)
    }

    @Test func stagesSurviveReopenAndRemainScopedToDestinationAndStoppedSessions() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let fixture = HistoryFixture()
        let publication = try fixture.publication()
        let otherStage = try fixture.staging(1)
        var sessionID: UUID?
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            let id = try await fixture.begin(store)
            sessionID = id
            try await store.recordStaging(sessionID: id, intent: publication.staging)
            try await store.recordStaging(sessionID: id, intent: publication.staging)
            try await store.recordStaging(sessionID: id, intent: otherStage)
            try await store.recordPublication(sessionID: id, intent: publication)
            try await store.recordPublication(sessionID: id, intent: publication)
            #expect(try await store.pendingJournal(destinationID: fixture.destinationID).isEmpty)
            #expect(try await directory.journalCounts().pending == 2)
        }
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        let pending = try await reopened.pendingJournal(destinationID: fixture.destinationID)
        #expect(pending.count == 2)
        #expect(pending.allSatisfy { $0.sessionID == sessionID })
        #expect(pending.contains { $0.staging == publication.staging && $0.publication == publication })
        #expect(pending.contains { $0.staging == otherStage && $0.publication == nil })
        #expect(try await reopened.pendingJournal(destinationID: UUID()).isEmpty)
        #expect(try await fixture.candidates(reopened).isEmpty)
        #expect(try await reopened.recentSessions().first?.status == .interrupted)
    }

    @Test func collisionMayChangeOnlyProposedPathAndSuccessResolvesExactIntent() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        let first = try fixture.publication()
        let collision = first.changing(path: "2026/09/IMG_0001 (2).HEIC")
        await #expect(throws: BackupStoreError.invalidRecord) { try await store.recordPublication(sessionID: id, intent: first) }
        try await store.recordStaging(sessionID: id, intent: first.staging)
        await #expect(throws: BackupStoreError.invalidRecord) { try await store.recordVerified(sessionID: id, record: first.verifiedRecord) }
        try await store.recordPublication(sessionID: id, intent: first)
        await #expect(throws: BackupStoreError.invalidRecord) {
            try await store.recordPublication(sessionID: id, intent: first.changing(inode: 3))
        }
        try await store.recordPublication(sessionID: id, intent: collision)
        await #expect(throws: BackupStoreError.invalidRecord) { try await store.recordVerified(sessionID: id, record: first.verifiedRecord) }
        try await store.recordVerified(sessionID: id, record: collision.verifiedRecord)
        try await store.recordVerified(sessionID: id, record: collision.verifiedRecord)
        await #expect(throws: BackupStoreError.invalidRecord) { try await store.recordPublication(sessionID: id, intent: first) }
        let counts = try await directory.journalCounts()
        #expect(counts.pending == 0 && counts.resolved == 1)
        #expect(try await fixture.candidates(store).first?.record == collision.verifiedRecord)
        #expect(try await store.recentSessions().first?.verifiedResources == 1)
    }

    @Test func journalResolutionAndRecordCountersRollBackTogether() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        let intent = try fixture.publication()
        try await store.recordStaging(sessionID: id, intent: intent.staging)
        try await store.recordPublication(sessionID: id, intent: intent)
        try await directory.database().write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_resolve BEFORE UPDATE OF resolved_at ON backup_journal
                BEGIN SELECT RAISE(ABORT, 'simulated journal failure'); END;
                """)
        }
        await #expect(throws: BackupStoreError.unavailable) { try await store.recordVerified(sessionID: id, record: intent.verifiedRecord) }
        #expect(try await fixture.candidates(store).isEmpty)
        #expect(try await directory.journalCounts().pending == 1)
        #expect(try await store.recentSessions().first?.verifiedResources == 0)
        try await directory.database().write { try $0.execute(sql: "DROP TRIGGER reject_resolve") }
        try await store.recordVerified(sessionID: id, record: intent.verifiedRecord)
        #expect(try await directory.journalCounts().resolved == 1)
        #expect(try await store.recentSessions().first?.verifiedResources == 1)
    }

    @Test func failedCollisionIntentWritePreservesThePreviousDurablePath() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        let intent = try fixture.publication()
        try await store.recordStaging(sessionID: id, intent: intent.staging)
        try await store.recordPublication(sessionID: id, intent: intent)
        try await directory.database().write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_intent BEFORE UPDATE OF publication_payload ON backup_journal
                BEGIN SELECT RAISE(ABORT, 'simulated intent failure'); END;
                """)
        }
        await #expect(throws: BackupStoreError.unavailable) {
            try await store.recordPublication(sessionID: id, intent: intent.changing(path: "2026/09/IMG_0001 (2).HEIC"))
        }
        try await store.finishSession(id: id, result: BackupSnapshot(phase: .failed))
        #expect(try await store.pendingJournal(destinationID: fixture.destinationID).first?.publication == intent)
        #expect(try await fixture.candidates(store).isEmpty)
    }

    @Test(arguments: [BackupPhase.failed, .cancelled])
    func recoveryRetainsTerminalOutcomeAndIsIdempotent(phase: BackupPhase) async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        let intents = try [fixture.publication(0), fixture.publication(1)]
        for intent in intents {
            try await store.recordStaging(sessionID: id, intent: intent.staging)
            try await store.recordPublication(sessionID: id, intent: intent)
        }
        await #expect(throws: BackupStoreError.unknownSession) {
            try await store.reconcilePublication(sessionID: id, intent: intents[0], record: intents[0].verifiedRecord)
        }
        try await store.finishSession(id: id, result: BackupSnapshot(phase: phase, transferredBytes: 8))
        let prior = try #require(try await store.recentSessions().first)
        for intent in intents {
            let changed = intent.changing(inode: 123)
            await #expect(throws: BackupStoreError.invalidRecord) {
                try await store.reconcilePublication(sessionID: id, intent: changed, record: changed.verifiedRecord)
            }
            try await store.reconcilePublication(sessionID: id, intent: intent, record: intent.verifiedRecord)
            try await store.reconcilePublication(sessionID: id, intent: intent, record: intent.verifiedRecord)
        }
        let after = try #require(try await store.recentSessions().first)
        #expect(after.status == prior.status && after.status != .completed)
        #expect(after.finishedAt == prior.finishedAt && after.transferredBytes == prior.transferredBytes)
        #expect(after.completedAssets == 1 && after.verifiedResources == 2 && after.verifiedBytes == 8)
        #expect(try await store.pendingJournal(destinationID: fixture.destinationID).isEmpty)
    }

    @Test func migratingV1PreservesOriginalEvidenceAndDoesNotCreateJournalClaims() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let fixture = HistoryFixture()
        let record = try fixture.record()
        var sessionID: UUID?
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            let id = try await fixture.begin(store)
            sessionID = id
            try await store.recordVerified(sessionID: id, record: record)
            try await store.finishSession(id: id, result: BackupSnapshot(phase: .failed, transferredBytes: 3))
        }
        // Reversing later table/index migrations recreates the
        // actual unchanged v1 schema and populated rows, rather than a hand-written lookalike.
        try await directory.database().write { db in
            try db.execute(sql: "DROP TABLE recovery_import")
            try db.execute(sql: """
                DROP INDEX session_history_page;
                DROP INDEX session_device_history_page;
                CREATE INDEX session_recent ON backup_session(started_at DESC);
                DELETE FROM grdb_migrations WHERE identifier = 'v6_history_pages';
                """)
            try db.execute(sql: "DROP INDEX session_device_completed")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v5_device_last_backup'")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v4_folder_recovery'")
            try db.execute(sql: "DROP TABLE backup_journal")
            try db.execute(sql: "DROP INDEX session_resource_asset_lookup")
            try db.execute(sql: """
                DELETE FROM grdb_migrations WHERE identifier IN ('v2_publication_journal', 'v3_session_asset_lookup')
                """)
        }
        let migrated = try await BackupStore(databaseURL: directory.databaseURL)
        let session = try #require(try await migrated.recentSessions().first)
        #expect(session.id == sessionID && session.status == .failed)
        #expect(session.verifiedResources == 1 && session.verifiedBytes == 3)
        #expect(try await fixture.candidates(migrated).first?.record == record)
        #expect(try await migrated.pendingJournal(destinationID: fixture.destinationID).isEmpty)
        #expect(try await directory.journalCounts().pending == 0)
        let migrations = try await directory.database().read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }
        #expect(migrations == ["v1_original_backup_history", "v2_publication_journal", "v3_session_asset_lookup", "v4_folder_recovery", "v5_device_last_backup", "v6_history_pages"])
    }
}
