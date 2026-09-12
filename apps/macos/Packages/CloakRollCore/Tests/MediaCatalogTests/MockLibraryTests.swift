import Foundation
import MediaCatalog
import MediaModels
import Testing

@Suite("Sample catalog")
struct MockLibraryTests {
    @Test func fixturesAreDeterministicAndPreserveOriginalCompanions() {
        let first = MockLibrary.make(count: 1_024)
        let second = MockLibrary.make(count: 1_024)
        #expect(first == second)
        #expect(first.device.id == "sample-device")
        #expect(first.assets.count == 1_024)
        #expect(Set(first.assets.map(\.id)).count == 1_024)
        #expect(Set(first.assets.map(\.kind)) == Set(MediaKind.allCases))
        #expect(first.assets.contains { $0.createdAt == nil })
        #expect(Set(first.statuses.values) == [.backedUp, .notBackedUp])
        #expect(first.assets.filter { $0.kind == .livePhoto }.allSatisfy {
            $0.resources.map { URL(fileURLWithPath: $0.filename).pathExtension } == ["HEIC", "MOV"]
        })
        #expect(first.assets.filter { $0.kind == .raw }.allSatisfy {
            $0.resources.map { URL(fileURLWithPath: $0.filename).pathExtension } == ["DNG", "JPG"]
        })
    }

    @Test(arguments: [0, -1])
    func nonpositiveSampleCountIsEmpty(count: Int) {
        let library = MockLibrary.make(count: count)
        #expect(library.assets.isEmpty)
        #expect(library.statuses.isEmpty)
        #expect(library.backupDates.isEmpty)
    }

    @Test func largeProjectionPreservesEveryAssetAndCompanion() async throws {
        let library = MockLibrary.make(count: 100_000)
        let start = ContinuousClock.now
        let snapshot = try await CatalogProjector().project(
            assets: library.assets,
            statuses: library.statuses,
            backupDates: library.backupDates,
            query: CatalogQuery()
        )
        let elapsed = start.duration(to: .now)
        print("100,000-item metadata projection: \(elapsed)")
        #expect(snapshot.totalCount == 100_000)
        #expect(snapshot.filteredCount == 100_000)
        #expect(Set(snapshot.orderedIDs).count == 100_000)
        #expect(snapshot.sections.flatMap(\.assets).reduce(0) { $0 + $1.resources.count }
                == library.assets.reduce(0) { $0 + $1.resources.count })
        #expect(snapshot.grouping == .year)
        #expect(snapshot.sections.count < 40)
        #expect(snapshot.newCount == 25_000)
    }

    @Test(arguments: [1_024, 2_001])
    func automaticGroupingScalesWithoutLosingItems(count: Int) async throws {
        let library = MockLibrary.make(count: count)
        let snapshot = try await CatalogProjector().project(
            assets: library.assets, statuses: library.statuses, backupDates: library.backupDates, query: CatalogQuery()
        )
        #expect(snapshot.filteredCount == count)
        #expect(snapshot.grouping == (count <= 2_000 ? .day : .month))
        #expect(snapshot.sections.allSatisfy { $0.grouping == snapshot.grouping })
    }
}
