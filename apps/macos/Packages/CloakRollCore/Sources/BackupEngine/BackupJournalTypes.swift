import Foundation

/// Durable ownership is recorded before a source operation may write into this private path.
public struct BackupStagingIntent: Codable, Sendable, Equatable {
    public let id: UUID
    public let runID: UUID
    public let assetID: String
    public let resourceID: String
    public let deviceID: String
    public let sourceSessionID: UUID
    public let filename: String
    public let expectedByteCount: Int64
    public let sourceModifiedAt: Date?
    public let sourceMetadataSignature: String
    public let destinationIdentity: String
    public let stagingRelativePath: String

    public init(
        id: UUID, runID: UUID, assetID: String, resourceID: String, deviceID: String, sourceSessionID: UUID,
        filename: String, expectedByteCount: Int64, sourceModifiedAt: Date?, sourceMetadataSignature: String,
        destinationIdentity: String, stagingRelativePath: String
    ) {
        self.id = id
        self.runID = runID
        self.assetID = assetID
        self.resourceID = resourceID
        self.deviceID = deviceID
        self.sourceSessionID = sourceSessionID
        self.filename = filename
        self.expectedByteCount = expectedByteCount
        self.sourceModifiedAt = sourceModifiedAt
        self.sourceMetadataSignature = sourceMetadataSignature
        self.destinationIdentity = destinationIdentity
        self.stagingRelativePath = stagingRelativePath
    }
}

/// File identity is required in addition to its digest. Equal bytes in another file cannot
/// establish that an exclusive rename completed. Birth time also guards against inode reuse.
public struct BackupFileIdentity: Codable, Sendable, Equatable {
    public let device: Int64
    public let inode: UInt64
    public let birthSeconds: Int64
    public let birthNanoseconds: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let changedSeconds: Int64
    public let changedNanoseconds: Int64

    public init(
        device: Int64, inode: UInt64, birthSeconds: Int64, birthNanoseconds: Int64,
        modifiedSeconds: Int64, modifiedNanoseconds: Int64, changedSeconds: Int64, changedNanoseconds: Int64
    ) {
        self.device = device
        self.inode = inode
        self.birthSeconds = birthSeconds
        self.birthNanoseconds = birthNanoseconds
        self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds
        self.changedSeconds = changedSeconds
        self.changedNanoseconds = changedNanoseconds
    }
}

/// Persist this complete value before each exclusive rename attempt. The staging identifier
/// stays fixed while a collision changes only the proposed final relative path.
public struct BackupPublicationIntent: Codable, Sendable, Equatable {
    public let staging: BackupStagingIntent
    public let relativePath: String
    public let byteCount: Int64
    public let sha256: String
    public let verifiedAt: Date
    public let fileIdentity: BackupFileIdentity

    public init(
        staging: BackupStagingIntent, relativePath: String, byteCount: Int64, sha256: String,
        verifiedAt: Date, fileIdentity: BackupFileIdentity
    ) {
        self.staging = staging
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.verifiedAt = verifiedAt
        self.fileIdentity = fileIdentity
    }

    public var verifiedRecord: VerifiedBackupResource {
        VerifiedBackupResource(
            assetID: staging.assetID, resourceID: staging.resourceID, deviceID: staging.deviceID,
            sourceSessionID: staging.sourceSessionID, filename: staging.filename, relativePath: relativePath,
            byteCount: byteCount, sha256: sha256, verifiedAt: verifiedAt, sourceModifiedAt: staging.sourceModifiedAt,
            destinationIdentity: staging.destinationIdentity, sourceMetadataSignature: staging.sourceMetadataSignature
        )
    }
}

public enum BackupRecoveryOutcome: Sendable, Equatable {
    case published(VerifiedBackupResource)
    /// Verified owned staging is preserved for a future explicit retry; it is not a backup.
    case staged
    /// Missing, changed or ambiguous evidence never becomes verified success.
    case unavailable
}
