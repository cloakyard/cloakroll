import BackupEngine
import BackupPersistence
import Foundation
import Testing

@Suite("Saved original library")
struct SavedLibraryTests {
    @Test func repeatsDeduplicateResourcesButKeepCompanionsAndPartialCounts() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let first = try await fixture.begin(store)
        try await store.recordVerified(sessionID: first, record: fixture.record())
        try await store.finishSession(id: first, result: .init(phase: .failed))
        let query = SavedLibraryQuery(deviceKey: fixture.device.id, destinationID: fixture.destinationID)
        let partial = try #require(try await store.savedLibrary(query: query).items.first)
        #expect(partial.originals.count == 1 && partial.expectedOriginals == 2)
        #expect(partial.kind == .livePhoto)
        #expect(partial.capturedAt == fixture.assets[0].createdAt)
        let repeatID = try await fixture.begin(store)
        for index in 0..<2 { try await store.recordVerified(sessionID: repeatID, record: fixture.record(index)) }
        // In-flight records must not replace settled evidence.
        #expect(try await store.savedLibrary(query: query).items.first?.originals.count == 1)
        try await store.finishSession(id: repeatID, result: .init(phase: .completed, completedAssets: 1,
                                                               verifiedResources: 2, verifiedBytes: 8))
        let page = try await store.savedLibrary(query: query)
        #expect(page.items.count == 1 && page.items.first?.originals.count == 2)
        #expect(page.items.first?.originals.first?.filename == "IMG_0001.HEIC")
        #expect(try await store.savedLibrary(query: .init(deviceKey: "other", destinationID: fixture.destinationID)).items.isEmpty)
        #expect(try await store.savedLibrary(query: .init(deviceKey: fixture.device.id, destinationID: UUID())).items.isEmpty)
    }

    @Test func pagingAndDateTypeFiltersStayScoped() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let destination = UUID()
        for index in 1...5 {
            let fixture = HistoryFixture(destinationID: destination, date: Date(timeIntervalSince1970: Double(index)))
            let id = try await fixture.begin(store)
            try await store.recordVerified(sessionID: id, record: fixture.record())
            try await store.finishSession(id: id, result: .init(phase: .failed))
        }
        let key = HistoryFixture().device.id
        let query = SavedLibraryQuery(deviceKey: key, destinationID: destination)
        let first = try await store.savedLibrary(query: query, limit: 2)
        let second = try await store.savedLibrary(query: query, after: first.nextCursor, limit: 2)
        let third = try await store.savedLibrary(query: query, after: second.nextCursor, limit: 2)
        #expect(Set((first.items + second.items + third.items).map(\.id)).count == 5)
        #expect(third.nextCursor == nil)
        #expect(first.items.first?.capturedAt == Date(timeIntervalSince1970: 5))
        let filtered = SavedLibraryQuery(deviceKey: key, destinationID: destination, kind: .livePhoto,
                                        capturedAfter: Date(timeIntervalSince1970: 2), capturedBefore: Date(timeIntervalSince1970: 4))
        #expect(try await store.savedLibrary(query: filtered).items.count == 2)
        await #expect(throws: BackupStoreError.invalidRecord) {
            try await store.savedLibrary(query: filtered, after: first.nextCursor)
        }
    }
}
