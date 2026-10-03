import BackupEngine
import BackupPersistence
import Foundation
import GRDB

extension HistoryFixture {
    func staging(_ index: Int = 0, runID: UUID = UUID(), id: UUID = UUID()) throws -> BackupStagingIntent {
        let record = try record(index)
        return BackupStagingIntent(
            id: id, runID: runID, assetID: record.assetID, resourceID: record.resourceID,
            deviceID: record.deviceID, sourceSessionID: record.sourceSessionID, filename: record.filename,
            expectedByteCount: record.byteCount, sourceModifiedAt: record.sourceModifiedAt,
            sourceMetadataSignature: record.sourceMetadataSignature, destinationIdentity: record.destinationIdentity,
            stagingRelativePath: ".cloakroll-staging-\(runID.uuidString.lowercased())/\(UUID().uuidString.lowercased())/\(record.filename)"
        )
    }

    func publication(_ index: Int = 0, verifiedAt: Date = Date(timeIntervalSince1970: 200)) throws -> BackupPublicationIntent {
        let record = try record(index, verifiedAt: verifiedAt)
        return BackupPublicationIntent(
            staging: try staging(index), relativePath: record.relativePath, byteCount: record.byteCount,
            sha256: record.sha256, verifiedAt: record.verifiedAt,
            fileIdentity: BackupFileIdentity(device: 1, inode: 2, birthSeconds: 3, birthNanoseconds: 4,
                                             modifiedSeconds: 5, modifiedNanoseconds: 6, changedSeconds: 7, changedNanoseconds: 8)
        )
    }
}

extension BackupPublicationIntent {
    func changing(path: String? = nil, digest: String? = nil, inode: UInt64? = nil) -> BackupPublicationIntent {
        BackupPublicationIntent(
            staging: staging, relativePath: path ?? relativePath, byteCount: byteCount,
            sha256: digest ?? sha256, verifiedAt: verifiedAt,
            fileIdentity: BackupFileIdentity(
                device: fileIdentity.device, inode: inode ?? fileIdentity.inode,
                birthSeconds: fileIdentity.birthSeconds, birthNanoseconds: fileIdentity.birthNanoseconds,
                modifiedSeconds: fileIdentity.modifiedSeconds, modifiedNanoseconds: fileIdentity.modifiedNanoseconds,
                changedSeconds: fileIdentity.changedSeconds, changedNanoseconds: fileIdentity.changedNanoseconds
            )
        )
    }
}

extension BackupStagingIntent {
    func changing(path: String? = nil, bytes: Int64? = nil, sourceSessionID: UUID? = nil, signature: String? = nil) -> BackupStagingIntent {
        BackupStagingIntent(
            id: id, runID: runID, assetID: assetID, resourceID: resourceID, deviceID: deviceID,
            sourceSessionID: sourceSessionID ?? self.sourceSessionID, filename: filename,
            expectedByteCount: bytes ?? expectedByteCount, sourceModifiedAt: sourceModifiedAt,
            sourceMetadataSignature: signature ?? sourceMetadataSignature, destinationIdentity: destinationIdentity,
            stagingRelativePath: path ?? stagingRelativePath
        )
    }
}

extension HistoryDirectory {
    func journalCounts() async throws -> (pending: Int, resolved: Int) {
        try await database().read { db in
            let pending = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backup_journal WHERE resolved_at IS NULL") ?? 0
            let resolved = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backup_journal WHERE resolved_at IS NOT NULL") ?? 0
            return (pending, resolved)
        }
    }
}
