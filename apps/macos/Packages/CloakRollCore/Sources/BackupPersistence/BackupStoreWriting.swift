import BackupEngine
import Foundation
import GRDB

enum BackupStoreWriting {
    static func begin(_ db: Database, id: UUID, destinationID: UUID, registration: BackupRegistration) throws {
        let now = Date().timeIntervalSince1970
        try db.execute(sql: """
            INSERT INTO device(device_key, display_name, persistent, first_seen, last_seen) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(device_key) DO UPDATE SET display_name = excluded.display_name, last_seen = excluded.last_seen
            """, arguments: [registration.device.id, registration.device.name,
                              registration.device.identity?.isPersistent == true, now, now])
        try db.execute(sql: "INSERT OR IGNORE INTO destination(id, created_at) VALUES (?, ?)",
                       arguments: [destinationID.uuidString, now])
        try db.execute(sql: """
            INSERT INTO backup_session(id, device_key, device_name, destination_id, source_session_id, status,
                started_at, total_assets, total_resources, expected_bytes) VALUES (?, ?, ?, ?, ?, 'running', ?, ?, ?, ?)
            """, arguments: [id.uuidString, registration.device.id, registration.device.name, destinationID.uuidString,
                              registration.sourceSessionID.uuidString, now, registration.assetCount,
                              registration.components.count, registration.expectedBytes])
        for component in registration.components {
            let resourceID = try register(component, deviceKey: registration.device.id, db: db)
            try db.execute(sql: """
                INSERT INTO session_resource(session_id, resource_id, runtime_asset_id, runtime_resource_id, source_signature)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [id.uuidString, resourceID, component.assetID, component.resource.id, component.sourceSignature])
        }
    }

    private static func register(_ component: BackupRegistration.Component, deviceKey: String, db: Database) throws -> Int64 {
        try db.execute(sql: """
            INSERT OR IGNORE INTO asset(device_key, canonical, digest, reusable) VALUES (?, ?, ?, ?)
            """, arguments: [deviceKey, component.asset.canonical, component.asset.digest, component.asset.isReusableAcrossConnections])
        guard let assetID = try Int64.fetchOne(db, sql: "SELECT id FROM asset WHERE device_key = ? AND canonical = ?",
                                              arguments: [deviceKey, component.asset.canonical]) else {
            throw BackupStoreError.invalidIdentity
        }
        try db.execute(sql: """
            INSERT OR IGNORE INTO resource(asset_id, canonical, digest, reusable, filename, expected_bytes) VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [assetID, component.identity.canonical, component.identity.digest,
                              component.identity.isReusableAcrossConnections, component.resource.filename, component.resource.byteCount])
        guard let resourceID = try Int64.fetchOne(db, sql: "SELECT id FROM resource WHERE asset_id = ? AND canonical = ?",
                                                 arguments: [assetID, component.identity.canonical]) else {
            throw BackupStoreError.invalidIdentity
        }
        return resourceID
    }

    static func record(
        _ db: Database, sessionID: UUID, record: VerifiedBackupResource, recovering: Bool = false
    ) throws {
        guard let session = try Row.fetchOne(db, sql: "SELECT * FROM backup_session WHERE id = ?", arguments: [sessionID.uuidString]),
              recovering ? ["interrupted", "cancelled", "failed"].contains(session["status"] as String)
                : session["status"] as String == "running" else { throw BackupStoreError.unknownSession }
        guard let registered = try Row.fetchOne(db, sql: """
            SELECT s.*, r.filename, r.expected_bytes FROM session_resource s JOIN resource r ON r.id = s.resource_id
            WHERE s.session_id = ? AND s.runtime_resource_id = ?
            """, arguments: [sessionID.uuidString, record.resourceID]) else { throw BackupStoreError.invalidRecord }
        try validate(record, session: session, registered: registered)
        if let existing = try Row.fetchOne(db, sql: "SELECT * FROM backup_record WHERE session_id = ? AND runtime_resource_id = ?",
                                           arguments: [sessionID.uuidString, record.resourceID]) {
            guard try matchesStoredRecord(existing, record: record) else { throw BackupStoreError.invalidRecord }
            return
        }
        try db.execute(sql: """
            INSERT INTO backup_record(session_id, resource_id, destination_id, device_id, source_session_id,
                runtime_asset_id, runtime_resource_id, filename, relative_path, byte_count, sha256, verified_at,
                source_modified_at, destination_identity, source_signature)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [sessionID.uuidString, registered["resource_id"] as Int64, session["destination_id"] as String,
                              record.deviceID, record.sourceSessionID.uuidString, record.assetID, record.resourceID,
                              record.filename, record.relativePath, record.byteCount, record.sha256,
                              record.verifiedAt.timeIntervalSince1970,
                              record.sourceModifiedAt?.timeIntervalSince1970, record.destinationIdentity, record.sourceMetadataSignature])
        let complete = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) = COUNT(b.id) FROM session_resource r LEFT JOIN backup_record b
                ON b.session_id = r.session_id AND b.runtime_resource_id = r.runtime_resource_id
            WHERE r.session_id = ? AND r.runtime_asset_id = ?
            """, arguments: [sessionID.uuidString, record.assetID]) == 1
        try db.execute(sql: """
            UPDATE backup_session SET verified_resources = verified_resources + 1, verified_bytes = verified_bytes + ?,
                completed_assets = completed_assets + ? WHERE id = ?
            """, arguments: [record.byteCount, complete ? 1 : 0, sessionID.uuidString])
    }

    private static func matchesStoredRecord(_ row: Row, record: VerifiedBackupResource) throws -> Bool {
        // SQLite stores Unix-epoch doubles. Converting Foundation's reference-epoch doubles can
        // round a fractional timestamp, so replay compares dates at that same stored precision.
        // Source signatures, bytes, digests, names and paths still require exact equality.
        let expected = VerifiedBackupResource(
            assetID: record.assetID, resourceID: record.resourceID, deviceID: record.deviceID,
            sourceSessionID: record.sourceSessionID, filename: record.filename, relativePath: record.relativePath,
            byteCount: record.byteCount, sha256: record.sha256,
            verifiedAt: Date(timeIntervalSince1970: record.verifiedAt.timeIntervalSince1970),
            sourceModifiedAt: record.sourceModifiedAt.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970) },
            destinationIdentity: record.destinationIdentity, sourceMetadataSignature: record.sourceMetadataSignature
        )
        return try BackupStoreReading.record(row) == expected
    }

    private static func validate(_ record: VerifiedBackupResource, session: Row, registered: Row) throws {
        let path = record.relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard record.deviceID == session["device_key"] as String,
              record.sourceSessionID.uuidString == session["source_session_id"] as String,
              record.assetID == registered["runtime_asset_id"] as String,
              record.filename == registered["filename"] as String,
              record.byteCount == registered["expected_bytes"] as Int64, record.byteCount > 0,
              record.sourceMetadataSignature == registered["source_signature"] as String,
              !record.destinationIdentity.isEmpty, record.verifiedAt.timeIntervalSince1970.isFinite,
              !path.isEmpty, path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }),
              record.sha256.count == 64, record.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw BackupStoreError.invalidRecord
        }
    }

    static func finish(_ db: Database, id: UUID, result: BackupSnapshot) throws {
        guard let status = terminalStatus(result.phase) else { throw BackupStoreError.invalidCompletion }
        guard let session = try Row.fetchOne(db, sql: "SELECT * FROM backup_session WHERE id = ?", arguments: [id.uuidString]),
              session["status"] as String == "running" else { throw BackupStoreError.unknownSession }
        let totalAssets: Int = session["total_assets"]
        let totalResources: Int = session["total_resources"]
        let completedAssets: Int = session["completed_assets"]
        let verifiedResources: Int = session["verified_resources"]
        let verifiedBytes: Int64 = session["verified_bytes"]
        if status == .completed {
            guard completedAssets == totalAssets, verifiedResources == totalResources,
                  result.completedAssets == completedAssets, result.verifiedResources == verifiedResources,
                  result.verifiedBytes == verifiedBytes else { throw BackupStoreError.invalidCompletion }
        }
        let expectedBytes: Int64 = session["expected_bytes"]
        try db.execute(sql: "UPDATE backup_session SET status = ?, finished_at = ?, transferred_bytes = ? WHERE id = ?",
                       arguments: [status.rawValue, Date().timeIntervalSince1970,
                                   min(expectedBytes, max(0, result.transferredBytes)), id.uuidString])
    }

    private static func terminalStatus(_ phase: BackupPhase) -> StoredBackupSessionStatus? {
        switch phase {
        case .completed: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        default: nil
        }
    }
}
