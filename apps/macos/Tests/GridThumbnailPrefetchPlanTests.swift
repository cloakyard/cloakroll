import Foundation
import MediaModels
import Testing
@testable import CloakRoll

struct GridThumbnailPrefetchPlanTests {
    @Test func nextTwoRowsAreKnownWithoutInstantiatingTheirCells() throws {
        let plan = try GridThumbnailPrefetchPlan(sections: sections([10]), columns: 2)
        #expect(plan.candidates(visibleIDs: ["0", "1"]).map(\.id) == ["2", "3", "4", "5"])
        #expect(plan.candidates(visibleIDs: ["4", "5"]).map(\.id) == ["6", "7", "8", "9", "2", "3"])
        #expect(plan.candidates(visibleIDs: []).isEmpty)
        #expect(plan.candidates(visibleIDs: ["missing"]).isEmpty)
    }

    @Test func sectionBreaksAndPartialRowsDoNotCountAsFullFlattenedRows() throws {
        let plan = try GridThumbnailPrefetchPlan(sections: sections([3, 3]), columns: 2)
        #expect(plan.candidates(visibleIDs: ["0", "1"]).map(\.id) == ["2", "3", "4"])
        #expect(plan.candidates(visibleIDs: ["2"]).map(\.id) == ["3", "4", "5", "0", "1"])
        #expect(plan.candidates(visibleIDs: ["3", "4"]).map(\.id) == ["5", "2"])
    }

    @Test func aWideWindowStillBoundsTheSpeculativeWorkingSet() throws {
        let plan = try GridThumbnailPrefetchPlan(sections: sections([200]), columns: 40)
        let visible = Set((0..<40).map(String.init))
        #expect(plan.candidates(visibleIDs: visible).count == 32)
        #expect(plan.candidates(visibleIDs: visible).first?.id == "40")
        #expect(plan.candidates(visibleIDs: visible).last?.id == "71")
        #expect(plan.candidates(visibleIDs: visible, limit: 0).isEmpty)
    }

    @Test func changedColumnCountChangesTheActualUpcomingRows() throws {
        let source = sections([12])
        let narrow = try GridThumbnailPrefetchPlan(sections: source, columns: 2)
        let wide = try GridThumbnailPrefetchPlan(sections: source, columns: 4)
        #expect(narrow.candidates(visibleIDs: ["0", "1"]).map(\.id) == ["2", "3", "4", "5"])
        #expect(wide.candidates(visibleIDs: ["0", "1"]).map(\.id) == ["4", "5", "6", "7", "8", "9", "10", "11"])
    }

    private func sections(_ counts: [Int]) -> [MediaSection] {
        var next = 0
        return counts.enumerated().map { index, count in
            let assets = (next..<(next + count)).map { prefetchAsset(String($0)) }
            next += count
            return MediaSection(id: "section-\(index)", date: nil, assets: assets)
        }
    }
}

func prefetchAsset(_ id: String) -> MediaAsset {
    MediaAsset(id: id, deviceID: "device", resources: [
        MediaResource(id: id, filename: "\(id).HEIC", byteCount: 100)
    ], kind: .photo, createdAt: nil)
}
