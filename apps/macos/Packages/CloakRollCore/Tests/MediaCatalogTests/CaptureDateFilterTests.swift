import Foundation
import MediaCatalog
import MediaModels
import Testing

@Suite("Capture date filtering")
struct CaptureDateFilterTests {
    @Test(arguments: [(3, 8, 23), (11, 1, 25)])
    func wholeDaysRespectDaylightSaving(month: Int, day: Int, hours: Int) throws {
        let calendar = try calendar()
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
        let range = try #require(CaptureDateRange(from: date, through: date, calendar: calendar))
        #expect(range.end.timeIntervalSince(range.from) == Double(hours * 3_600))
        #expect(range.contains(range.from))
        #expect(range.contains(range.end.addingTimeInterval(-0.001)))
        #expect(!range.contains(range.from.addingTimeInterval(-0.001)))
        #expect(!range.contains(range.end))
        #expect(!range.contains(nil))
    }

    @Test func invalidRangesAreRejectedButTimeOrderWithinOneDayIsAllowed() throws {
        let calendar = try calendar()
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 7)))
        #expect(CaptureDateRange(from: day.addingTimeInterval(3_600), through: day, calendar: calendar) != nil)
        #expect(CaptureDateRange(from: day.addingTimeInterval(86_400), through: day, calendar: calendar) == nil)
        #expect(CaptureDateRange(from: Date(timeIntervalSince1970: .infinity), through: day) == nil)
        #expect(CaptureDateRange(from: day, through: Date(timeIntervalSince1970: .nan)) == nil)
    }

    @Test func filtersComposeAndKeepCompleteCompanionsAndFullSidebarCounts() async throws {
        let calendar = try calendar()
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 7)))
        let range = try #require(CaptureDateRange(from: day, through: day, calendar: calendar))
        let live = MediaAsset(id: "live", deviceID: "phone", resources: [
            MediaResource(id: "still", filename: "IMG.HEIC", byteCount: 60),
            MediaResource(id: "motion", filename: "PAIR.MOV", byteCount: 40)
        ], kind: .livePhoto, createdAt: range.end.addingTimeInterval(-1))
        let assets = [live, asset("start", day), asset("tomorrow", range.end), asset("unknown", nil)]
        let projector = CatalogProjector()
        let result = try await projector.project(
            assets: assets, statuses: [:], backupDates: [:],
            query: CatalogQuery(filter: .photos, search: "pair", captureDateRange: range)
        )
        #expect(result.sections.flatMap(\.assets) == [live])
        #expect(result.visibleNewCount == 1 && result.visibleNewBytes == 100)
        #expect(result.counts[.all] == 4 && result.newCount == 4 && result.newBytes == 130)
        let backed = try await projector.project(
            assets: assets, statuses: ["live": .backedUp], backupDates: [:],
            query: CatalogQuery(filter: .notBackedUp, captureDateRange: range)
        )
        #expect(backed.orderedIDs == ["start"])
        let cleared = try await projector.project(assets: assets, statuses: [:], backupDates: [:], query: CatalogQuery())
        #expect(cleared.filteredCount == 4 && cleared.orderedIDs.last == "unknown")
    }

    private func calendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        return calendar
    }

    private func asset(_ id: String, _ date: Date?) -> MediaAsset {
        MediaAsset(id: id, deviceID: "phone", resources: [MediaResource(id: id, filename: "\(id).HEIC", byteCount: 10)],
                   kind: .photo, createdAt: date)
    }
}
