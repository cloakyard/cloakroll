import BackupEngine
import Foundation

/// Durable intent only. Neither a staged nor a publication row proves that a final file exists.
public struct StoredBackupJournalEntry: Sendable, Equatable {
    public let sessionID: UUID
    public let staging: BackupStagingIntent
    public let publication: BackupPublicationIntent?

    public init(sessionID: UUID, staging: BackupStagingIntent, publication: BackupPublicationIntent?) {
        self.sessionID = sessionID
        self.staging = staging
        self.publication = publication
    }
}

/// A metadata match only. The local original must be revalidated before displaying backup status.
public struct StoredBackupCandidate: Sendable, Equatable {
    public let assetID: String
    public let resourceID: String
    public let record: VerifiedBackupResource

    public init(assetID: String, resourceID: String, record: VerifiedBackupResource) {
        self.assetID = assetID
        self.resourceID = resourceID
        self.record = record
    }
}

public enum StoredBackupSessionStatus: String, Sendable, Equatable {
    case running, completed, failed, cancelled, interrupted, recovered
}

public struct StoredBackupSession: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let deviceName: String
    public let destinationID: UUID
    public let status: StoredBackupSessionStatus
    public let startedAt: Date
    public let finishedAt: Date?
    public let totalAssets: Int
    public let totalResources: Int
    public let completedAssets: Int
    public let verifiedResources: Int
    public let verifiedBytes: Int64
    public let transferredBytes: Int64

    public init(
        id: UUID, deviceName: String, destinationID: UUID, status: StoredBackupSessionStatus,
        startedAt: Date, finishedAt: Date?, totalAssets: Int, totalResources: Int,
        completedAssets: Int, verifiedResources: Int, verifiedBytes: Int64, transferredBytes: Int64
    ) {
        self.id = id
        self.deviceName = deviceName
        self.destinationID = destinationID
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.totalAssets = totalAssets
        self.totalResources = totalResources
        self.completedAssets = completedAssets
        self.verifiedResources = verifiedResources
        self.verifiedBytes = verifiedBytes
        self.transferredBytes = transferredBytes
    }
}

public enum BackupStoreError: Error, Sendable, Equatable, LocalizedError {
    case unavailable
    case invalidIdentity
    case invalidRecord
    case unknownSession
    case invalidCompletion

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Backup history could not be read or saved. Your original files have not been removed."
        case .invalidIdentity: "The current library cannot be matched safely. Refresh the library and try again."
        case .invalidRecord: "The saved original does not match this backup session. Its file has been preserved."
        case .unknownSession: "This backup session is no longer active. Its saved originals have been preserved."
        case .invalidCompletion: "Backup history could not confirm every original. Its saved files have been preserved."
        }
    }
}
