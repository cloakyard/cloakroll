import BackupEngine
import Foundation
import GRDB
import MediaModels

enum BackupStoreReading {
    private struct IdentityKey: Hashable {
        let assetDigest: String
        let assetCanonical: String
        let resourceDigest: String
        let resourceCanonical: String
    }

    private struct HistoricalRecord {
        let reusable: Bool
        let record: VerifiedBackupResource
    }

    private struct ContentEvidence: Hashable {
        let byteCount: Int64
        let sha256: String
        let destinationIdentity: String
    }

    static func candidates(
        _ db: Database, deviceKey: String, destinationID: UUID, identity: BackupCatalogIdentity
    ) throws -> [StoredBackupCandidate] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT b.*, a.digest AS asset_digest, a.canonical AS asset_canonical,
                r.digest AS resource_digest, r.canonical AS resource_canonical,
                (a.reusable AND r.reusable AND d.persistent) AS reusable
            FROM backup_record b JOIN resource r ON r.id = b.resource_id
                JOIN asset a ON a.id = r.asset_id JOIN device d ON d.device_key = a.device_key
            WHERE a.device_key = ? AND b.destination_id = ? ORDER BY b.verified_at DESC, b.id DESC
            """, arguments: [deviceKey, destinationID.uuidString])
        var history: [IdentityKey: [HistoricalRecord]] = [:]
        for row in rows {
            let key = IdentityKey(assetDigest: row["asset_digest"], assetCanonical: row["asset_canonical"],
                                  resourceDigest: row["resource_digest"], resourceCanonical: row["resource_canonical"])
            history[key, default: []].append(HistoricalRecord(reusable: row["reusable"], record: try record(row)))
        }
        let assetOccurrences = Dictionary(grouping: identity.assets.values, by: \.canonical).mapValues(\.count)
        var candidates: [StoredBackupCandidate] = []
        for (assetID, asset) in identity.assets {
            guard assetID == asset.assetID, assetOccurrences[asset.canonical] == 1 else { continue }
            let resourceOccurrences = Dictionary(grouping: asset.resources.values, by: \.canonical).mapValues(\.count)
            for (resourceID, resource) in asset.resources {
                guard resourceID == resource.resourceID, resourceOccurrences[resource.canonical] == 1 else { continue }
                let key = IdentityKey(assetDigest: asset.digest, assetCanonical: asset.canonical,
                                      resourceDigest: resource.digest, resourceCanonical: resource.canonical)
                let reusable = asset.isReusableAcrossConnections && resource.isReusableAcrossConnections
                let matches = history[key, default: []].filter {
                    $0.record.sourceSessionID == identity.sessionID || (reusable && $0.reusable)
                }
                // Multiple historical paths with identical content can be checked locally. Conflicting
                // content or a replaced destination root is ambiguous and must not suppress a download.
                let content = Set(matches.map { ContentEvidence(
                    byteCount: $0.record.byteCount, sha256: $0.record.sha256, destinationIdentity: $0.record.destinationIdentity
                ) })
                guard content.count == 1, let match = matches.first else { continue }
                candidates.append(StoredBackupCandidate(assetID: assetID, resourceID: resourceID, record: match.record))
            }
        }
        return candidates.sorted { ($0.assetID, $0.resourceID) < ($1.assetID, $1.resourceID) }
    }

    static func record(_ row: Row) throws -> VerifiedBackupResource {
        guard let sourceSessionID = UUID(uuidString: row["source_session_id"]) else { throw BackupStoreError.invalidRecord }
        let modified: Double? = row["source_modified_at"]
        return VerifiedBackupResource(
            assetID: row["runtime_asset_id"], resourceID: row["runtime_resource_id"], deviceID: row["device_id"],
            sourceSessionID: sourceSessionID, filename: row["filename"], relativePath: row["relative_path"],
            byteCount: row["byte_count"], sha256: row["sha256"], verifiedAt: Date(timeIntervalSince1970: row["verified_at"]),
            sourceModifiedAt: modified.map(Date.init(timeIntervalSince1970:)), destinationIdentity: row["destination_identity"],
            sourceMetadataSignature: row["source_signature"]
        )
    }

    static func sessions(_ db: Database, limit: Int) throws -> [StoredBackupSession] {
        try Row.fetchAll(db, sql: "SELECT * FROM backup_session ORDER BY started_at DESC, id DESC LIMIT ?",
                         arguments: [limit]).map { row in
            guard let id = UUID(uuidString: row["id"]), let destinationID = UUID(uuidString: row["destination_id"]),
                  let status = StoredBackupSessionStatus(rawValue: row["status"]) else { throw BackupStoreError.unavailable }
            let finished: Double? = row["finished_at"]
            return StoredBackupSession(
                id: id, deviceName: row["device_name"], destinationID: destinationID, status: status,
                startedAt: Date(timeIntervalSince1970: row["started_at"]), finishedAt: finished.map(Date.init(timeIntervalSince1970:)),
                totalAssets: row["total_assets"], totalResources: row["total_resources"], completedAssets: row["completed_assets"],
                verifiedResources: row["verified_resources"], verifiedBytes: row["verified_bytes"],
                transferredBytes: row["transferred_bytes"]
            )
        }
    }
}
