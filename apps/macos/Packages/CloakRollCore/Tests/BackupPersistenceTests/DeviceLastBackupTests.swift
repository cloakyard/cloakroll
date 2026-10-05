import BackupEngine
import BackupPersistence
import Foundation
import GRDB
import Testing

@Suite("Device last completed backup")
struct DeviceLastBackupTests {
    @Test func exactDeviceLookupFindsHistoryBeyondTheRecentListAcrossDestinations() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let phone = HistoryFixture(deviceValue: "phone' OR 1=1 --")
        let completed = try await complete(phone, store)
        let sameName = HistoryFixture(deviceValue: "another-phone")
        for _ in 0..<101 { _ = try await sameName.begin(store) }
        #expect(try await store.recentSessions(limit: 100).allSatisfy { $0.id != completed })
        let last = try #require(try await store.lastCompletedSession(deviceKey: phone.device.id))
        #expect(last.id == completed && last.completedAssets == 1 && last.verifiedBytes == 8)
        #expect(try await store.lastCompletedSession(deviceKey: sameName.device.id) == nil)
        #expect(try await store.lastCompletedSession(deviceKey: "absent") == nil)
        let otherFolder = HistoryFixture(deviceValue: "phone' OR 1=1 --")
        let next = try await complete(otherFolder, store)
        #expect(try await store.lastCompletedSession(deviceKey: phone.device.id)?.id == next)
    }

    @Test func onlyFinishedCompleteBackupsEstablishTheLastBackupDate() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let phone = HistoryFixture()
        let completed = try await complete(phone, store)
        let recovered = try await complete(phone, store)
        try await directory.database().write { db in
            try db.execute(sql: "UPDATE backup_session SET status = 'recovered' WHERE id = ?", arguments: [recovered.uuidString])
        }
        for phase in [BackupPhase.cancelled, .failed] {
            let unfinished = try await phone.begin(store)
            try await store.recordVerified(sessionID: unfinished, record: phone.record(0))
            try await store.finishSession(id: unfinished, result: BackupSnapshot(phase: phase))
        }
        _ = try await phone.begin(store)
        #expect(try await store.lastCompletedSession(deviceKey: phone.device.id)?.id == completed)
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        #expect(try await reopened.lastCompletedSession(deviceKey: phone.device.id)?.id == completed)
    }

    @Test func completionDateWinsOverStartDateAndInconsistentRecordsAreExcluded() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let phone = HistoryFixture()
        let first = try await complete(phone, store)
        let second = try await complete(phone, store)
        try await directory.database().write { db in
            try db.execute(sql: "UPDATE backup_session SET started_at = 100, finished_at = 400 WHERE id = ?", arguments: [first.uuidString])
            try db.execute(sql: "UPDATE backup_session SET started_at = 200, finished_at = 300 WHERE id = ?", arguments: [second.uuidString])
        }
        #expect(try await store.lastCompletedSession(deviceKey: phone.device.id)?.id == first)
        try await directory.database().write { db in
            try db.execute(sql: "UPDATE backup_session SET verified_resources = 1 WHERE id = ?", arguments: [first.uuidString])
            try db.execute(sql: "UPDATE backup_session SET finished_at = NULL WHERE id = ?", arguments: [second.uuidString])
        }
        #expect(try await store.lastCompletedSession(deviceKey: phone.device.id) == nil)
    }

    @Test func populatedV4UpgradePreservesSummaryAndAddsDeviceIndex() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let phone = HistoryFixture()
        let before: StoredBackupSession
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            _ = try await complete(phone, store)
            before = try #require(try await store.lastCompletedSession(deviceKey: phone.device.id))
        }
        try await directory.database().write { db in
            try db.execute(sql: "DROP INDEX session_device_completed")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v5_device_last_backup'")
        }
        let migrated = try await BackupStore(databaseURL: directory.databaseURL)
        #expect(try await migrated.lastCompletedSession(deviceKey: phone.device.id) == before)
        #expect(try await directory.database().read { db in
            try db.indexes(on: "backup_session").contains { $0.name == "session_device_completed" }
        })
    }

    private func complete(_ fixture: HistoryFixture, _ store: BackupStore) async throws -> UUID {
        let id = try await fixture.begin(store)
        try await store.recordVerified(sessionID: id, record: fixture.record(0))
        try await store.recordVerified(sessionID: id, record: fixture.record(1))
        try await store.finishSession(id: id, result: BackupSnapshot(
            phase: .completed, completedAssets: 1, verifiedResources: 2, verifiedBytes: 8
        ))
        return id
    }
}
