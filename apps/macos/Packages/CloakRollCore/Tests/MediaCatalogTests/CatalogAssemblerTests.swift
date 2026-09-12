import Foundation
import MediaCatalog
import MediaModels
import Testing

@Suite("Device catalog assembly")
struct CatalogAssemblerTests {
    @Test func emptyCatalogHasNoInventedAssets() {
        #expect(CatalogAssembler.assemble(records: []).isEmpty)
    }

    @Test(arguments: [
        ("photo.heic", "public.heic", false, MediaKind.photo),
        ("photo.jpeg", "public.jpeg", false, .photo),
        ("photo.png", "public.png", false, .photo),
        ("video.mov", "com.apple.quicktime-movie", false, .video),
        ("video.mp4", "public.mpeg-4", false, .video),
        ("photo.dng", "com.adobe.raw-image", false, .raw),
        ("unknown.bin", "public.data", true, .raw),
        ("notes.txt", "public.plain-text", false, .other)
    ])
    func classifiesDeclaredTypes(values: (String, String, Bool, MediaKind)) throws {
        let (filename, uti, isRaw, expected) = values
        let asset = try #require(CatalogAssembler.assemble(records: [
            record("source", filename: filename, uti: uti, isRaw: isRaw)
        ]).first)
        #expect(asset.kind == expected)
    }

    @Test func extensionFallbackIsLimitedToMissingOrGenericTypes() {
        let records = [
            record("a", filename: "image.HEIC"),
            record("b", filename: "clip.MOV", uti: "public.data"),
            record("c", filename: "image.DNG", uti: "public.image"),
            record("d", filename: "clip.MOV", uti: "public.jpeg"),
            record("e", filename: "image.HEIC", uti: "com.example.unknown-format"),
            record("f", filename: "clip.MOV", uti: "public.image"),
            record("g", filename: "image.HEIC", uti: "public.movie"),
            record("h", filename: "unknown.no-such-extension")
        ]
        let kinds = Dictionary(uniqueKeysWithValues: CatalogAssembler.assemble(records: records).map { ($0.primaryResourceID, $0.kind) })
        #expect(kinds == ["a": .photo, "b": .video, "c": .raw, "d": .photo,
                          "e": .other, "f": .photo, "g": .video, "h": .other])
    }

    @Test func matchingFilenamesAloneDoNotMakeLivePhotos() {
        let records = [record("still", filename: "IMG_0001.HEIC"), record("movie", filename: "IMG_0001.MOV")]
        let assets = CatalogAssembler.assemble(records: records)
        #expect(assets.count == 2)
        #expect(Set(assets.map(\.kind)) == [.photo, .video])
        assertEveryResourcePreserved(records, in: assets)
    }

    @Test func groupRelatedAndBurstUUIDsDoNotProvePairing() {
        let records = [
            record("still", filename: "IMG_0001.HEIC", group: "group", related: "related", burst: "burst"),
            record("movie", filename: "IMG_0001.MOV", group: "group", related: "related", burst: "burst"),
            record("burst-2", filename: "IMG_0002.HEIC", group: "group", related: "related", burst: "burst")
        ]
        let assets = CatalogAssembler.assemble(records: records)
        #expect(assets.count == 3)
        #expect(assets.allSatisfy { $0.resources.count == 1 })
    }

    @Test func explicitSidecarMakesLivePhotoWithStillPreviewAndMotionDuration() throws {
        let records = [
            record("z-still", filename: "IMG_0001.HEIC", sidecars: ["a-motion"]),
            record("a-motion", filename: "unrelated-name.MOV", duration: 3.25)
        ]
        let assets = CatalogAssembler.assemble(records: records)
        let asset = try #require(assets.first)
        #expect(assets.count == 1)
        #expect(asset.kind == .livePhoto)
        #expect(asset.primaryResourceID == "z-still")
        #expect(asset.filename == "IMG_0001.HEIC")
        #expect(asset.resources.map(\.id) == ["z-still", "a-motion"])
        #expect(asset.duration == 3.25)
        #expect(asset.byteCount == 200)
        assertEveryResourcePreserved(records, in: assets)
    }

    @Test func reverseSidecarAndMatchingOriginAlsoProveUnambiguousLivePairs() {
        let reverse = [record("still", filename: "still.heic"), record("movie", filename: "movie.mov", sidecars: ["still"])]
        let origin = [record("still", filename: "still.heic", origin: "original"),
                      record("movie", filename: "movie.mov", origin: "original")]
        #expect(CatalogAssembler.assemble(records: reverse).map(\.kind) == [.livePhoto])
        #expect(CatalogAssembler.assemble(records: origin).map(\.kind) == [.livePhoto])
    }

    @Test func blankOriginIsNotRelationshipEvidence() {
        let records = [record("still", filename: "still.heic", origin: " \n"),
                       record("movie", filename: "movie.mov", origin: " \n")]
        #expect(CatalogAssembler.assemble(records: records).count == 2)
    }

    @Test func mp4OrMisleadingMovieExtensionIsNotALivePhotoCompanion() {
        let mp4 = [record("still", filename: "still.heic", sidecars: ["movie"]),
                   record("movie", filename: "movie.mp4")]
        let misleading = [record("still", filename: "still.heic", sidecars: ["movie"]),
                          record("movie", filename: "movie.mov", uti: "public.mpeg-4")]
        #expect(CatalogAssembler.assemble(records: mp4).count == 2)
        #expect(CatalogAssembler.assemble(records: misleading).count == 2)
    }

    @Test func explicitRAWPairKeepsTheRenderedStillAsPrimary() throws {
        let records = [record("z-still", filename: "IMG.JPG", pairedRaw: "a-raw"),
                       record("a-raw", filename: "IMG.DNG")]
        let asset = try #require(CatalogAssembler.assemble(records: records).first)
        #expect(asset.kind == .raw)
        #expect(asset.primaryResourceID == "z-still")
        #expect(asset.filename == "IMG.JPG")
        #expect(asset.resources.map(\.id) == ["z-still", "a-raw"])
    }

    @Test func rawSidecarRelationshipPairsButRawOriginOrNameAloneDoesNot() {
        let sidecars = [record("still", filename: "IMG.JPG", sidecars: ["raw"]), record("raw", filename: "IMG.DNG")]
        let origin = [record("still", filename: "IMG.JPG", origin: "same"),
                      record("raw", filename: "IMG.DNG", origin: "same")]
        #expect(CatalogAssembler.assemble(records: sidecars).count == 1)
        #expect(CatalogAssembler.assemble(records: origin).count == 2)
    }

    @Test func missingOrMistypedRAWCompanionRemainsIndependent() {
        let records = [record("still", filename: "IMG.JPG", pairedRaw: "other"),
                       record("other", filename: "other.JPG"),
                       record("missing", filename: "missing.JPG", pairedRaw: "not-yet-here")]
        let assets = CatalogAssembler.assemble(records: records)
        #expect(assets.count == 3)
        assertEveryResourcePreserved(records, in: assets)
    }

    @Test func originWithTwoStillsOrTwoMoviesPreservesAllMembers() {
        let records = [record("still", filename: "a.heic", origin: "shared"),
                       record("still-2", filename: "b.heic", origin: "shared"),
                       record("movie", filename: "c.mov", origin: "shared")]
        let assets = CatalogAssembler.assemble(records: records)
        #expect(assets.count == 3)
        assertEveryResourcePreserved(records, in: assets)
    }

    @Test func overlappingPairEvidenceNeverChoosesAnArbitraryWinner() {
        let records = [record("still-1", filename: "a.heic", sidecars: ["movie"]),
                       record("still-2", filename: "b.heic", origin: "shared"),
                       record("movie", filename: "c.mov", origin: "shared")]
        let first = CatalogAssembler.assemble(records: records)
        #expect(first.count == 3)
        #expect(first == CatalogAssembler.assemble(records: records.reversed()))
        assertEveryResourcePreserved(records, in: first)
    }

    @Test func simultaneousRawAndMotionRelationshipsRemainAmbiguous() {
        let records = [record("still", filename: "a.heic", sidecars: ["movie"], pairedRaw: "raw"),
                       record("movie", filename: "b.mov"), record("raw", filename: "c.dng")]
        let assets = CatalogAssembler.assemble(records: records)
        #expect(assets.count == 3)
        assertEveryResourcePreserved(records, in: assets)
    }

    @Test func explicitSidecarChainAttachesToOneAsset() throws {
        let records = [record("still", filename: "a.heic", sidecars: ["adjustment"]),
                       record("adjustment", filename: "a.aae", sidecars: ["metadata"]),
                       record("metadata", filename: "a.xmp")]
        let assets = CatalogAssembler.assemble(records: records)
        let asset = try #require(assets.first)
        #expect(assets.count == 1)
        #expect(asset.kind == .photo)
        #expect(asset.resources.count == 3)
        assertEveryResourcePreserved(records, in: assets)
    }

    @Test func sidecarSharedByTheTwoMembersOfOnePairIsCountedOnce() throws {
        let records = [record("still", filename: "a.heic", sidecars: ["movie", "adjustment", "adjustment"]),
                       record("movie", filename: "a.mov", sidecars: ["adjustment"]),
                       record("adjustment", filename: "a.aae")]
        let assets = CatalogAssembler.assemble(records: records)
        #expect(assets.count == 1)
        #expect(try #require(assets.first).resources.count == 3)
        assertEveryResourcePreserved(records, in: assets)
    }

    @Test func sharedSidecarBetweenSeparateAssetsStaysSeparate() {
        let records = [record("a", filename: "a.heic", sidecars: ["adjustment"]),
                       record("b", filename: "b.heic", sidecars: ["adjustment"]),
                       record("adjustment", filename: "edit.aae")]
        let assets = CatalogAssembler.assemble(records: records)
        #expect(assets.count == 3)
        #expect(assets.allSatisfy { $0.resources.count == 1 })
        assertEveryResourcePreserved(records, in: assets)
    }

    @Test func unknownMediaIsPreservedAndOriginSidecarsAttachOnlyToUniqueOwners() {
        let records = [record("a", filename: "a.heic", origin: "a"),
                       record("adjustment", filename: "a.aae", origin: "a"),
                       record("unknown", filename: "original.unknown-format")]
        let assets = CatalogAssembler.assemble(records: records)
        #expect(assets.count == 2)
        #expect(Set(assets.map(\.kind)) == [.photo, .other])
        assertEveryResourcePreserved(records, in: assets)
    }

    @Test func sameFilenamesAndRelationshipIDsCannotCrossDevicesOrSourcePaths() {
        let records = [record("still", device: "one", filename: "IMG.heic", path: ["DCIM", "100"], sidecars: ["movie"]),
                       record("movie", device: "two", filename: "IMG.mov"),
                       record("still", device: "two", filename: "IMG.heic", path: ["DCIM", "100"]),
                       record("other-path", device: "one", filename: "IMG.heic", path: ["DCIM", "101"])]
        let assets = CatalogAssembler.assemble(records: records)
        #expect(assets.count == 4)
        #expect(Set(assets.map(\.id)).count == 4)
        #expect(assets.allSatisfy { $0.resources.count == 1 })
        assertEveryResourcePreserved(records, in: assets)
    }

    @Test func lateCompanionsDoNotChangeTheStillIdentity() throws {
        let still = record("still", filename: "a.heic", sidecars: ["movie", "adjustment"])
        let initial = try #require(CatalogAssembler.assemble(records: [still]).first)
        let records = [record("movie", filename: "a.mov"), still, record("adjustment", filename: "a.aae")]
        let complete = try #require(CatalogAssembler.assemble(records: records).first)
        #expect(initial.id == complete.id)
        #expect(initial.primaryResourceID == complete.primaryResourceID)
        #expect(initial.kind == .photo)
        #expect(complete.kind == .livePhoto)
        #expect(complete.resources.count == 3)
    }

    @Test func rebuildReflectsRemovalAndRenameWithoutRetainingOldRows() throws {
        let still = record("still", filename: "a.heic", sidecars: ["movie"])
        let paired = try #require(CatalogAssembler.assemble(records: [still, record("movie", filename: "a.mov")]).first)
        let renamed = try #require(CatalogAssembler.assemble(records: [record("still", filename: "renamed.heic")]).first)
        #expect(renamed.id == paired.id)
        #expect(renamed.kind == .photo)
        #expect(renamed.filename == "renamed.heic")
        #expect(renamed.resources.count == 1)
        #expect(CatalogAssembler.assemble(records: []).isEmpty)
    }

    @Test func outputOrderIsStableAcrossBatchOrderAndUnrelatedAdditions() {
        let records = [record("z", filename: "z.heic"), record("a", filename: "a.mov"),
                       record("m", device: "other", filename: "m.dng")]
        let assets = CatalogAssembler.assemble(records: records)
        #expect(assets == CatalogAssembler.assemble(records: records.reversed()))
        let expanded = CatalogAssembler.assemble(records: records + [record("new", filename: "new.heic")])
        #expect(Set(assets.map(\.id)).isSubset(of: Set(expanded.map(\.id))))
        #expect(assets.map(\.id) == assets.map(\.id).sorted())
    }

    @Test func conflictingDuplicateIDsStayIndependentAndCannotResolvePairing() {
        let records = [record("still", filename: "a.heic", sidecars: ["movie"]),
                       record("movie", filename: "a.mov"), record("movie", filename: "b.mov")]
        let assets = CatalogAssembler.assemble(records: records)
        #expect(assets.count == 3)
        #expect(Set(assets.map(\.id)).count == 3)
        #expect(assets == CatalogAssembler.assemble(records: records.reversed()))
        assertEveryResourcePreserved(records, in: assets)
    }

    @Test func exactDuplicateAndRepeatedRelationshipReferencesAreCountedOnce() {
        let still = record("still", filename: "a.heic", sidecars: ["movie", "movie", "still", "missing"])
        let movie = record("movie", filename: "a.mov")
        let assets = CatalogAssembler.assemble(records: [still, movie, still, movie])
        #expect(assets.count == 1)
        #expect(assets.first?.resources.count == 2)
    }

    @Test func invalidDatesRemainUnknownAndNoModificationDateIsInventedAsCreation() throws {
        let invalid = SourceMediaRecord(id: "invalid", deviceID: "phone", filename: "a.mov", byteCount: -9,
                                        createdAt: Date(timeIntervalSince1970: .infinity), pixelWidth: -1,
                                        pixelHeight: 0, duration: .infinity)
        let unknown = SourceMediaRecord(id: "unknown", deviceID: "phone", filename: "b.heic", byteCount: 4,
                                        modifiedAt: Date(timeIntervalSince1970: 123))
        let assets = CatalogAssembler.assemble(records: [invalid, unknown])
        #expect(assets.allSatisfy { $0.createdAt == nil && $0.duration == nil })
        let video = try #require(assets.first { $0.kind == .video })
        #expect(video.byteCount == 0)
        #expect(video.pixelWidth == nil)
        #expect(video.pixelHeight == nil)
    }

    private func record(
        _ id: String, device: String = "phone", filename: String, path: [String] = [], uti: String? = nil,
        isRaw: Bool = false, origin: String? = nil, group: String? = nil, related: String? = nil,
        burst: String? = nil, sidecars: [String] = [], pairedRaw: String? = nil, duration: Double? = nil
    ) -> SourceMediaRecord {
        SourceMediaRecord(id: id, deviceID: device, filename: filename, contextPath: path, uti: uti,
                          isRaw: isRaw, byteCount: 100, duration: duration, originatingAssetID: origin,
                          groupUUID: group, relatedUUID: related, burstUUID: burst,
                          sidecarIDs: sidecars, pairedRawID: pairedRaw)
    }

    private func assertEveryResourcePreserved(_ records: [SourceMediaRecord], in assets: [MediaAsset]) {
        let expected = records.map { "\($0.deviceID):\($0.id):\($0.filename)" }.sorted()
        let actual = assets.flatMap { asset in asset.resources.map { "\(asset.deviceID):\($0.id):\($0.filename)" } }.sorted()
        #expect(actual == expected)
    }
}
