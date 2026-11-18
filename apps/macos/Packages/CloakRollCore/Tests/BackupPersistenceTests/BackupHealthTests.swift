import BackupEngine
import BackupPersistence
import Foundation
import Testing

@Suite("Backup health evidence")
struct BackupHealthTests {
    @Test func sourceIdentitySurvivesANewAttemptAndSeparatesPhonesAndFolders() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let first = HistoryFixture()
        let original = try await first.begin(store)
        let sourceID = try #require(try await store.backupHealth().first).id
        let latest = try await first.begin(store)
        let refreshed = try #require(try await store.backupHealth().first)
        #expect(refreshed.id == sourceID)
        #expect(refreshed.latestSession.id == latest && latest != original)
        _ = try await HistoryFixture(deviceValue: "another-phone", destinationID: first.destinationID).begin(store)
        _ = try await HistoryFixture().begin(store)
        let sources = try await store.backupHealth()
        #expect(sources.count == 3 && Set(sources.map(\.id)).count == 3)
    }

    @Test func emptyAndUncheckedHistoryNeverInventsAHealthyCheck() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        #expect(try await store.backupHealth().isEmpty)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        try await store.finishSession(id: id, result: .init(phase: .cancelled))
        let entry = try #require(try await store.backupHealth().first)
        #expect(entry.lastCompletedAt == nil)
        #expect(entry.integrityCheck == nil)
        #expect(entry.latestSession.status == .cancelled)
        await #expect(throws: BackupStoreError.invalidRecord) {
            try await store.recordIntegrityCheck(sessionID: id, result: .init(totalFiles: 0))
        }
    }

    @Test func completedCheckSurvivesReopenAndDoesNotChangeBackupOutcome() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        try await store.recordVerified(sessionID: id, record: fixture.record())
        try await store.finishSession(id: id, result: .init(phase: .failed))
        var check = SavedBackupCheckProgress(totalFiles: 1)
        await #expect(throws: BackupStoreError.invalidRecord) {
            try await store.recordIntegrityCheck(sessionID: id, result: check)
        }
        check.checkedFiles = 1
        check.matchingFiles = 0
        try await store.recordIntegrityCheck(sessionID: id, result: check, at: Date(timeIntervalSince1970: 300))
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        let entry = try #require(try await reopened.backupHealth().first)
        #expect(entry.latestSession.status == .failed)
        #expect(entry.lastCompletedAt == nil)
        #expect(entry.integrityCheck?.checkedAt == Date(timeIntervalSince1970: 300))
        #expect(entry.integrityCheck?.matchingFiles == 0)
        check.matchingFiles = 1
        try await reopened.recordIntegrityCheck(sessionID: id, result: check, at: Date(timeIntervalSince1970: 200))
        #expect(try await reopened.backupHealth().first?.integrityCheck?.matchingFiles == 0)
    }

    @Test func deviceAndDestinationRemainSeparate() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let first = HistoryFixture()
        _ = try await first.begin(store)
        _ = try await HistoryFixture(destinationID: first.destinationID).begin(store)
        _ = try await HistoryFixture(deviceValue: "another-phone", destinationID: first.destinationID).begin(store)
        _ = try await HistoryFixture().begin(store)
        #expect(try await store.backupHealth().count == 3)
    }
}
