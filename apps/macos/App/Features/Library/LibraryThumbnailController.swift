import CoreGraphics
import CryptoKit
import Foundation
import MediaModels
import OSLog
import ThumbnailPipeline

/// One controller serves the grid and Info. Session transitions are serialized before new work.
@MainActor
final class LibraryThumbnailController {
    private let encoded: ThumbnailPipeline
    private let decoded: DecodedThumbnailCache
    private var sessionID: UUID?
    private var generation = UUID()
    private var transition: Task<Void, Never>?

    private static var defaultCacheDirectory: URL? {
        guard ProcessInfo.processInfo.environment["CLOAKROLL_TESTING"] != "1" else { return nil }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appending(path: "CloakRoll/Thumbnails", directoryHint: .isDirectory)
    }

    init(cacheDirectory: URL? = LibraryThumbnailController.defaultCacheDirectory) {
        encoded = ThumbnailPipeline(cacheDirectory: cacheDirectory)
        decoded = DecodedThumbnailCache()
        transition = Task { [encoded, decoded] in
            await encoded.setSession(nil)
            await decoded.setSession(nil)
        }
    }

    func setSession(_ sessionID: UUID?) {
        guard self.sessionID != sessionID else { return }
        self.sessionID = sessionID
        generation = UUID()
        let previous = transition
        transition = Task { [encoded, decoded] in
            await previous?.value
            await encoded.setSession(sessionID)
            await decoded.setSession(sessionID)
        }
    }

    func image(
        for key: ThumbnailKey, priority: ThumbnailPriority = .visible,
        load: @escaping @Sendable () async throws -> Data
    ) async throws -> CGImage? {
        let generation = try await prepare(key)
        if let image = await decoded.cachedImage(for: key) {
            try validate(key, generation: generation)
            return image
        }
        let data = try await encoded.data(for: key, priority: priority, load: load)
        try validate(key, generation: generation)
        let image = try await decoded.image(for: key, data: data)
        try validate(key, generation: generation)
        return image
    }

    func prefetch(for key: ThumbnailKey, load: @escaping @Sendable () async throws -> Data) async throws {
        _ = try await image(for: key, priority: .prefetch, load: load)
    }

    private func prepare(_ key: ThumbnailKey) async throws -> UUID {
        let generation = generation
        try validate(key, generation: generation)
        await transition?.value
        try validate(key, generation: generation)
        return generation
    }

    private func validate(_ key: ThumbnailKey, generation: UUID) throws {
        try Task.checkCancellation()
        guard sessionID == key.sessionID, self.generation == generation else { throw ThumbnailPipelineError.staleSession }
    }

    #if DEBUG
    func metrics() async -> (source: ThumbnailPipelineMetrics, images: DecodedThumbnailCache.Metrics) {
        (await encoded.metrics(), await decoded.metrics())
    }

    func logMetrics() async {
        let source = await encoded.metrics()
        let images = await decoded.metrics()
        let logger = Logger(subsystem: "com.cloakyard.cloakroll", category: "Thumbnails")
        logger.notice("Thumbnail loads=\(source.sourceLoads) active=\(source.active) queued=\(source.queued)")
        logger.notice("Thumbnail coalesced=\(source.coalesced) failed=\(source.failed) diskFailures=\(source.diskFailures)")
        logger.notice("Thumbnail encoded hits=\(source.memoryHits) bytes=\(source.memoryBytes) items=\(source.memoryItems)")
        logger.notice("Thumbnail disk hits=\(source.diskHits) bytes=\(source.diskBytes) items=\(source.diskItems)")
        logger.notice("Thumbnail decoded hits=\(images.hits) decodes=\(images.decodes) failed=\(images.failures)")
        logger.notice("Thumbnail decoded bytes=\(images.bytes) items=\(images.items)")
    }
    #endif
}

extension ThumbnailKey {
    init?(asset: MediaAsset, sessionID: UUID?, maximumPixelSize: Int = 512, reusableIdentity: String? = nil) {
        guard let sessionID, let resourceID = asset.primaryResourceID else { return nil }
        if let reusableIdentity {
            self.init(
                sessionID: sessionID, resourceID: resourceID, version: reusableIdentity,
                maximumPixelSize: maximumPixelSize, reusableIdentity: reusableIdentity
            )
            return
        }
        // Structured, sorted encoding avoids delimiter collisions and includes all available
        // source metadata. Catalog revision is deliberately excluded: unrelated additions do not
        // invalidate unchanged images. Session scoping prevents unsupported persistent-ID reuse.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(asset) else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        self.init(sessionID: sessionID, resourceID: resourceID, version: digest, maximumPixelSize: maximumPixelSize)
    }
}
