import Foundation
import MediaModels
import Testing

@Suite("Media asset metadata")
struct MediaAssetTests {
    @Test("A Live Photo counts both original resources")
    func companionResourcesContributeToByteCount() {
        let asset = MediaAsset(
            id: "phone:live-photo",
            deviceID: "phone",
            resources: [
                MediaResource(id: "still", filename: "IMG_0001.HEIC", byteCount: 4_000),
                MediaResource(id: "motion", filename: "IMG_0001.MOV", byteCount: 9_000)
            ],
            kind: .livePhoto,
            createdAt: nil
        )

        #expect(asset.byteCount == 13_000)
        #expect(asset.filename == "IMG_0001.HEIC")
        #expect(asset.resources.count == 2)
    }

    @Test("An asset without resources remains usable")
    func emptyResourcesHaveSafeDisplayValues() {
        let asset = makeAsset(resources: [])

        #expect(asset.byteCount == 0)
        #expect(asset.filename == "Untitled")
    }

    @Test("Malformed resource sizes do not create a negative total")
    func negativeResourceSizeIsClamped() {
        let resource = MediaResource(id: "original", filename: "IMG_0001.HEIC", byteCount: -1)

        #expect(resource.byteCount == 0)
        #expect(makeAsset(resources: [resource]).byteCount == 0)
    }

    @Test("An overflowing total saturates instead of wrapping")
    func largeResourceTotalDoesNotOverflow() {
        let asset = makeAsset(resources: [
            MediaResource(id: "original", filename: "IMG_0001.DNG", byteCount: Int64.max),
            MediaResource(id: "companion", filename: "IMG_0001.JPG", byteCount: 1)
        ])

        #expect(asset.byteCount == Int64.max)
    }

    @Test("Unknown dates survive a metadata round trip")
    func unknownDateRoundTrip() throws {
        let asset = makeAsset(resources: [
            MediaResource(id: "original", filename: "IMG_0001.HEIC", byteCount: 1_234)
        ])

        let data = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(MediaAsset.self, from: data)

        #expect(decoded == asset)
        #expect(decoded.createdAt == nil)
        #expect(decoded.duration == nil)
        #expect(decoded.pixelWidth == nil)
        #expect(decoded.pixelHeight == nil)
    }

    @Test("Video metadata survives a value round trip")
    func videoMetadataRoundTrip() throws {
        let asset = MediaAsset(
            id: "phone:video",
            deviceID: "phone",
            resources: [MediaResource(id: "original", filename: "IMG_0002.MOV", byteCount: 12_345)],
            kind: .video,
            createdAt: Date(timeIntervalSince1970: 1_725_000_000),
            duration: 12.5,
            pixelWidth: 3_840,
            pixelHeight: 2_160
        )

        let decoded = try JSONDecoder().decode(MediaAsset.self, from: JSONEncoder().encode(asset))

        #expect(decoded == asset)
        #expect(Set([asset, decoded]).count == 1)
    }

    @Test("Companion resource changes are part of asset value equality")
    func equalityIncludesAllOriginalResources() {
        let still = MediaResource(id: "still", filename: "IMG_0001.HEIC", byteCount: 4_000)
        let stillOnly = makeAsset(resources: [still])
        let withCompanion = makeAsset(resources: [
            still,
            MediaResource(id: "motion", filename: "IMG_0001.MOV", byteCount: 9_000)
        ])

        #expect(stillOnly != withCompanion)
        #expect(Set([stillOnly, withCompanion]).count == 2)
    }

    private func makeAsset(resources: [MediaResource]) -> MediaAsset {
        MediaAsset(
            id: "phone:asset",
            deviceID: "phone",
            resources: resources,
            kind: .photo,
            createdAt: nil
        )
    }
}
