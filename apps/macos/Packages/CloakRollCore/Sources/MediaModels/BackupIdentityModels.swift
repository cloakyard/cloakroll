import Foundation

/// Versioned original-resource evidence. Runtime IDs only address the current camera connection.
/// Metadata correspondence is conservative matching, not proof of equal source bytes.
public struct BackupCatalogIdentity: Codable, Equatable, Sendable {
    public let deviceKey: String
    public let sessionID: UUID
    public let assets: [String: BackupAssetIdentity]

    public init(deviceKey: String, sessionID: UUID, assets: [String: BackupAssetIdentity]) {
        self.deviceKey = deviceKey
        self.sessionID = sessionID
        self.assets = assets
    }
}

public struct BackupAssetIdentity: Codable, Equatable, Sendable {
    public let assetID: String
    public let canonical: String
    public let digest: String
    public let isReusableAcrossConnections: Bool
    public let resources: [String: BackupResourceIdentity]

    public init(
        assetID: String, canonical: String, digest: String, isReusableAcrossConnections: Bool,
        resources: [String: BackupResourceIdentity]
    ) {
        self.assetID = assetID
        self.canonical = canonical
        self.digest = digest
        self.isReusableAcrossConnections = isReusableAcrossConnections
        self.resources = resources
    }
}

public struct BackupResourceIdentity: Codable, Equatable, Sendable {
    public let resourceID: String
    public let canonical: String
    public let digest: String
    public let isReusableAcrossConnections: Bool

    public init(resourceID: String, canonical: String, digest: String, isReusableAcrossConnections: Bool) {
        self.resourceID = resourceID
        self.canonical = canonical
        self.digest = digest
        self.isReusableAcrossConnections = isReusableAcrossConnections
    }
}
