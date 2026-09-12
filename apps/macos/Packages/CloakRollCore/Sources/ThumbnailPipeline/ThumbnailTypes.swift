import Foundation

/// Requests are connection-scoped. Cross-connection preview reuse requires an explicit identity
/// supplied by a caller that has validated unique, complete metadata for the same persistent device.
public struct ThumbnailKey: Codable, Hashable, Sendable {
    public let sessionID: UUID
    public let resourceID: String
    public let version: String
    public let maximumPixelSize: Int
    /// Caller-proven preview identity only; never evidence for backup matching or verification.
    public let reusableIdentity: String?

    public init(
        sessionID: UUID, resourceID: String, version: String, maximumPixelSize: Int, reusableIdentity: String? = nil
    ) {
        self.sessionID = sessionID
        self.resourceID = resourceID
        self.version = version
        self.maximumPixelSize = maximumPixelSize
        self.reusableIdentity = reusableIdentity
    }

    var permitsReuse: Bool { reusableIdentity.map { !$0.isEmpty } == true }

    /// The request retains the real connection identity. Only storage uses this reserved namespace.
    var storageKey: ThumbnailKey {
        guard let reusableIdentity, !reusableIdentity.isEmpty else { return self }
        return ThumbnailKey(
            sessionID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
            resourceID: reusableIdentity, version: version, maximumPixelSize: maximumPixelSize,
            reusableIdentity: reusableIdentity
        )
    }
}

public enum ThumbnailPriority: Sendable {
    case visible
    case prefetch
}

public enum ThumbnailPipelineError: Error, Equatable, Sendable {
    case staleSession
    case queueFull
    case oversizedData
    case emptyData
}

public struct ThumbnailPipelineConfiguration: Sendable {
    public let memoryByteLimit: Int
    public let memoryItemLimit: Int
    public let diskByteLimit: Int
    public let diskItemLimit: Int
    public let maximumDataBytes: Int
    public let maximumActiveLoads: Int
    public let maximumQueuedRequests: Int

    public init(
        memoryByteLimit: Int = 32 * 1_024 * 1_024,
        memoryItemLimit: Int = 512,
        diskByteLimit: Int = 256 * 1_024 * 1_024,
        diskItemLimit: Int = 2_000,
        maximumDataBytes: Int = 16 * 1_024 * 1_024,
        maximumActiveLoads: Int = 2,
        maximumQueuedRequests: Int = 64
    ) {
        self.memoryByteLimit = max(0, memoryByteLimit)
        self.memoryItemLimit = max(0, memoryItemLimit)
        self.diskByteLimit = max(0, diskByteLimit)
        self.diskItemLimit = max(0, diskItemLimit)
        self.maximumDataBytes = min(16 * 1_024 * 1_024, max(1, maximumDataBytes))
        self.maximumActiveLoads = min(2, max(1, maximumActiveLoads))
        self.maximumQueuedRequests = min(64, max(0, maximumQueuedRequests))
    }
}

/// Lifetime counters and current costs. No resource names, paths, or device identifiers.
public struct ThumbnailPipelineMetrics: Equatable, Sendable {
    public let memoryHits: Int
    public let diskHits: Int
    public let sourceLoads: Int
    public let coalesced: Int
    public let failed: Int
    public let memoryBytes: Int
    public let memoryItems: Int
    public let diskBytes: Int
    public let diskItems: Int
    public let diskFailures: Int
    public let active: Int
    public let queued: Int
}
