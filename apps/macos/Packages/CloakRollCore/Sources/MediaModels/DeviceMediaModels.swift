import Foundation

/// Immutable facts supplied by the camera catalog. The ID addresses a resource only within this
/// connection; metadata and optional identifiers are evidence for later conservative matching.
public struct SourceMediaRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let deviceID: String
    public let filename: String
    public let originalFilename: String?
    public let contextPath: [String]
    public let uti: String?
    public let isRaw: Bool
    public let byteCount: Int64
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let duration: Double?
    public let originatingAssetID: String?
    public let groupUUID: String?
    public let relatedUUID: String?
    public let burstUUID: String?
    public let sidecarIDs: [String]
    public let pairedRawID: String?

    public init(
        id: String, deviceID: String, filename: String, originalFilename: String? = nil,
        contextPath: [String] = [], uti: String? = nil, isRaw: Bool = false, byteCount: Int64,
        createdAt: Date? = nil, modifiedAt: Date? = nil, pixelWidth: Int? = nil, pixelHeight: Int? = nil,
        duration: Double? = nil, originatingAssetID: String? = nil, groupUUID: String? = nil,
        relatedUUID: String? = nil, burstUUID: String? = nil, sidecarIDs: [String] = [], pairedRawID: String? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.filename = filename
        self.originalFilename = originalFilename
        self.contextPath = contextPath
        self.uti = uti
        self.isRaw = isRaw
        self.byteCount = max(0, byteCount)
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.pixelWidth = pixelWidth.flatMap { $0 > 0 ? $0 : nil }
        self.pixelHeight = pixelHeight.flatMap { $0 > 0 ? $0 : nil }
        self.duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.originatingAssetID = originatingAssetID
        self.groupUUID = groupUUID
        self.relatedUUID = relatedUUID
        self.burstUUID = burstUUID
        self.sidecarIDs = sidecarIDs
        self.pairedRawID = pairedRawID
    }
}

public enum MediaScanState: String, Codable, Sendable {
    case scanning, complete, interrupted
}

/// A replaceable, complete snapshot of all resources accumulated so far. Dropping an older
/// envelope never drops resource deltas. Completion describes USB exposure, not iCloud coverage.
public struct DeviceMediaSnapshot: Equatable, Sendable {
    public let sessionID: UUID
    public let deviceID: String
    public let revision: UInt64
    public let records: [SourceMediaRecord]
    public let state: MediaScanState
    public let percentComplete: Int?
    public let iCloudPhotosEnabled: Bool?

    public init(
        sessionID: UUID, deviceID: String, revision: UInt64, records: [SourceMediaRecord],
        state: MediaScanState, percentComplete: Int? = nil, iCloudPhotosEnabled: Bool? = nil
    ) {
        self.sessionID = sessionID
        self.deviceID = deviceID
        self.revision = revision
        self.records = records
        self.state = state
        self.percentComplete = percentComplete.map { min(100, max(0, $0)) }
        self.iCloudPhotosEnabled = iCloudPhotosEnabled
    }
}

@MainActor
public protocol DeviceMediaSource: DeviceBrowsing {
    /// One consumer; coalesced full snapshots, never lossy incremental resource events.
    var catalogs: AsyncStream<DeviceMediaSnapshot> { get }
}

@MainActor
public protocol ThumbnailProviding: AnyObject {
    func thumbnailData(for resourceID: String, sessionID: UUID, maximumPixelSize: Int) async throws -> Data
}

public enum MediaSourceError: Error, Equatable, Sendable {
    case unavailable, staleSession, missingResource, thumbnailUnavailable
}
