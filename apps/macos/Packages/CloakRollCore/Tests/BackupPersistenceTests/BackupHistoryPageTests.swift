import BackupEngine
import Foundation
import GRDB
import Testing
@testable import BackupPersistence

@Suite("Bounded backup history pages")
struct BackupHistoryPageTests {
    @Test(arguments: [0, 100, 101, 200, 201])
    func visitsEverySessionExactlyOnce(count: Int) async throws {
        let fixture = try await HistoryPageFixture(count: count)
        defer { fixture.directory.remove() }
        var cursor: BackupHistoryCursor?
        var ids: [UUID] = []
        repeat {
            let page = try await fixture.store.sessionPage(after: cursor)
            #expect(page.sessions.count <= 100)
            ids += page.sessions.map(\.id)
            cursor = page.nextCursor
        } while cursor != nil && ids.count <= count
        #expect(ids == fixture.ids.reversed())
        #expect(Set(ids).count == count)
    }

    @Test func tiedDatesAndSubDatePrecisionDoNotRepeatBoundaryRows() async throws {
        let fixture = try await HistoryPageFixture(count: 17, tiedTimestamp: 100.00000001)
        defer { fixture.directory.remove() }
        var cursor: BackupHistoryCursor?
        var ids: [UUID] = []
        repeat {
            let page = try await fixture.store.sessionPage(limit: 3, after: cursor)
            ids += page.sessions.map(\.id)
            cursor = page.nextCursor
        } while cursor != nil && ids.count <= 17
        #expect(ids == fixture.ids.reversed())
    }

    @Test func newSessionsDoNotShiftAnExistingPageBoundary() async throws {
        let fixture = try await HistoryPageFixture(count: 7)
        defer { fixture.directory.remove() }
        let first = try await fixture.store.sessionPage(limit: 3)
        let cursor = try #require(first.nextCursor)
        let newID = try await HistoryFixture().begin(fixture.store)
        let older = try await fixture.store.sessionPage(limit: 3, after: cursor)
        #expect(older.sessions.map(\.id) == Array(fixture.ids[1...3].reversed()))
        #expect(try await fixture.store.sessionPage(limit: 1).sessions.first?.id == newID)
    }

    @Test func filtersApplyBeforePagingAndCannotReuseAnotherFiltersCursor() async throws {
        let fixture = try await HistoryPageFixture(count: 9)
        defer { fixture.directory.remove() }
        let otherPhone = HistoryFixture(deviceValue: "second-phone")
        _ = try await otherPhone.begin(fixture.store)
        let filter = BackupHistoryFilter(deviceKey: fixture.deviceKey, outcome: .unfinished)
        let first = try await fixture.store.sessionPage(limit: 4, filter: filter)
        let cursor = try #require(first.nextCursor)
        let second = try await fixture.store.sessionPage(limit: 4, filter: filter, after: cursor)
        #expect(first.sessions.map(\.id) == fixture.ids.suffix(4).reversed())
        #expect(second.sessions.map(\.id) == fixture.ids[1...4].reversed())
        #expect(try await fixture.store.sessionPage(filter: .init(outcome: .completed)).sessions.isEmpty)
        await #expect(throws: BackupStoreError.self) { try await fixture.store.sessionPage(after: cursor) }
        await #expect(throws: BackupStoreError.self) {
            try await fixture.store.sessionPage(filter: .init(deviceKey: otherPhone.device.id, outcome: .unfinished), after: cursor)
        }
    }

    @Test func limitsRemainBoundedAtBothExtremes() async throws {
        let fixture = try await HistoryPageFixture(count: 205)
        defer { fixture.directory.remove() }
        #expect(try await fixture.store.sessionPage(limit: Int.min).sessions.count == 1)
        #expect(try await fixture.store.sessionPage(limit: Int.max).sessions.count == 200)
        #expect(try await fixture.store.sessionPage(limit: 200).nextCursor != nil)
        #expect(try await fixture.store.recentSessions(limit: 0).isEmpty)
    }

    @Test func migrationPreservesHistoryAndBothQueriesUseOrderedIndexes() async throws {
        let fixture = try await HistoryPageFixture(count: 1_005)
        defer { fixture.directory.remove() }
        let queue = try fixture.directory.database()
        try await queue.write { db in
            try db.execute(sql: """
                DROP INDEX session_history_page;
                DROP INDEX session_device_history_page;
                CREATE INDEX session_recent ON backup_session(started_at DESC);
                DELETE FROM grdb_migrations WHERE identifier = 'v6_history_pages';
                """)
        }
        let reopened = try await BackupStore(databaseURL: fixture.directory.databaseURL)
        #expect(try await reopened.sessionPage().sessions.map(\.id) == fixture.ids.suffix(100).reversed())
        try await reopened.database.read { db in
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backup_session") == 1_005)
            for deviceClause in ["", "device_key = 'persistent:device-one' AND "] {
                let plans = try Row.fetchAll(db, sql: """
                    EXPLAIN QUERY PLAN SELECT * FROM backup_session
                    WHERE \(deviceClause)(started_at, id) < (123, 'boundary')
                    ORDER BY started_at DESC, id DESC LIMIT 101
                    """).map { row -> String in row["detail"] }
                #expect(plans.contains { $0.contains(deviceClause.isEmpty ? "session_history_page" : "session_device_history_page") })
                #expect(!plans.contains { $0.contains("TEMP B-TREE") }, "\(plans)")
            }
        }
    }
}

private struct HistoryPageFixture {
    let directory = HistoryDirectory()
    let store: BackupStore
    let ids: [UUID]
    let deviceKey: String

    init(count: Int, tiedTimestamp: Double? = nil) async throws {
        store = try await BackupStore(databaseURL: directory.databaseURL)
        let source = HistoryFixture()
        deviceKey = source.device.id
        let seed = try await source.begin(store)
        ids = (0..<count).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
        let identifiers = ids
        try await directory.database().write { db in
            for (offset, id) in identifiers.enumerated() {
                try db.execute(sql: """
                    INSERT INTO backup_session
                    (id, device_key, device_name, destination_id, source_session_id, status, started_at, finished_at,
                     total_assets, total_resources, expected_bytes)
                    SELECT ?, device_key, device_name, destination_id, source_session_id, 'cancelled', ?, ?,
                        total_assets, total_resources, expected_bytes FROM backup_session WHERE id = ?
                    """, arguments: [id.uuidString, tiedTimestamp ?? Double(offset), Double(offset + 1), seed.uuidString])
            }
            try db.execute(sql: "DELETE FROM session_resource WHERE session_id = ?", arguments: [seed.uuidString])
            try db.execute(sql: "DELETE FROM backup_session WHERE id = ?", arguments: [seed.uuidString])
        }
    }
}
