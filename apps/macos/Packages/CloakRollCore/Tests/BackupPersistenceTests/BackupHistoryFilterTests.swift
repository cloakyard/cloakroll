import BackupEngine
import BackupPersistence
import Foundation
import GRDB
import Testing

@Suite("Backup history filters")
struct BackupHistoryFilterTests {
    @Test func identicalDeviceNamesRemainSeparateAndKeysAreBoundParameters() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let first = HistoryFixture(deviceValue: "phone' OR 1=1 --")
        let second = HistoryFixture(deviceValue: "second-phone")
        let firstID = try await first.begin(store)
        let secondID = try await second.begin(store)
        let devices = try await store.historyDevices()
        #expect(devices.count == 2 && Set(devices.map(\.name)) == ["iPhone"])
        #expect(Set(devices.map(\.id)) == [first.device.id, second.device.id])
        #expect(try await store.recentSessions(filter: .init(deviceKey: first.device.id)).map(\.id) == [firstID])
        #expect(try await store.recentSessions(filter: .init(deviceKey: second.device.id)).map(\.id) == [secondID])
        #expect(try await store.recentSessions(filter: .init(deviceKey: "unknown")).isEmpty)
    }

    @Test func deviceFilterPrecedesLimitAndDoesNotLoseOlderBackups() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let older = HistoryFixture(deviceValue: "older-phone")
        let olderID = try await older.begin(store)
        let newer = HistoryFixture(deviceValue: "newer-phone")
        for _ in 0..<101 { _ = try await newer.begin(store) }
        #expect(try await store.recentSessions(limit: 100).allSatisfy { $0.id != olderID })
        #expect(try await store.recentSessions(limit: 1, filter: .init(deviceKey: older.device.id)).map(\.id) == [olderID])
        #expect(try await store.historyDevices().count == 2)
        #expect(try await store.recentSessions(limit: -1, filter: .init(deviceKey: older.device.id)).isEmpty)
    }

    @Test func outcomesIncludeRunningAndPartialSessionsWithoutChangingEvidence() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let fixture = HistoryFixture()
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let complete = try await fixture.begin(store)
        try await store.recordVerified(sessionID: complete, record: fixture.record(0))
        try await store.recordVerified(sessionID: complete, record: fixture.record(1))
        try await store.finishSession(id: complete, result: BackupSnapshot(phase: .completed, completedAssets: 1, verifiedResources: 2, verifiedBytes: 8, transferredBytes: 8))
        let failed = try await fixture.begin(store)
        try await store.recordVerified(sessionID: failed, record: fixture.record(0))
        try await store.finishSession(id: failed, result: BackupSnapshot(phase: .failed, transferredBytes: 3))
        let stopped = try await fixture.begin(store)
        try await store.finishSession(id: stopped, result: BackupSnapshot(phase: .cancelled))
        let running = try await fixture.begin(store)
        let unfinished = try await store.recentSessions(filter: .init(deviceKey: fixture.device.id, outcome: .unfinished))
        #expect(Set(unfinished.map(\.id)) == [failed, stopped, running])
        #expect(unfinished.first { $0.id == failed }?.verifiedResources == 1)
        #expect(try await store.recentSessions(filter: .init(outcome: .completed)).map(\.id) == [complete])
        #expect(try await fixture.candidates(store).count == 2)
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        #expect(try await reopened.recentSessions(filter: .init(outcome: .unfinished)).first { $0.id == running }?.status == .interrupted)
    }

    @Test func outcomeFilterPrecedesLimitAndCanReturnNoMatches() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let fixture = HistoryFixture()
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let complete = try await fixture.begin(store)
        try await store.recordVerified(sessionID: complete, record: fixture.record(0))
        try await store.recordVerified(sessionID: complete, record: fixture.record(1))
        try await store.finishSession(id: complete, result: BackupSnapshot(phase: .completed, completedAssets: 1, verifiedResources: 2, verifiedBytes: 8))
        _ = try await fixture.begin(store)
        #expect(try await store.recentSessions(limit: 1, filter: .init(outcome: .completed)).map(\.id) == [complete])
        #expect(try await store.recentSessions(filter: .init(deviceKey: "absent", outcome: .unfinished)).isEmpty)
    }
}
