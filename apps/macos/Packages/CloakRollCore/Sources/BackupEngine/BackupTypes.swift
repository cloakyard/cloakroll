import Foundation
import MediaModels

public enum BackupPhase: String, Equatable, Sendable {
    case idle, preparing, downloading, verifying, completed, failed, cancelling, cancelled
}

public enum BackupEngineError: Error, Equatable, Sendable {
    case busy
    case invalidSelection
    case invalidResourceSize
    case sourceSizeChanged
    case persistenceFailed
}

extension BackupEngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .busy: "A backup is already running."
        case .invalidSelection: "The selected media contains missing or ambiguous original resources."
        case .invalidResourceSize: "An original has no reliable size. Reconnect your iPhone and try again."
        case .sourceSizeChanged: "The original changed or its download format differs from the catalog. Refresh the library and try again."
        case .persistenceFailed:
            "The original was saved, but its backup record couldn’t be stored. Try again to finish recording the backup."
        }
    }
}

public struct BackupDownloadRequest: Sendable, Equatable {
    public let resource: MediaResource
    public let sessionID: UUID
    public let directory: URL
    public let filename: String

    public init(resource: MediaResource, sessionID: UUID, directory: URL, filename: String) {
        self.resource = resource
        self.sessionID = sessionID
        self.directory = directory
        self.filename = filename
    }
}

/// A replaceable, complete progress value. Transferred bytes are not verified bytes.
public struct BackupSnapshot: Sendable, Equatable {
    public var runID: UUID?
    public var phase: BackupPhase
    public var totalAssets: Int
    public var totalResources: Int
    public var expectedBytes: Int64
    public var completedAssets: Int
    public var verifiedResources: Int
    public var verifiedBytes: Int64
    public var transferredBytes: Int64
    public var currentFilename: String?
    public var currentResourceBytes: Int64
    public var currentResourceExpectedBytes: Int64
    public var completedAssetIDs: Set<String>
    public var message: String?

    public init(
        runID: UUID? = nil, phase: BackupPhase = .idle, totalAssets: Int = 0, totalResources: Int = 0,
        expectedBytes: Int64 = 0, completedAssets: Int = 0, verifiedResources: Int = 0,
        verifiedBytes: Int64 = 0, transferredBytes: Int64 = 0, currentFilename: String? = nil,
        currentResourceBytes: Int64 = 0, currentResourceExpectedBytes: Int64 = 0,
        completedAssetIDs: Set<String> = [], message: String? = nil
    ) {
        self.runID = runID
        self.phase = phase
        self.totalAssets = totalAssets
        self.totalResources = totalResources
        self.expectedBytes = expectedBytes
        self.completedAssets = completedAssets
        self.verifiedResources = verifiedResources
        self.verifiedBytes = verifiedBytes
        self.transferredBytes = transferredBytes
        self.currentFilename = currentFilename
        self.currentResourceBytes = currentResourceBytes
        self.currentResourceExpectedBytes = currentResourceExpectedBytes
        self.completedAssetIDs = completedAssetIDs
        self.message = message
    }
}

/// Evidence about one finalized local original. The SHA-256 is local byte evidence, not a source
/// hash comparison. A local record alone does not establish that the persistence hook succeeded.
public struct VerifiedBackupResource: Sendable, Equatable {
    public let assetID: String
    public let resourceID: String
    public let deviceID: String
    public let sourceSessionID: UUID
    public let filename: String
    public let relativePath: String
    public let byteCount: Int64
    public let sha256: String
    public let verifiedAt: Date
    public let sourceModifiedAt: Date?
    public let destinationIdentity: String
    public let sourceMetadataSignature: String

    public init(
        assetID: String, resourceID: String, deviceID: String, sourceSessionID: UUID, filename: String,
        relativePath: String, byteCount: Int64, sha256: String, verifiedAt: Date,
        sourceModifiedAt: Date? = nil, destinationIdentity: String = "", sourceMetadataSignature: String = ""
    ) {
        self.assetID = assetID
        self.resourceID = resourceID
        self.deviceID = deviceID
        self.sourceSessionID = sourceSessionID
        self.filename = filename
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.verifiedAt = verifiedAt
        self.sourceModifiedAt = sourceModifiedAt
        self.destinationIdentity = destinationIdentity
        self.sourceMetadataSignature = sourceMetadataSignature
    }
}

public struct BackupResult: Sendable, Equatable {
    public let snapshot: BackupSnapshot
    public let records: [VerifiedBackupResource]

    public init(snapshot: BackupSnapshot, records: [VerifiedBackupResource]) {
        self.snapshot = snapshot
        self.records = records
    }
}
