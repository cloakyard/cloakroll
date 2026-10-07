import BackupEngine
import BackupPersistence
import Foundation
import Testing
@testable import CloakRoll

@Suite("Backup history page navigation", .timeLimit(.minutes(1)))
@MainActor
struct BackupHistoryPagingTests {
    @Test func navigationStaysBoundedAndRefreshReturnsToTheLatestPage() async throws {
        let fixture = try await PagingFixture()
        // The injected reader uses single-row pages; the production reader's 100-row
        // boundary is exercised separately against 101 actual stored sessions.
        let script = PagingScript(fixture.pages.map { .success($0) } + [.success(fixture.pages[1]), .success(fixture.pages[0])])
        let subject = fixture.subject { _, cursor in try await script.read(cursor) }
        await subject.loadSessions()
        #expect(subject.sessionPageIndex == 0 && subject.hasOlderSessions)
        await subject.loadNewerSessions()
        await subject.loadOlderSessions()
        #expect(subject.sessionPageIndex == 1 && subject.recentSessions == fixture.pages[1].sessions)
        await subject.loadOlderSessions()
        #expect(subject.sessionPageIndex == 2 && !subject.hasOlderSessions)
        await subject.loadOlderSessions()
        #expect(await script.cursors.count == 3)
        await subject.loadNewerSessions()
        #expect(subject.sessionPageIndex == 1 && subject.recentSessions == fixture.pages[1].sessions)
        await subject.loadSessions()
        #expect(subject.sessionPageIndex == 0 && subject.recentSessions == fixture.pages[0].sessions)
        #expect(await script.cursors == [nil, fixture.pages[0].nextCursor, fixture.pages[1].nextCursor,
                                       fixture.pages[0].nextCursor, nil])
    }

    @Test func failedOlderPageRetainsRowsAndRetriesThatExactPage() async throws {
        let fixture = try await PagingFixture()
        let script = PagingScript([.success(fixture.pages[0]), .failure(PagingError.unavailable), .success(fixture.pages[1])])
        let subject = fixture.subject { _, cursor in try await script.read(cursor) }
        await subject.loadSessions()
        await subject.loadOlderSessions()
        #expect(subject.sessionPageIndex == 0 && subject.recentSessions == fixture.pages[0].sessions)
        #expect(subject.sessionErrorMessage != nil && subject.hasOlderSessions && !subject.isLoadingSessions)
        await subject.retrySessions()
        #expect(subject.sessionErrorMessage == nil && subject.sessionPageIndex == 1)
        #expect(subject.recentSessions == fixture.pages[1].sessions)
        #expect(await script.cursors == [nil, fixture.pages[0].nextCursor, fixture.pages[0].nextCursor])
    }

    @Test(arguments: [false, true])
    func filterChangeFencesOlderPageAndItsFailure(oldFails: Bool) async throws {
        let fixture = try await PagingFixture()
        let reader = PendingPageReader()
        let subject = fixture.subject { _, _ in try await reader.read() }
        let initial = Task { await subject.loadSessions() }
        try await reader.wait(1)
        await reader.finish(0, .success(fixture.pages[0]))
        await initial.value
        let older = Task { await subject.loadOlderSessions() }
        try await reader.wait(2)
        await subject.loadOlderSessions()
        #expect(await reader.count == 2)
        let filtered = Task { await subject.applySessionFilter(.init(deviceKey: "another-phone")) }
        try await reader.wait(3)
        #expect(subject.recentSessions.isEmpty && subject.sessionPageIndex == 0 && !subject.hasOlderSessions)
        await reader.finish(2, .success(.init(sessions: [])))
        await filtered.value
        await reader.finish(1, oldFails ? .failure(PagingError.unavailable) : .success(fixture.pages[1]))
        await older.value
        #expect(subject.recentSessions.isEmpty && subject.hasLoadedSessions && !subject.isLoadingSessions)
        #expect(subject.sessionErrorMessage == nil && !subject.hasOlderSessions)
    }

    @Test func cancelledPageCannotPublishRowsAndLeavesNavigationAvailable() async throws {
        let fixture = try await PagingFixture()
        let reader = PendingPageReader()
        let subject = fixture.subject { _, _ in try await reader.read() }
        let initial = Task { await subject.loadSessions() }
        try await reader.wait(1)
        await reader.finish(0, .success(fixture.pages[0]))
        await initial.value
        let older = Task { await subject.loadOlderSessions() }
        try await reader.wait(2)
        older.cancel()
        await reader.finish(1, .success(fixture.pages[1]))
        await older.value
        #expect(subject.recentSessions == fixture.pages[0].sessions && subject.sessionPageIndex == 0)
        #expect(subject.hasOlderSessions && subject.sessionErrorMessage == nil && !subject.isLoadingSessions)
    }

    @Test func emptyOlderPageReloadsLatestInsteadOfStrandingNavigation() async throws {
        let fixture = try await PagingFixture()
        let script = PagingScript([.success(fixture.pages[0]), .success(.init(sessions: [])),
                                   .success(.init(sessions: fixture.pages[0].sessions))])
        let subject = fixture.subject { _, cursor in try await script.read(cursor) }
        await subject.loadSessions()
        await subject.loadOlderSessions()
        #expect(subject.sessionPageIndex == 0 && !subject.hasOlderSessions && !subject.isLoadingSessions)
        #expect(subject.recentSessions == fixture.pages[0].sessions && subject.sessionErrorMessage == nil)
        #expect(await script.cursors == [nil, fixture.pages[0].nextCursor, nil])
    }

    @Test func filterFromOlderPageStartsFreshAndFailedRefreshCanRetryLatest() async throws {
        let fixture = try await PagingFixture()
        let script = PagingScript([.success(fixture.pages[0]), .success(fixture.pages[1]),
                                   .failure(PagingError.unavailable), .success(fixture.pages[0]), .success(.init(sessions: []))])
        let subject = fixture.subject { _, cursor in try await script.read(cursor) }
        await subject.loadSessions()
        await subject.loadOlderSessions()
        await subject.loadSessions()
        #expect(subject.sessionPageIndex == 1 && subject.recentSessions == fixture.pages[1].sessions)
        await subject.retrySessions()
        #expect(subject.sessionPageIndex == 0 && subject.sessionErrorMessage == nil)
        await subject.applySessionFilter(.init(outcome: .completed))
        #expect(subject.recentSessions.isEmpty && subject.sessionPageIndex == 0 && !subject.hasOlderSessions)
        #expect(await script.cursors == [nil, fixture.pages[0].nextCursor, nil, nil, nil])
    }
}

@MainActor
private struct PagingFixture {
    let library: PersistentLibraryFixture
    let pages: [BackupHistoryPage]

    init() async throws {
        library = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        let context = try await LibraryBackupPersistence.prepare(source: catalog.source, assets: [catalog.asset], device: catalog.device)
        let store = try await library.persistence.store()
        for _ in 0..<3 {
            let id = try await store.beginSession(device: catalog.device, destinationID: UUID(), sourceSessionID: catalog.source.sessionID,
                                                 assets: [catalog.asset], identity: context.identity)
            try await store.finishSession(id: id, result: BackupSnapshot(phase: .cancelled))
        }
        let first = try await store.sessionPage(limit: 1)
        let second = try await store.sessionPage(limit: 1, after: first.nextCursor)
        let third = try await store.sessionPage(limit: 1, after: second.nextCursor)
        pages = [first, second, third]
    }

    func subject(reader: @escaping LibraryBackupPersistence.SessionReader) -> LibraryBackupPersistence {
        LibraryBackupPersistence(databaseURL: library.databaseURL, readSessions: reader)
    }
}

private enum PagingError: Error { case unavailable }

private actor PagingScript {
    var values: [Result<BackupHistoryPage, Error>]
    private(set) var cursors: [BackupHistoryCursor?] = []
    init(_ values: [Result<BackupHistoryPage, Error>]) { self.values = values }
    func read(_ cursor: BackupHistoryCursor?) throws -> BackupHistoryPage {
        cursors.append(cursor)
        return try values.removeFirst().get()
    }
}

private actor PendingPageReader {
    private var pending: [Int: CheckedContinuation<BackupHistoryPage, Error>] = [:]
    private(set) var count = 0
    func read() async throws -> BackupHistoryPage {
        let index = count
        count += 1
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func finish(_ index: Int, _ result: Result<BackupHistoryPage, Error>) { pending.removeValue(forKey: index)?.resume(with: result) }
    func wait(_ expected: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while count < expected, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(count >= expected)
    }
}
