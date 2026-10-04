import CoreGraphics
import Foundation
import Testing
import ThumbnailPipeline
@testable import CloakRoll

@MainActor
struct ThumbnailPresentationTests {
    @Test func aNearbyBitmapIsAlreadyInstalledWhenItsCellBecomesVisible() throws {
        let state = ThumbnailPresentation()
        let key = key()
        let bitmap = try bitmap()
        #expect(state.prepare(key: key, demand: .prefetch))
        state.accept(bitmap, for: key)
        #expect(state.image === bitmap)

        // The first visible presentation already has the identical bitmap, without another load.
        #expect(!state.prepare(key: key, demand: .visible))
        #expect(state.image === bitmap)
    }

    @Test func movingBackIntoTheNearbyBandRetainsTheDisplayedBitmap() throws {
        let state = ThumbnailPresentation()
        let key = key()
        let bitmap = try bitmap()
        #expect(state.prepare(key: key, demand: .visible))
        state.accept(bitmap, for: key)
        #expect(!state.prepare(key: key, demand: .prefetch))
        #expect(state.image === bitmap)
        #expect(!state.prepare(key: key, demand: .visible))
        #expect(state.image === bitmap)
    }

    @Test func leavingTheNearbyBandReleasesTheImageAndRejectsLateCompletion() throws {
        let state = ThumbnailPresentation()
        let key = key()
        let bitmap = try bitmap()
        _ = state.prepare(key: key, demand: .visible)
        state.accept(bitmap, for: key)
        #expect(!state.prepare(key: key, demand: .none))
        #expect(state.image == nil)
        state.accept(bitmap, for: key)
        #expect(state.image == nil)
        #expect(state.prepare(key: key, demand: .prefetch))
    }

    @Test(arguments: [true, false])
    func changedSessionOrMetadataClearsTheOldImageAndRejectsItsResult(changeSession: Bool) throws {
        let state = ThumbnailPresentation()
        let previous = key()
        let current = ThumbnailKey(
            sessionID: changeSession ? UUID() : previous.sessionID,
            resourceID: previous.resourceID, version: changeSession ? previous.version : "modified", maximumPixelSize: 512
        )
        let oldImage = try bitmap()
        let newImage = try bitmap()
        _ = state.prepare(key: previous, demand: .prefetch)
        state.accept(oldImage, for: previous)
        #expect(state.prepare(key: current, demand: .prefetch))
        #expect(state.image == nil)
        state.accept(oldImage, for: previous)
        #expect(state.image == nil)
        state.accept(newImage, for: current)
        #expect(state.image === newImage)
    }

    @Test func resetAndUnavailableKeyRejectLateImages() throws {
        let state = ThumbnailPresentation()
        let key = key()
        let bitmap = try bitmap()
        _ = state.prepare(key: key, demand: .prefetch)
        state.reset()
        state.accept(bitmap, for: key)
        #expect(state.image == nil)
        _ = state.prepare(key: key, demand: .visible)
        state.accept(bitmap, for: key)
        #expect(!state.prepare(key: nil, demand: .visible))
        #expect(state.image == nil)
        state.accept(bitmap, for: key)
        #expect(state.image == nil)
    }

    @Test func aMissingBitmapDoesNotPretendTheCellIsReady() {
        let state = ThumbnailPresentation()
        let key = key()
        _ = state.prepare(key: key, demand: .prefetch)
        state.accept(nil, for: key)
        #expect(state.image == nil)
        #expect(state.prepare(key: key, demand: .visible))
    }

    private func key() -> ThumbnailKey {
        ThumbnailKey(sessionID: UUID(), resourceID: "original", version: "1", maximumPixelSize: 512)
    }

    private func bitmap() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 16, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        return try #require(context.makeImage())
    }
}
