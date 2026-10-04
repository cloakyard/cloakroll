import CoreGraphics
import Foundation
import ImageIO
import Testing
import ThumbnailPipeline
import UniformTypeIdentifiers
@testable import CloakRoll

@MainActor
struct LibraryThumbnailControllerTests {
    @Test func nearbyCellReceivesThePreparedBitmapBeforePromotion() async throws {
        let controller = LibraryThumbnailController(cacheDirectory: nil)
        let session = UUID()
        controller.setSession(session)
        let key = key(session)
        let data = try fixture(width: 48, height: 24)
        let presentation = ThumbnailPresentation()
        #expect(presentation.prepare(key: key, demand: .prefetch))
        let image = try #require(try await controller.image(for: key, priority: .prefetch) { data })
        presentation.accept(image, for: key)
        #expect(presentation.image === image)
        #expect(!presentation.prepare(key: key, demand: .visible))
        #expect(presentation.image === image)
        let metrics = await controller.metrics()
        #expect(metrics.source.sourceLoads == 1)
        #expect(metrics.images.decodes == 1)
    }

    @Test func prefetchPreparesTheBitmapBeforeAVisibleRequest() async throws {
        let controller = LibraryThumbnailController(cacheDirectory: nil)
        let session = UUID()
        controller.setSession(session)
        let key = key(session)
        let data = try fixture(width: 48, height: 24)
        try await controller.prefetch(for: key) { data }
        let before = await controller.metrics()
        #expect(before.source.sourceLoads == 1)
        #expect(before.images.decodes == 1)
        #expect(before.images.items == 1)
        let image = try #require(try await controller.image(for: key) {
            Issue.record("A prefetched bitmap requested its source again")
            return data
        })
        #expect(image.width == 48)
        let after = await controller.metrics()
        #expect(after.source.sourceLoads == 1)
        #expect(after.images.decodes == 1)
        #expect(after.images.hits == before.images.hits + 1)
    }

    @Test func cancellingPrefetchKeepsTheVisibleConsumerAndSharedSourceAlive() async throws {
        let controller = LibraryThumbnailController(cacheDirectory: nil)
        let session = UUID()
        controller.setSession(session)
        let key = key(session)
        let source = ControlledThumbnailSource()
        let prefetch = Task { try await controller.prefetch(for: key) { try await source.load("shared") } }
        await source.waitForStart("shared")
        let visible = Task { try await controller.image(for: key) { try await source.load("shared") } }
        prefetch.cancel()
        await #expect(throws: CancellationError.self) { try await prefetch.value }
        await source.finish("shared", data: try fixture(width: 48, height: 24))
        #expect(try await visible.value?.width == 48)
        #expect(await source.callCount("shared") == 1)
        #expect(await controller.metrics().images.decodes == 1)
    }

    @Test func aRetiredPrefetchCannotWarmTheReplacementSessionsBitmapCache() async throws {
        let controller = LibraryThumbnailController(cacheDirectory: nil)
        let oldSession = UUID()
        let currentSession = UUID()
        controller.setSession(oldSession)
        let oldKey = key(oldSession)
        let source = ControlledThumbnailSource()
        let old = Task { try await controller.prefetch(for: oldKey) { try await source.load("old") } }
        await source.waitForStart("old")
        controller.setSession(currentSession)
        await #expect(throws: ThumbnailPipelineError.staleSession) { try await old.value }
        await source.finish("old", data: try fixture(width: 48, height: 24))
        let currentKey = key(currentSession)
        let data = try fixture(width: 64, height: 32)
        try await controller.prefetch(for: currentKey) { data }
        let metrics = await controller.metrics()
        #expect(metrics.images.decodes == 1)
        #expect(metrics.images.items == 1)
        #expect(try await controller.image(for: currentKey) { data }?.width == 64)
    }

    @Test func gridAndInfoShareSourceAndDecodedImage() async throws {
        let controller = LibraryThumbnailController(cacheDirectory: nil)
        let session = UUID()
        controller.setSession(session)
        let key = key(session)
        let source = ControlledThumbnailSource()
        let grid = Task { try await controller.image(for: key) { try await source.load("shared") } }
        await source.waitForStart("shared")
        let info = Task { try await controller.image(for: key) { try await source.load("shared") } }

        await source.finish("shared", data: try fixture(width: 48, height: 24))
        let gridImage = try #require(try await grid.value)
        let infoImage = try #require(try await info.value)
        #expect(gridImage === infoImage)
        #expect(await source.callCount("shared") == 1)

        let revisited = try await controller.image(for: key) { try await source.load("shared") }
        #expect(revisited === gridImage)
        #expect(await source.callCount("shared") == 1)
    }

    @Test func cancellingGridConsumerPreservesInfoRequest() async throws {
        let controller = LibraryThumbnailController(cacheDirectory: nil)
        let session = UUID()
        controller.setSession(session)
        let key = key(session)
        let source = ControlledThumbnailSource(honorsCancellation: true)
        let grid = Task { try await controller.image(for: key) { try await source.load("shared") } }
        await source.waitForStart("shared")
        let info = Task { try await controller.image(for: key) { try await source.load("shared") } }

        grid.cancel()
        await #expect(throws: CancellationError.self) { _ = try await grid.value }
        await source.finish("shared", data: try fixture(width: 48, height: 24))
        let image = try #require(try await info.value)
        #expect(image.width == 48)
        #expect(image.height == 24)
        #expect(await source.callCount("shared") == 1)
    }

    @Test func retiredSessionRejectsLateSourceResult() async throws {
        let controller = LibraryThumbnailController(cacheDirectory: nil)
        let oldSession = UUID()
        let newSession = UUID()
        controller.setSession(oldSession)
        let source = ControlledThumbnailSource()
        let oldKey = key(oldSession)
        let old = Task { try await controller.image(for: oldKey) { try await source.load("old") } }
        await source.waitForStart("old")

        controller.setSession(newSession)
        let newKey = key(newSession)
        let current = Task { try await controller.image(for: newKey) { try await source.load("current") } }
        await source.waitForStart("current")
        await #expect(throws: ThumbnailPipelineError.staleSession) { _ = try await old.value }

        // This source deliberately ignores cancellation and returns after its session retires.
        await source.finish("old", data: try fixture(width: 32, height: 16))
        await source.finish("current", data: try fixture(width: 64, height: 32))
        let image = try #require(try await current.value)
        #expect(image.width == 64)
        #expect(image.height == 32)
        let revisited = try await controller.image(for: newKey) { try await source.load("current") }
        #expect(revisited === image)
        #expect(await source.callCount("current") == 1)
    }

    @Test func retiringAndRestoringSameUUIDDoesNotReviveOldCaller() async throws {
        let controller = LibraryThumbnailController(cacheDirectory: nil)
        let session = UUID()
        controller.setSession(session)
        let key = key(session)
        let source = ControlledThumbnailSource()
        let old = Task { try await controller.image(for: key) { try await source.load("old") } }
        await source.waitForStart("old")

        // There is intentionally no suspension between the two presentation transitions.
        controller.setSession(nil)
        controller.setSession(session)
        let current = Task { try await controller.image(for: key) { try await source.load("current") } }
        await source.waitForStart("current")
        await #expect(throws: ThumbnailPipelineError.staleSession) { _ = try await old.value }

        await source.finish("old", data: try fixture(width: 32, height: 16))
        await source.finish("current", data: try fixture(width: 64, height: 32))
        let image = try #require(try await current.value)
        #expect(image.width == 64)
        #expect(image.height == 32)
        #expect(await source.callCount("current") == 1)
        let revisited = try await controller.image(for: key) { try await source.load("current") }
        #expect(revisited === image)
        #expect(await source.callCount("current") == 1)
    }

    private func key(_ session: UUID) -> ThumbnailKey {
        ThumbnailKey(sessionID: session, resourceID: "resource", version: "1", maximumPixelSize: 128)
    }

    private func fixture(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

/// Explicit source gates avoid timer-based assumptions. Completed values also serve unexpected
/// duplicate calls, allowing a count assertion to fail instead of stranding a continuation.
private actor ControlledThumbnailSource {
    private let honorsCancellation: Bool
    private var calls: [String: Int] = [:]
    private var starts: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var pending: [String: [CheckedContinuation<Data, Never>]] = [:]
    private var completed: [String: Data] = [:]

    init(honorsCancellation: Bool = false) { self.honorsCancellation = honorsCancellation }

    func load(_ identifier: String) async throws -> Data {
        calls[identifier, default: 0] += 1
        starts.removeValue(forKey: identifier)?.forEach { $0.resume() }
        let data: Data
        if let result = completed[identifier] {
            data = result
        } else {
            data = await withCheckedContinuation { pending[identifier, default: []].append($0) }
        }
        if honorsCancellation { try Task.checkCancellation() }
        return data
    }

    func waitForStart(_ identifier: String) async {
        guard calls[identifier, default: 0] == 0 else { return }
        await withCheckedContinuation { starts[identifier, default: []].append($0) }
    }

    func finish(_ identifier: String, data: Data) {
        completed[identifier] = data
        pending.removeValue(forKey: identifier)?.forEach { $0.resume(returning: data) }
    }

    func callCount(_ identifier: String) -> Int { calls[identifier, default: 0] }
}
