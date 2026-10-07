import BackupEngine
import BackupPersistence
import Foundation
import Testing
@testable import CloakRoll

@Suite("Offline backup history", .timeLimit(.minutes(1)))
@MainActor
struct BackupHistoryLoadingTests {
    @Test func savedSessionsLoadWithoutADeviceOrDestinationLease() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        try await fixture.accept(catalog)
        try await fixture.backup(catalog)
        let scopedAccess = fixture.destinationFixture.scope.counts
        let reopened = LibraryBackupPersistence(databaseURL: fixture.databaseURL)
        await reopened.loadSessions()
        let session = try #require(reopened.recentSessions.first)
        #expect(session.deviceName == catalog.device.name && session.status == .completed)
        #expect(session.completedAssets == 1 && session.verifiedBytes == 3)
        #expect(reopened.hasLoadedSessions && !reopened.isLoadingSessions && reopened.sessionErrorMessage == nil)
        #expect(fixture.destinationFixture.scope.counts.started == scopedAccess.started)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }

    @Test func failedOpenPreservesTheDatabaseAndRetryCanLoadItLater() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CloakRollHistory-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appendingPathComponent("Backups.sqlite")
        let invalid = Data("deliberately invalid test history".utf8)
        try invalid.write(to: database)
        let persistence = LibraryBackupPersistence(databaseURL: database)
        await persistence.loadSessions()
        #expect(persistence.sessionErrorMessage != nil && !persistence.hasLoadedSessions)
        #expect(persistence.recentSessions.isEmpty && !persistence.isLoadingSessions)
        #expect(try Data(contentsOf: database) == invalid)
        // The fixture explicitly removes its own invalid file; the production loader never does.
        try FileManager.default.removeItem(at: database)
        await persistence.loadSessions()
        #expect(persistence.sessionErrorMessage == nil && persistence.hasLoadedSessions)
        #expect(persistence.recentSessions.isEmpty && !persistence.isLoadingSessions)
    }

    @Test func refreshFailureRetainsLastGoodSessionsAndRetryClearsError() async throws {
        let first = historySession()
        let latest = historySession()
        let script = HistoryReadScript([.success([first]), .failure(HistoryReadError.unavailable), .success([latest])])
        let persistence = LibraryBackupPersistence(databaseURL: unusedHistoryURL(), readSessions: { _, _ in try await script.next() })
        await persistence.loadSessions()
        #expect(persistence.recentSessions == [first])
        await persistence.loadSessions()
        #expect(persistence.recentSessions == [first] && persistence.sessionErrorMessage != nil)
        #expect(persistence.hasLoadedSessions && !persistence.isLoadingSessions)
        await persistence.loadSessions()
        #expect(persistence.recentSessions == [latest] && persistence.sessionErrorMessage == nil)
    }

    @Test func overlappingInitialLoadsMakeOnlyOneRead() async throws {
        let reader = ControlledHistoryReader()
        let persistence = LibraryBackupPersistence(databaseURL: unusedHistoryURL(), readSessions: { _, _ in try await reader.read() })
        let first = Task { await persistence.loadSessions() }
        try await reader.waitForRequests(1)
        #expect(persistence.isLoadingSessions)
        await persistence.loadSessions()
        #expect(await reader.count == 1)
        await reader.finish(0, result: .success([]))
        await first.value
        #expect(persistence.hasLoadedSessions && !persistence.isLoadingSessions)
    }

    @Test(arguments: [false, true])
    func olderRefreshCannotReplaceNewerSessionsOrPublishAnOldError(oldFails: Bool) async throws {
        let reader = ControlledHistoryReader()
        let persistence = LibraryBackupPersistence(databaseURL: unusedHistoryURL(), readSessions: { _, _ in try await reader.read() })
        let old = Task { try? await persistence.refreshSessions() }
        try await reader.waitForRequests(1)
        let current = Task { try await persistence.refreshSessions() }
        try await reader.waitForRequests(2)
        let latest = historySession()
        await reader.finish(1, result: .success([latest]))
        try await current.value
        #expect(persistence.recentSessions == [latest] && !persistence.isLoadingSessions)
        await reader.finish(0, result: oldFails ? .failure(HistoryReadError.unavailable) : .success([historySession()]))
        await old.value
        #expect(persistence.recentSessions == [latest])
        #expect(persistence.sessionErrorMessage == nil && !persistence.isLoadingSessions)
    }

    @Test func filterChangeClearsPreviousRowsAndFencesAnOlderRead() async throws {
        let reader = ControlledHistoryReader()
        let persistence = LibraryBackupPersistence(databaseURL: unusedHistoryURL(), readSessions: { _, _ in try await reader.read() })
        let old = Task { await persistence.loadSessions() }
        try await reader.waitForRequests(1)
        let filter = BackupHistoryFilter(deviceKey: "another-phone", outcome: .unfinished)
        let current = Task { await persistence.applySessionFilter(filter) }
        try await reader.waitForRequests(2)
        #expect(persistence.sessionFilter == filter && persistence.recentSessions.isEmpty)
        await reader.finish(0, result: .success([historySession()]))
        await old.value
        #expect(persistence.recentSessions.isEmpty && persistence.isLoadingSessions)
        let latest = historySession()
        await reader.finish(1, result: .success([latest]))
        await current.value
        #expect(persistence.recentSessions == [latest] && persistence.hasLoadedSessions)
    }

    @Test func failedFilterReadNeverShowsUnfilteredRowsAndRetryKeepsTheFilter() async throws {
        let first = historySession()
        let script = HistoryReadScript([.success([first]), .failure(HistoryReadError.unavailable), .success([])])
        let filter = BackupHistoryFilter(deviceKey: "selected-phone")
        let persistence = LibraryBackupPersistence(databaseURL: unusedHistoryURL(), readSessions: { request, _ in
            let result = try await script.next()
            if result.sessions.isEmpty { #expect(request == filter) }
            return result
        })
        await persistence.loadSessions()
        #expect(persistence.recentSessions == [first])
        await persistence.applySessionFilter(filter)
        #expect(persistence.sessionFilter == filter && persistence.recentSessions.isEmpty)
        #expect(persistence.sessionErrorMessage != nil && !persistence.hasLoadedSessions)
        await persistence.loadSessions()
        #expect(persistence.sessionFilter == filter && persistence.recentSessions.isEmpty)
        #expect(persistence.sessionErrorMessage == nil && persistence.hasLoadedSessions)
    }

    @Test func historyLoadsAtMostOneHundredLatestSessions() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        let context = try await LibraryBackupPersistence.prepare(source: catalog.source, assets: [catalog.asset], device: catalog.device)
        let store = try await fixture.persistence.store()
        let destinationID = UUID()
        var identifiers: [UUID] = []
        for _ in 0..<101 {
            let id = try await store.beginSession(
                device: catalog.device, destinationID: destinationID, sourceSessionID: catalog.source.sessionID,
                assets: [catalog.asset], identity: context.identity
            )
            try await store.finishSession(id: id, result: BackupSnapshot(phase: .cancelled))
            identifiers.append(id)
        }
        await fixture.persistence.loadSessions()
        #expect(fixture.persistence.recentSessions.count == 100)
        #expect(Set(fixture.persistence.recentSessions.map(\.id)) == Set(identifiers.suffix(100)))
        #expect(fixture.persistence.recentSessions.allSatisfy { $0.status == .cancelled && $0.verifiedResources == 0 })
        #expect(fixture.persistence.hasOlderSessions)
        await fixture.persistence.loadOlderSessions()
        #expect(fixture.persistence.sessionPageIndex == 1 && !fixture.persistence.hasOlderSessions)
        #expect(fixture.persistence.recentSessions.map(\.id) == [identifiers[0]])
        await fixture.persistence.loadNewerSessions()
        #expect(fixture.persistence.sessionPageIndex == 0 && fixture.persistence.recentSessions.count == 100)

    }
}

private func unusedHistoryURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Unused.sqlite")
}

private func historySession() -> StoredBackupSession {
    StoredBackupSession(
        id: UUID(), deviceName: "Fixture iPhone", destinationID: UUID(), status: .completed,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000), finishedAt: Date(timeIntervalSince1970: 1_700_000_005),
        totalAssets: 1, totalResources: 1, completedAssets: 1, verifiedResources: 1, verifiedBytes: 3, transferredBytes: 3
    )
}

private enum HistoryReadError: Error { case unavailable }

private actor HistoryReadScript {
    private var values: [Result<[StoredBackupSession], Error>]
    init(_ values: [Result<[StoredBackupSession], Error>]) { self.values = values }
    func next() throws -> BackupHistoryPage { try BackupHistoryPage(sessions: values.removeFirst().get()) }
}

private actor ControlledHistoryReader {
    private var pending: [Int: CheckedContinuation<BackupHistoryPage, Error>] = [:]
    private(set) var count = 0

    func read() async throws -> BackupHistoryPage {
        let index = count
        count += 1
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }

    func finish(_ index: Int, result: Result<[StoredBackupSession], Error>) {
        pending.removeValue(forKey: index)?.resume(with: result.map { BackupHistoryPage(sessions: $0) })
    }

    func waitForRequests(_ expected: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while count < expected, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(count >= expected)
    }
}
