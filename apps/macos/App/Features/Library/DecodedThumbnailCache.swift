import CoreGraphics
import Foundation
import ImageIO
import ThumbnailPipeline

/// Serial decoding keeps bursts of encoded cache hits from spawning unbounded image work.
/// Cost is the actual decoded bitmap allocation, separate from encoded and on-screen images.
actor DecodedThumbnailCache {
    struct Metrics: Sendable {
        let hits: Int
        let decodes: Int
        let failures: Int
        let bytes: Int
        let items: Int
    }

    private struct Entry {
        let image: CGImage
        let cost: Int
        var access: UInt64
    }

    private let byteLimit: Int
    private let itemLimit: Int
    private var sessionID: UUID?
    private var entries: [ThumbnailKey: Entry] = [:]
    private var bytes = 0
    private var access: UInt64 = 0
    private var hits = 0
    private var decodes = 0
    private var failures = 0

    init(byteLimit: Int = 64 * 1_024 * 1_024, itemLimit: Int = 256) {
        self.byteLimit = max(0, byteLimit)
        self.itemLimit = max(0, itemLimit)
    }

    func setSession(_ sessionID: UUID?) {
        guard self.sessionID != sessionID else { return }
        self.sessionID = sessionID
        entries.removeAll()
        bytes = 0
    }

    func cachedImage(for key: ThumbnailKey) -> CGImage? {
        guard key.sessionID == sessionID, var entry = entries[key] else { return nil }
        access &+= 1
        entry.access = access
        entries[key] = entry
        hits += 1
        return entry.image
    }

    func image(for key: ThumbnailKey, data: Data) throws -> CGImage? {
        try Task.checkCancellation()
        guard key.sessionID == sessionID else { throw ThumbnailPipelineError.staleSession }
        if let cached = cachedImage(for: key) { return cached }
        decodes += 1
        guard let image = ThumbnailDecoder.decode(data, maximumPixelSize: key.maximumPixelSize) else {
            failures += 1
            return nil
        }
        try Task.checkCancellation()
        let allocation = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !allocation.overflow, allocation.partialValue <= byteLimit, itemLimit > 0 else { return image }
        let cost = allocation.partialValue
        while bytes > byteLimit - cost || entries.count >= itemLimit {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access }) else { break }
            bytes -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
        access &+= 1
        entries[key] = Entry(image: image, cost: cost, access: access)
        bytes += cost
        return image
    }

    func metrics() -> Metrics {
        Metrics(hits: hits, decodes: decodes, failures: failures, bytes: bytes, items: entries.count)
    }
}

enum ThumbnailDecoder {
    static func decode(_ data: Data, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(512, max(64, maximumPixelSize)),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}
