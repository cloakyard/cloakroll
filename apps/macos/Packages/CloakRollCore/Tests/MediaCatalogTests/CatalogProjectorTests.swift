import Foundation
import MediaCatalog
import MediaModels
import Testing

@Suite("Catalog projection")
struct CatalogProjectorTests {
    private let now = Date(timeIntervalSince1970: 1_789_214_400)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    @Test func emptyCatalogHasEverySidebarCount() async {
        let snapshot = await CatalogProjector().project(
            assets: [], statuses: [:], backupDates: [:], query: CatalogQuery()
        )
        #expect(snapshot == .empty)
        #expect(snapshot.counts.count == LibraryFilter.allCases.count)
    }

    @Test func backupCountsRemainConservativeAndIndependentOfSearch() async {
        let assets = [
            asset("photo", kind: .photo),
            asset("live", kind: .livePhoto),
            asset("raw", kind: .raw),
            asset("video", kind: .video),
            asset("other", kind: .other)
        ]
        let statuses: [String: BackupStatus] = [
            "live": .backedUp, "raw": .uncertain, "video": .failed, "other": .backedUp
        ]
        let snapshot = await CatalogProjector().project(
            assets: assets,
            statuses: statuses,
            backupDates: ["live": now, "other": now.addingTimeInterval(-30 * 86_400)],
            query: CatalogQuery(search: "live"),
            now: now,
            calendar: calendar
        )
        #expect(snapshot.counts == [
            .all: 5, .photos: 3, .videos: 1, .livePhotos: 1, .raw: 1,
            .notBackedUp: 3, .backedUp: 2, .recentlyBackedUp: 1
        ])
        #expect(snapshot.orderedIDs == ["live"])
        #expect(snapshot.filteredCount == 1)
        #expect(snapshot.totalCount == 5)
        #expect(snapshot.totalBytes == 500)
        #expect(snapshot.newCount == 3)
        #expect(snapshot.newBytes == 300)
    }

    @Test(arguments: LibraryFilter.allCases)
    func eachFilterMatchesItsFullCatalogCount(filter: LibraryFilter) async {
        let library = MockLibrary.make(count: 1_024, now: now)
        let snapshot = await CatalogProjector().project(
            assets: library.assets,
            statuses: library.statuses,
            backupDates: library.backupDates,
            query: CatalogQuery(filter: filter),
            now: now,
            calendar: calendar
        )
        #expect(snapshot.filteredCount == snapshot.counts[filter])
        #expect(snapshot.orderedIDs.count == Set(snapshot.orderedIDs).count)
    }

    @Test func searchesCompanionsWithoutSplittingTheAsset() async {
        let paired = MediaAsset(
            id: "paired", deviceID: "device",
            resources: [
                MediaResource(id: "still", filename: "IMG_0001.HEIC", byteCount: 100),
                MediaResource(id: "motion", filename: "Café.MOV", byteCount: 200)
            ],
            kind: .livePhoto, createdAt: now
        )
        let snapshot = await CatalogProjector().project(
            assets: [paired, asset("other")], statuses: [:], backupDates: [:],
            query: CatalogQuery(search: "  CAFE.mov\n")
        )
        #expect(snapshot.orderedIDs == ["paired"])
        #expect(snapshot.sections.first?.assets.first?.resources.count == 2)
        #expect(snapshot.sections.first?.assets.first?.byteCount == 300)
    }

    @Test(arguments: [CatalogSort.newestFirst, .oldestFirst])
    func unknownDatesSortLastAndEqualDatesHaveStableIDs(sort: CatalogSort) async {
        let date = now
        let assets = [
            asset("z", date: nil), asset("b", date: date), asset("a", date: date),
            asset("old", date: date.addingTimeInterval(-86_400)), asset("y", date: nil)
        ]
        let query = CatalogQuery(sort: sort)
        let projector = CatalogProjector()
        let first = await projector.project(assets: assets, statuses: [:], backupDates: [:], query: query)
        let second = await projector.project(assets: assets.reversed(), statuses: [:], backupDates: [:], query: query)
        #expect(first == second)
        #expect(first.orderedIDs == (sort == .newestFirst ? ["a", "b", "old", "y", "z"] : ["old", "a", "b", "y", "z"]))
        #expect(first.sections.last?.date == nil)
        #expect(first.sections.last?.id == "day:unknown")
    }

    @Test func daylightSavingTransitionUsesCalendarDays() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let dates = try [
            DateComponents(year: 2026, month: 3, day: 7, hour: 23, minute: 59),
            DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30),
            DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 30),
            DateComponents(year: 2026, month: 3, day: 9)
        ].map { try #require(calendar.date(from: $0)) }
        let assets = dates.enumerated().map { asset(String($0.offset), date: $0.element) }
        let snapshot = await CatalogProjector().project(
            assets: assets, statuses: [:], backupDates: [:], query: CatalogQuery(grouping: .day), calendar: calendar
        )
        #expect(snapshot.sections.map { $0.assets.count } == [1, 2, 1])
        #expect(snapshot.sections.map(\.id).count == Set(snapshot.sections.map(\.id)).count)
        let transition = try #require(snapshot.sections.dropFirst().first?.date)
        #expect(calendar.component(.day, from: transition) == 8)
        #expect(calendar.component(.hour, from: transition) == 0)
    }

    @Test func monthAndYearGroupingKeepBoundaryAndUnknownSeparate() async throws {
        let before = try #require(calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 23)))
        let after = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let later = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let assets = [asset("before", date: before), asset("after", date: after), asset("later", date: later), asset("unknown", date: nil)]
        let projector = CatalogProjector()
        let months = await projector.project(
            assets: assets, statuses: [:], backupDates: [:], query: CatalogQuery(grouping: .month), calendar: calendar
        )
        let years = await projector.project(
            assets: assets, statuses: [:], backupDates: [:], query: CatalogQuery(grouping: .year), calendar: calendar
        )
        #expect(months.sections.map { $0.assets.count } == [1, 1, 1, 1])
        #expect(years.sections.map { $0.assets.count } == [2, 1, 1])
        #expect(years.sections.first?.assets.map(\.id) == ["later", "after"])
        #expect(Set(months.sections.map(\.id)).isDisjoint(with: Set(years.sections.map(\.id))))
    }

    @Test func recentBackupsUseSevenCalendarDaysAndRequireConfirmedStatus() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 4)))
        let ids = ["start", "before", "now", "future", "missing", "uncertain"]
        let assets = ids.map { asset($0) }
        var statuses = Dictionary(uniqueKeysWithValues: ids.map { ($0, BackupStatus.backedUp) })
        statuses["uncertain"] = .uncertain
        let snapshot = await CatalogProjector().project(
            assets: assets,
            statuses: statuses,
            backupDates: ["start": start, "before": start.addingTimeInterval(-1), "now": now,
                          "future": now.addingTimeInterval(1), "uncertain": now],
            query: CatalogQuery(filter: .recentlyBackedUp),
            now: now,
            calendar: calendar
        )
        #expect(Set(snapshot.orderedIDs) == ["start", "now"])
        #expect(snapshot.counts[.recentlyBackedUp] == 2)
    }

    @Test func aggregateBytesDoNotOverflow() async {
        let large = (0..<2).map { index in
            MediaAsset(
                id: "\(index)", deviceID: "device",
                resources: [MediaResource(id: "\(index)", filename: "large.MOV", byteCount: .max)],
                kind: .video, createdAt: nil
            )
        }
        let snapshot = await CatalogProjector().project(
            assets: large, statuses: [:], backupDates: [:], query: CatalogQuery()
        )
        #expect(snapshot.newBytes == Int64.max)
        #expect(snapshot.totalBytes == Int64.max)
    }

    private func asset(_ id: String, kind: MediaKind = .photo, date: Date? = Date(timeIntervalSince1970: 1_789_214_400)) -> MediaAsset {
        MediaAsset(
            id: id, deviceID: "device",
            resources: [MediaResource(id: "\(id)-resource", filename: "\(id).HEIC", byteCount: 100)],
            kind: kind, createdAt: date
        )
    }
}
