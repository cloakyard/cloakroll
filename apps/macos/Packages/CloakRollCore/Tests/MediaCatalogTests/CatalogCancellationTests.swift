import Foundation
import MediaCatalog
import MediaModels
import Testing

@Suite("Catalog cancellation")
struct CatalogCancellationTests {
    @Test func aCancelledEmptyProjectionThrowsInsteadOfReturningAnEmptyLibrary() async {
        let projector = CatalogProjector()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await projector.project(assets: [], statuses: [:], backupDates: [:], query: CatalogQuery())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancelledLargeQueriesLeaveTheProjectorAvailableForTheCurrentQuery() async throws {
        let projector = CatalogProjector()
        let library = MockLibrary.make(count: 10_000)
        let cancelledCount = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for index in 0..<16 {
                group.addTask {
                    // Cancel within each child before the actor hop. This makes the superseded
                    // queue deterministic, without elapsed-time assertions or scheduling sleeps.
                    withUnsafeCurrentTask { $0?.cancel() }
                    do {
                        _ = try await projector.project(
                            assets: library.assets, statuses: library.statuses, backupDates: library.backupDates,
                            query: CatalogQuery(search: "superseded-\(index)")
                        )
                        return false
                    } catch is CancellationError {
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var count = 0
            for await cancelled in group where cancelled { count += 1 }
            return count
        }
        #expect(cancelledCount == 16)

        let current = try await projector.project(
            assets: library.assets, statuses: library.statuses, backupDates: library.backupDates,
            query: CatalogQuery(filter: .videos)
        )
        #expect(current.totalCount == 10_000)
        #expect(current.filteredCount == current.counts[.videos])
        #expect(current.sections.flatMap(\.assets).allSatisfy { $0.kind == .video })
    }
}
