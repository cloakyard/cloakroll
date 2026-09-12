import Foundation
import MediaCatalog
import MediaModels
import Testing

@Suite("Filtered backup aggregates")
struct CatalogBackupAggregateTests {
    @Test(arguments: [
        (LibraryFilter.all, 4, Int64(700)),
        (.photos, 3, 500), (.videos, 1, 200), (.livePhotos, 1, 100),
        (.raw, 1, 100), (.notBackedUp, 4, 700), (.backedUp, 0, 0), (.recentlyBackedUp, 0, 0)
    ])
    func filteredAndSearchedTotalsMatchEligibleVisibleAssets(
        filter: LibraryFilter, expectedCount: Int, expectedBytes: Int64
    ) async throws {
        let now = Date(timeIntervalSince1970: 1_789_214_400)
        let snapshot = try await CatalogProjector().project(
            assets: fixtures,
            statuses: ["raw": .uncertain, "video": .failed, "backed": .backedUp],
            backupDates: ["backed": now],
            query: CatalogQuery(filter: filter, search: "  KEEP  "),
            now: now
        )
        #expect(snapshot.visibleNewCount == expectedCount)
        #expect(snapshot.visibleNewBytes == expectedBytes)
        #expect(snapshot.newCount == 5)
        #expect(snapshot.newBytes == 1_200)
        #expect(snapshot.totalCount == 6)
        #expect(snapshot.totalBytes == 1_600)
        #expect(snapshot.counts[.raw] == 3)
    }

    @Test func noSearchMatchesLeaveNoBackupCandidates() async throws {
        let snapshot = try await CatalogProjector().project(
            assets: fixtures, statuses: [:], backupDates: [:],
            query: CatalogQuery(search: "missing")
        )
        #expect(snapshot.visibleNewCount == 0)
        #expect(snapshot.visibleNewBytes == 0)
        #expect(snapshot.newCount == 6)
        #expect(snapshot.newBytes == 1_600)
        #expect(snapshot.sections.isEmpty)
    }

    @Test func existingInitializersDefaultToFullCatalogTotalsButAcceptExplicitZero() {
        let full = CatalogSnapshot(
            sections: [], counts: [:], orderedIDs: [], totalCount: 3,
            newCount: 2, newBytes: 100, totalBytes: 200
        )
        let filtered = CatalogSnapshot(
            sections: [], counts: [:], orderedIDs: [], totalCount: 3,
            newCount: 2, newBytes: 100, totalBytes: 200, visibleNewCount: 0, visibleNewBytes: 0
        )
        #expect(full.visibleNewCount == 2)
        #expect(full.visibleNewBytes == 100)
        #expect(filtered.visibleNewCount == 0)
        #expect(filtered.visibleNewBytes == 0)
        #expect(full != filtered)
    }

    private var fixtures: [MediaAsset] {
        [
            asset("raw", name: "keep.DNG", kind: .raw, bytes: 100),
            asset("video", name: "keep.MOV", kind: .video, bytes: 200),
            asset("photo", name: "keep.HEIC", kind: .photo, bytes: 300),
            asset("backed", name: "keep-backed.DNG", kind: .raw, bytes: 400),
            asset("excluded", name: "outside.DNG", kind: .raw, bytes: 500),
            MediaAsset(
                id: "live", deviceID: "device",
                resources: [
                    MediaResource(id: "still", filename: "outside.HEIC", byteCount: 60),
                    MediaResource(id: "motion", filename: "keep-motion.MOV", byteCount: 40)
                ],
                kind: .livePhoto, createdAt: nil
            )
        ]
    }

    private func asset(_ id: String, name: String, kind: MediaKind, bytes: Int64) -> MediaAsset {
        MediaAsset(
            id: id, deviceID: "device",
            resources: [MediaResource(id: "\(id)-resource", filename: name, byteCount: bytes)],
            kind: kind, createdAt: nil
        )
    }
}
