import Foundation

public enum MediaKind: String, CaseIterable, Codable, Sendable {
    case photo
    case video
    case livePhoto
    case raw
    case other

    public var isStillImage: Bool {
        self == .photo || self == .livePhoto || self == .raw
    }
}

/// One original file. A logical asset can contain several original resources.
public struct MediaResource: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let filename: String
    public let byteCount: Int64

    public init(id: String, filename: String, byteCount: Int64) {
        self.id = id
        self.filename = filename
        self.byteCount = max(0, byteCount)
    }
}

/// Metadata only. Backup state belongs to a device/destination-scoped status projection.
/// IDs must be globally unique across devices; adapters own source identity normalization.
public struct MediaAsset: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let deviceID: String
    public let resources: [MediaResource]
    public let kind: MediaKind
    public let createdAt: Date?
    public let duration: Double?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let primaryResourceID: String?

    public init(
        id: String,
        deviceID: String,
        resources: [MediaResource],
        kind: MediaKind,
        createdAt: Date?,
        duration: Double? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        primaryResourceID: String? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.resources = resources
        self.kind = kind
        self.createdAt = createdAt
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.primaryResourceID = primaryResourceID ?? resources.first?.id
    }

    public var primaryResource: MediaResource? {
        resources.first { $0.id == primaryResourceID } ?? resources.first
    }

    public var filename: String { primaryResource?.filename ?? "Untitled" }

    public var byteCount: Int64 {
        resources.reduce(0) { sum, resource in
            let addition = sum.addingReportingOverflow(resource.byteCount)
            return addition.overflow ? Int64.max : addition.partialValue
        }
    }
}

public enum BackupStatus: String, CaseIterable, Codable, Sendable {
    case notBackedUp
    case backedUp
    case uncertain
    case failed
}
