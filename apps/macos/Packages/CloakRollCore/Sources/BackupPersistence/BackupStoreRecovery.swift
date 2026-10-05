import BackupEngine
import Foundation
import GRDB

extension BackupStore {
    /// Called before publishing a new original, and for incremental reuse. Membership comes
    /// from the durable session registration, including companions that have not transferred.
    public func recoveryEntry(sessionID: UUID, record: VerifiedBackupResource) async throws -> BackupRecoveryEntry {
        try await database.read { db in try BackupStoreRecovery.entry(db, sessionID: sessionID, record: record) }
    }

    public func recoveryEntries(destinationIdentity: String) async throws -> [BackupRecoveryEntry] {
        try await database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM (
                    SELECT b.*, ROW_NUMBER() OVER (
                        PARTITION BY resource_id, relative_path, sha256 ORDER BY verified_at DESC, id DESC
                    ) AS position FROM backup_record b WHERE destination_identity = ?
                ) WHERE position = 1 LIMIT 200001
                """, arguments: [destinationIdentity])
            guard rows.count <= 200_000 else { throw BackupRecoveryError.tooLarge }
            return try rows.map { row in
                try Task.checkCancellation()
                guard let sessionID = UUID(uuidString: row["session_id"]) else { throw BackupStoreError.invalidRecord }
                return try BackupStoreRecovery.entry(db, sessionID: sessionID, record: BackupStoreReading.record(row))
            }
        }
    }

    /// Only accepts a completed byte-verification scan. The caller keeps its destination lease
    /// until this atomic transaction settles. Cancellation before commit rolls back all rows.
    public func importRecovery(_ scan: BackupRecoveryScan, destinationID: UUID) async throws -> Int {
        let cancellation = RecoveryImportCancellation()
        do {
            return try await withTaskCancellationHandler {
                try await database.write { db in
                    var fresh: [BackupRecoveryEntry] = []
                    for entry in scan.entries {
                        try cancellation.check()
                        try entry.validate()
                        let exists = try Bool.fetchOne(db, sql: """
                            SELECT EXISTS(SELECT 1 FROM recovery_import
                            WHERE destination_id = ? AND destination_identity = ? AND entry_key = ?)
                            """, arguments: [destinationID.uuidString, scan.destinationIdentity, entry.key]) == true
                        if !exists { fresh.append(entry) }
                    }
                    let groups = Dictionary(grouping: fresh) { entry in
                        [entry.deviceKey, entry.assetReusable ? "persistent" : entry.record.sourceSessionID.uuidString]
                    }
                    for entries in groups.values {
                        try BackupStoreRecovery.insert(db, entries: entries, destinationID: destinationID,
                                                       rootIdentity: scan.destinationIdentity, checkCancellation: cancellation.check)
                    }
                    try cancellation.check()
                    return fresh.count
                }
            } onCancel: { cancellation.cancel() }
        } catch { throw Self.failure(error) }
    }

}

enum BackupStoreRecovery {
    static func entry(_ db: Database, sessionID: UUID, record: VerifiedBackupResource) throws -> BackupRecoveryEntry {
        guard let session = try Row.fetchOne(db, sql: """
            SELECT s.*, d.persistent FROM backup_session s JOIN device d ON d.device_key = s.device_key WHERE s.id = ?
            """, arguments: [sessionID.uuidString]),
              session["device_key"] as String == record.deviceID,
              session["source_session_id"] as String == record.sourceSessionID.uuidString else { throw BackupStoreError.invalidRecord }
        let rows = try Row.fetchAll(db, sql: """
            SELECT sr.*, r.canonical, r.digest, r.reusable, r.filename, r.expected_bytes,
                a.canonical AS asset_canonical, a.digest AS asset_digest, a.reusable AS asset_reusable
            FROM session_resource sr JOIN resource r ON r.id = sr.resource_id JOIN asset a ON a.id = r.asset_id
            WHERE sr.session_id = ? AND sr.runtime_asset_id = ? ORDER BY r.digest
            """, arguments: [sessionID.uuidString, record.assetID])
        guard let primary = rows.first(where: { $0["runtime_resource_id"] as String == record.resourceID }) else {
            throw BackupStoreError.invalidRecord
        }
        let components = rows.map { row in
            BackupRecoveryEntry.Component(canonical: row["canonical"], digest: row["digest"], reusable: row["reusable"],
                                          filename: row["filename"], byteCount: row["expected_bytes"],
                                              sourceSignature: row["source_signature"])
        }
        let entry = BackupRecoveryEntry(deviceKey: record.deviceID, deviceName: session["device_name"],
                                        persistentDevice: session["persistent"], assetCanonical: primary["asset_canonical"],
                                        assetDigest: primary["asset_digest"], assetReusable: primary["asset_reusable"],
                                        components: components, resourceDigest: primary["digest"], record: record)
        try entry.validate()
        return entry
    }

    static func insert(_ db: Database, entries: [BackupRecoveryEntry], destinationID: UUID, rootIdentity: String,
                       checkCancellation: () throws -> Void) throws {
        guard let first = entries.first else { return }
        let sessionID = UUID()
        let sourceSessionID = first.assetReusable ? UUID() : first.record.sourceSessionID
        let now = Date().timeIntervalSince1970
        let assets = Dictionary(grouping: entries, by: \.assetDigest)
        var totalResources = 0
        var expectedBytes: Int64 = 0
        for group in assets.values {
            guard let asset = group.first else { continue }
            totalResources += asset.components.count
            for part in asset.components {
                let sum = expectedBytes.addingReportingOverflow(part.byteCount)
                guard !sum.overflow else { throw BackupStoreError.invalidRecord }
                expectedBytes = sum.partialValue
            }
        }
        try db.execute(sql: """
            INSERT INTO device(device_key, display_name, persistent, first_seen, last_seen) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(device_key) DO UPDATE SET last_seen = excluded.last_seen
            """, arguments: [first.deviceKey, first.deviceName, first.persistentDevice, now, now])
        try db.execute(sql: "INSERT OR IGNORE INTO destination(id, created_at) VALUES (?, ?)", arguments: [destinationID.uuidString, now])
        try db.execute(sql: """
            INSERT INTO backup_session(id, device_key, device_name, destination_id, source_session_id, status,
                started_at, total_assets, total_resources, expected_bytes) VALUES (?, ?, ?, ?, ?, 'running', ?, ?, ?, ?)
            """, arguments: [sessionID.uuidString, first.deviceKey, first.deviceName, destinationID.uuidString,
                              sourceSessionID.uuidString, now, assets.count, totalResources, expectedBytes])
        for group in assets.values {
            try checkCancellation()
            guard let asset = group.first else { continue }
            try register(db, asset: asset, sessionID: sessionID)
            for entry in group {
                try checkCancellation()
                guard entry.assetCanonical == asset.assetCanonical,
                      entry.components.map(\.digest) == asset.components.map(\.digest),
                      let part = asset.components.first(where: { $0.digest == entry.resourceDigest }) else {
                    throw BackupStoreError.invalidIdentity
                }
                let original = entry.record
                let record = VerifiedBackupResource(
                    assetID: asset.assetDigest, resourceID: entry.resourceDigest, deviceID: first.deviceKey,
                    sourceSessionID: sourceSessionID, filename: part.filename, relativePath: original.relativePath,
                    byteCount: original.byteCount, sha256: original.sha256, verifiedAt: Date(timeIntervalSince1970: now),
                    sourceModifiedAt: original.sourceModifiedAt, destinationIdentity: rootIdentity,
                        sourceMetadataSignature: part.sourceSignature
                )
                try BackupStoreWriting.record(db, sessionID: sessionID, record: record)
                try db.execute(sql: "INSERT INTO recovery_import(destination_id, destination_identity, entry_key) VALUES (?, ?, ?)",
                               arguments: [destinationID.uuidString, rootIdentity, entry.key])
            }
        }
        try db.execute(sql: "UPDATE backup_session SET status = 'recovered', finished_at = ? WHERE id = ?",
                       arguments: [now, sessionID.uuidString])
    }

    private static func register(_ db: Database, asset: BackupRecoveryEntry, sessionID: UUID) throws {
        try db.execute(sql: "INSERT OR IGNORE INTO asset(device_key, canonical, digest, reusable) VALUES (?, ?, ?, ?)",
                       arguments: [asset.deviceKey, asset.assetCanonical, asset.assetDigest, asset.assetReusable])
        guard let assetID = try Int64.fetchOne(db, sql: "SELECT id FROM asset WHERE device_key = ? AND canonical = ?",
                                              arguments: [asset.deviceKey,
                                                  asset.assetCanonical]) else { throw BackupStoreError.invalidIdentity }
        for part in asset.components {
            try db.execute(sql: """
                INSERT OR IGNORE INTO resource(asset_id, canonical, digest, reusable, filename, expected_bytes) VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [assetID, part.canonical, part.digest, part.reusable, part.filename, part.byteCount])
            guard let resourceID = try Int64.fetchOne(db, sql: "SELECT id FROM resource WHERE asset_id = ? AND canonical = ?",
                                                     arguments: [assetID, part.canonical]) else { throw BackupStoreError.invalidIdentity }
            try db.execute(sql: """
                INSERT INTO session_resource(session_id, resource_id, runtime_asset_id, runtime_resource_id,
                    source_signature) VALUES (?, ?, ?, ?, ?)
                """, arguments: [sessionID.uuidString, resourceID, asset.assetDigest, part.digest, part.sourceSignature])
        }
    }
}

/// GRDB runs transactions outside the caller's task context; carry Stop into the database queue.
private final class RecoveryImportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    func check() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }
}
