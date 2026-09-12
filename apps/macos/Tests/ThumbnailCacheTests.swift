import CoreGraphics
import Foundation
import ImageIO
import MediaModels
import Testing
import ThumbnailPipeline
import UniformTypeIdentifiers
@testable import CloakRoll

struct ThumbnailCacheTests {
    @Test func sharedDecodeReusesBitmapAndTracksActualAllocation() async throws {
        let cache = DecodedThumbnailCache()
        let session = UUID()
        await cache.setSession(session)
        let key = key(session)
        let data = try fixture()
        async let first = cache.image(for: key, data: data)
        async let second = cache.image(for: key, data: data)
        let images = try await (first, second)
        let image = try #require(images.0)
        #expect(image === images.1)
        let metrics = await cache.metrics()
        #expect(metrics.decodes == 1)
        #expect(metrics.hits == 1)
        #expect(metrics.bytes == image.bytesPerRow * image.height)
        #expect(metrics.items == 1)
    }

    @Test func leastRecentlyUsedBitmapIsEvictedAtItemLimit() async throws {
        let cache = DecodedThumbnailCache(itemLimit: 2)
        let session = UUID()
        await cache.setSession(session)
        let data = try fixture()
        _ = try await cache.image(for: key(session, resource: "one"), data: data)
        _ = try await cache.image(for: key(session, resource: "two"), data: data)
        _ = await cache.cachedImage(for: key(session, resource: "one"))
        _ = try await cache.image(for: key(session, resource: "three"), data: data)
        #expect(await cache.cachedImage(for: key(session, resource: "two")) == nil)
        #expect(await cache.cachedImage(for: key(session, resource: "one")) != nil)
        #expect(await cache.metrics().items == 2)
    }

    @Test func oversizedBitmapIsReturnedWithoutExceedingCacheBudget() async throws {
        let cache = DecodedThumbnailCache(byteLimit: 16)
        let session = UUID()
        await cache.setSession(session)
        #expect(try await cache.image(for: key(session), data: fixture()) != nil)
        #expect(await cache.metrics().bytes == 0)
        #expect(await cache.metrics().items == 0)
    }

    @Test func retiredSessionCannotDecodeOrRetrieveOldBitmap() async throws {
        let cache = DecodedThumbnailCache()
        let old = UUID()
        await cache.setSession(old)
        _ = try await cache.image(for: key(old), data: fixture())
        await cache.setSession(UUID())
        #expect(await cache.cachedImage(for: key(old)) == nil)
        await #expect(throws: ThumbnailPipelineError.staleSession) {
            _ = try await cache.image(for: key(old), data: fixture())
        }
        #expect(await cache.metrics().bytes == 0)
    }

    @Test func metadataAndSessionChangesProduceDistinctKeys() throws {
        let session = UUID()
        let original = asset(bytes: 123, date: Date(timeIntervalSince1970: 1))
        let first = try #require(ThumbnailKey(asset: original, sessionID: session))
        #expect(first == ThumbnailKey(asset: original, sessionID: session))
        #expect(first != ThumbnailKey(asset: original, sessionID: UUID()))
        #expect(first != ThumbnailKey(asset: asset(bytes: 124, date: original.createdAt), sessionID: session))
        #expect(first != ThumbnailKey(asset: asset(bytes: 123, date: nil), sessionID: session))
        #expect(first != ThumbnailKey(
            asset: asset(bytes: 123, date: original.createdAt, modifiedAt: Date(timeIntervalSince1970: 2)), sessionID: session
        ))
        #expect(first != ThumbnailKey(asset: original, sessionID: session, maximumPixelSize: 256))
        #expect(ThumbnailKey(asset: original, sessionID: nil) == nil)
    }

    @Test func viewportRequestsVisibleAndNearbyRowsOnly() {
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)
        func band(_ y: CGFloat) -> ThumbnailDemand {
            ThumbnailDemand.classify(frame: CGRect(x: 0, y: y, width: 150, height: 150), viewport: viewport)
        }
        #expect(band(0) == .visible)
        #expect(band(599) == .visible)
        #expect(band(601) == .prefetch)
        #expect(band(899) == .prefetch)
        #expect(band(901) == .none)
        #expect(band(-151) == .prefetch)
        #expect(band(-301) == .none)
    }

    private func key(_ session: UUID, resource: String = "one") -> ThumbnailKey {
        ThumbnailKey(sessionID: session, resourceID: resource, version: "1", maximumPixelSize: 128)
    }

    private func asset(bytes: Int64, date: Date?, modifiedAt: Date? = nil) -> MediaAsset {
        MediaAsset(id: "asset", deviceID: "device", resources: [
            MediaResource(id: "resource", filename: "same.HEIC", byteCount: bytes, modifiedAt: modifiedAt)
        ], kind: .photo, createdAt: date)
    }

    private func fixture() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 256, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
