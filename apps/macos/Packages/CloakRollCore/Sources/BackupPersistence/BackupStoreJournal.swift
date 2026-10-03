import BackupEngine
import Foundation
import GRDB

enum BackupStoreJournal {
    static func stage(_ db: Database, sessionID: UUID, intent: BackupStagingIntent) throws {
        guard let session = try Row.fetchOne(db, sql: "SELECT * FROM backup_session WHERE id = ?",
                                            arguments: [sessionID.uuidString]),
              session["status"] as String == "running" else { throw BackupStoreError.unknownSession }
        guard let resource = try Row.fetchOne(db, sql: """
            SELECT s.*, r.filename, r.expected_bytes FROM session_resource s JOIN resource r ON r.id = s.resource_id
            WHERE s.session_id = ? AND s.runtime_resource_id = ?
            """, arguments: [sessionID.uuidString, intent.resourceID]) else { throw BackupStoreError.invalidRecord }
        try validate(intent, session: session, resource: resource)
        if let row = try entry(db, sessionID: sessionID, resourceID: intent.resourceID) {
            guard try decodeStaging(row) == intent else { throw BackupStoreError.invalidRecord }
            return
        }
        guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backup_record WHERE session_id = ? AND runtime_resource_id = ?",
                               arguments: [sessionID.uuidString, intent.resourceID]) == 0 else { throw BackupStoreError.invalidRecord }
        try db.execute(sql: """
            INSERT INTO backup_journal(id, session_id, runtime_resource_id, staging_payload, created_at)
            VALUES (?, ?, ?, ?, ?)
            """, arguments: [intent.id.uuidString, sessionID.uuidString, intent.resourceID,
                              try JSONEncoder().encode(intent), Date().timeIntervalSince1970])
    }

    static func publish(_ db: Database, sessionID: UUID, intent: BackupPublicationIntent) throws {
        guard try String.fetchOne(db, sql: "SELECT status FROM backup_session WHERE id = ?",
                                  arguments: [sessionID.uuidString]) == "running" else { throw BackupStoreError.unknownSession }
        guard let row = try entry(db, sessionID: sessionID, resourceID: intent.staging.resourceID),
              try decodeStaging(row) == intent.staging else { throw BackupStoreError.invalidRecord }
        try validate(intent)
        let previous = try decodePublication(row)
        if row["resolved_at"] as Double? != nil {
            guard previous == intent else { throw BackupStoreError.invalidRecord }
            return
        }
        if let previous {
            // A collision permits a new exclusive destination name, never new file evidence.
            guard previous.staging == intent.staging, previous.byteCount == intent.byteCount,
                  previous.sha256 == intent.sha256, previous.verifiedAt == intent.verifiedAt,
                  previous.fileIdentity == intent.fileIdentity else { throw BackupStoreError.invalidRecord }
        }
        try db.execute(sql: "UPDATE backup_journal SET publication_payload = ? WHERE id = ?",
                       arguments: [try JSONEncoder().encode(intent), intent.staging.id.uuidString])
    }

    static func validatePublication(_ db: Database, sessionID: UUID, record: VerifiedBackupResource) throws {
        // No intent is expected when freshly revalidating an already recorded original.
        guard let row = try entry(db, sessionID: sessionID, resourceID: record.resourceID) else { return }
        guard let intent = try decodePublication(row), intent.verifiedRecord == record else {
            throw BackupStoreError.invalidRecord
        }
    }

    static func resolve(_ db: Database, sessionID: UUID, resourceID: String) throws {
        try db.execute(sql: """
            UPDATE backup_journal SET resolved_at = COALESCE(resolved_at, ?)
            WHERE session_id = ? AND runtime_resource_id = ?
            """, arguments: [Date().timeIntervalSince1970, sessionID.uuidString, resourceID])
    }

    static func pending(_ db: Database, destinationID: UUID) throws -> [StoredBackupJournalEntry] {
        try Row.fetchAll(db, sql: """
            SELECT j.* FROM backup_journal j JOIN backup_session s ON s.id = j.session_id
            WHERE s.destination_id = ? AND s.status IN ('interrupted', 'cancelled', 'failed')
                AND j.resolved_at IS NULL ORDER BY j.created_at, j.id
            """, arguments: [destinationID.uuidString]).map { row in
                guard let sessionID = UUID(uuidString: row["session_id"]) else { throw BackupStoreError.invalidRecord }
                return try StoredBackupJournalEntry(sessionID: sessionID, staging: decodeStaging(row), publication: decodePublication(row))
            }
    }

    static func reconcile(
        _ db: Database, sessionID: UUID, intent: BackupPublicationIntent, record: VerifiedBackupResource
    ) throws {
        guard let row = try entry(db, sessionID: sessionID, resourceID: intent.staging.resourceID),
              try decodeStaging(row) == intent.staging, try decodePublication(row) == intent,
              record == intent.verifiedRecord else { throw BackupStoreError.invalidRecord }
        try BackupStoreWriting.record(db, sessionID: sessionID, record: record, recovering: true)
        try resolve(db, sessionID: sessionID, resourceID: record.resourceID)
    }

    private static func entry(_ db: Database, sessionID: UUID, resourceID: String) throws -> Row? {
        try Row.fetchOne(db, sql: "SELECT * FROM backup_journal WHERE session_id = ? AND runtime_resource_id = ?",
                         arguments: [sessionID.uuidString, resourceID])
    }

    private static func decodeStaging(_ row: Row) throws -> BackupStagingIntent {
        let intent = try JSONDecoder().decode(BackupStagingIntent.self, from: row["staging_payload"] as Data)
        guard intent.id.uuidString == row["id"] as String,
              intent.resourceID == row["runtime_resource_id"] as String else { throw BackupStoreError.invalidRecord }
        return intent
    }

    private static func decodePublication(_ row: Row) throws -> BackupPublicationIntent? {
        guard let data: Data = row["publication_payload"] else { return nil }
        let intent = try JSONDecoder().decode(BackupPublicationIntent.self, from: data)
        guard try intent.staging == decodeStaging(row) else { throw BackupStoreError.invalidRecord }
        try validate(intent)
        return intent
    }

    private static func validate(_ intent: BackupStagingIntent, session: Row, resource: Row) throws {
        let path = intent.stagingRelativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard intent.deviceID == session["device_key"] as String,
              intent.sourceSessionID.uuidString == session["source_session_id"] as String,
              intent.assetID == resource["runtime_asset_id"] as String,
              intent.filename == resource["filename"] as String,
              intent.expectedByteCount == resource["expected_bytes"] as Int64, intent.expectedByteCount > 0,
              intent.sourceMetadataSignature == resource["source_signature"] as String,
              !intent.destinationIdentity.isEmpty,
              intent.sourceModifiedAt?.timeIntervalSince1970.isFinite != false,
              safePath(intent.stagingRelativePath), path.count == 3,
              path[0] == ".cloakroll-staging-" + intent.runID.uuidString.lowercased(),
              UUID(uuidString: String(path[1])) != nil else { throw BackupStoreError.invalidRecord }
    }

    private static func validate(_ intent: BackupPublicationIntent) throws {
        let identity = intent.fileIdentity
        guard intent.byteCount == intent.staging.expectedByteCount, intent.byteCount > 0,
              intent.sha256.count == 64, intent.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              intent.verifiedAt.timeIntervalSince1970.isFinite, safePath(intent.relativePath),
              !intent.relativePath.split(separator: "/")[0].hasPrefix(".cloakroll-staging-"),
              identity.inode > 0,
              [identity.birthNanoseconds, identity.modifiedNanoseconds, identity.changedNanoseconds]
                .allSatisfy({ (0..<1_000_000_000).contains($0) }) else { throw BackupStoreError.invalidRecord }
    }

    private static func safePath(_ value: String) -> Bool {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }
    }
}
