import BackupEngine
import Foundation
import GRDB
import MediaModels

enum BackupStoreReading {
    private struct RequestedIdentity {
        let assetID: String
        let resourceID: String
        let assetDigest: String
        let assetCanonical: String
        let resourceDigest: String
        let resourceCanonical: String
        let reusable: Bool
    }

    private struct ContentEvidence: Hashable {
        let byteCount: Int64
        let sha256: String
        let destinationIdentity: String
    }

    private struct CandidateEvidence {
        var content: ContentEvidence?
        var ambiguous = false
        var newest: VerifiedBackupResource?
        var newestDate = -Double.infinity
        var newestID = Int64.min

        mutating func include(_ record: VerifiedBackupResource, date: Double, id: Int64) {
            let evidence = ContentEvidence(byteCount: record.byteCount, sha256: record.sha256,
                                           destinationIdentity: record.destinationIdentity)
            if let content { ambiguous = ambiguous || content != evidence } else { content = evidence }
            if date > newestDate || (date == newestDate && id > newestID) {
                newest = record
                newestDate = date
                newestID = id
            }
        }
    }

    private static let batchSize = 64

    static func candidates(
        _ db: Database, deviceKey: String, destinationID: UUID, identity: BackupCatalogIdentity
    ) throws -> [StoredBackupCandidate] {
        // A new destination cannot match any current asset. The destination index makes this
        // check independent of catalog size and avoids preparing thousands of empty batches.
        guard !identity.assets.isEmpty, try Bool.fetchOne(db, sql: """
            SELECT EXISTS(SELECT 1 FROM backup_record WHERE destination_id = ?)
            """, arguments: [destinationID.uuidString]) == true else { return [] }
        // Reject duplicate current identities across the full catalog, not separately per batch.
        let assetOccurrences = identity.assets.values.reduce(into: [String: Int]()) {
            $0[$1.canonical, default: 0] += 1
        }
        var candidates: [StoredBackupCandidate] = []
        var batch: [RequestedIdentity] = []
        batch.reserveCapacity(batchSize)
        for (assetID, asset) in identity.assets {
            guard assetID == asset.assetID, assetOccurrences[asset.canonical] == 1 else { continue }
            let resourceOccurrences = asset.resources.values.reduce(into: [String: Int]()) {
                $0[$1.canonical, default: 0] += 1
            }
            for (resourceID, resource) in asset.resources {
                guard resourceID == resource.resourceID, resourceOccurrences[resource.canonical] == 1 else { continue }
                batch.append(RequestedIdentity(
                    assetID: assetID, resourceID: resourceID, assetDigest: asset.digest, assetCanonical: asset.canonical,
                    resourceDigest: resource.digest, resourceCanonical: resource.canonical,
                    reusable: asset.isReusableAcrossConnections && resource.isReusableAcrossConnections
                ))
                if batch.count == batchSize {
                    candidates += try readBatch(db, deviceKey: deviceKey, destinationID: destinationID,
                                                sessionID: identity.sessionID, batch: batch)
                    batch.removeAll(keepingCapacity: true)
                }
            }
        }
        if !batch.isEmpty {
            candidates += try readBatch(db, deviceKey: deviceKey, destinationID: destinationID,
                                        sessionID: identity.sessionID, batch: batch)
        }
        return candidates.sorted { ($0.assetID, $0.resourceID) < ($1.assetID, $1.resourceID) }
    }

    private static func readBatch(
        _ db: Database, deviceKey: String, destinationID: UUID, sessionID: UUID, batch: [RequestedIdentity]
    ) throws -> [StoredBackupCandidate] {
        var arguments = StatementArguments()
        for key in batch {
            arguments += [key.assetDigest, key.resourceDigest]
        }
        arguments += [deviceKey, destinationID.uuidString]
        let statement = try db.cachedStatement(sql: candidateQuery(batchSize: batch.count))
        let rows = try Row.fetchCursor(statement, arguments: arguments)
        var evidence = Array(repeating: CandidateEvidence(), count: batch.count)
        while let row = try rows.next() {
            let index: Int = row["requested_index"]
            let key = batch[index]
            let assetCanonical: String = row["matched_asset_canonical"]
            let resourceCanonical: String = row["matched_resource_canonical"]
            // Swift canonical equality intentionally retains its Unicode normalization semantics.
            // SQLite's BINARY collation must not silently change the existing identity comparison.
            guard assetCanonical == key.assetCanonical, resourceCanonical == key.resourceCanonical else { continue }
            // Decode every matching row, including older or ineligible records. Do not make a
            // damaged older record disappear merely because a newer candidate was found first.
            let historical = try record(row)
            let reusable: Bool = row["reusable"]
            guard historical.sourceSessionID == sessionID || (key.reusable && reusable) else { continue }
            evidence[index].include(historical, date: row["verified_at"], id: row["id"])
        }
        return batch.enumerated().compactMap { index, key in
            // Conflicting content or destination roots remain ambiguous across ALL matching
            // history. The cursor has no row limit, and keeps only one candidate per key.
            guard !evidence[index].ambiguous, let record = evidence[index].newest else { return nil }
            return StoredBackupCandidate(assetID: key.assetID, resourceID: key.resourceID, record: record)
        }
    }

    /// Kept internal so query-plan tests exercise the actual bounded query. Explicit join order
    /// prevents SQLite from beginning with a scan of every backup record in the destination.
    static func candidateQuery(batchSize: Int) -> String {
        precondition((1...Self.batchSize).contains(batchSize))
        let values = (0..<batchSize).map { "(\($0), ?, ?)" }.joined(separator: ", ")
        return """
            WITH requested(ordinal, asset_digest, resource_digest) AS (VALUES \(values))
            SELECT q.ordinal AS requested_index, b.*, a.canonical AS matched_asset_canonical,
                r.canonical AS matched_resource_canonical, (a.reusable AND r.reusable AND d.persistent) AS reusable
            FROM requested q
            CROSS JOIN asset a INDEXED BY asset_lookup
                ON a.device_key = ? AND a.digest = q.asset_digest
            CROSS JOIN resource r INDEXED BY resource_lookup
                ON r.asset_id = a.id AND r.digest = q.resource_digest
            CROSS JOIN backup_record b INDEXED BY record_destination
                ON b.destination_id = ? AND b.resource_id = r.id
            CROSS JOIN device d ON d.device_key = a.device_key
            """
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

    static func sessions(_ db: Database, limit: Int, filter: BackupHistoryFilter) throws -> [StoredBackupSession] {
        try sessionRows(db, limit: limit, filter: filter, after: nil).map(session)
    }

    static func sessionPage(
        _ db: Database, limit: Int, filter: BackupHistoryFilter, after cursor: BackupHistoryCursor?
    ) throws -> BackupHistoryPage {
        let rows = try sessionRows(db, limit: limit + 1, filter: filter, after: cursor)
        let visible = rows.prefix(limit)
        let next = rows.count > limit ? visible.last.map {
            BackupHistoryCursor(startedAt: $0["started_at"], id: $0["id"], filter: filter)
        } : nil
        return try BackupHistoryPage(sessions: visible.map(session), nextCursor: next)
    }

    private static func sessionRows(
        _ db: Database, limit: Int, filter: BackupHistoryFilter, after cursor: BackupHistoryCursor?
    ) throws -> [Row] {
        var conditions: [String] = []
        var arguments = StatementArguments()
        if let key = filter.deviceKey {
            conditions.append("device_key = ?")
            arguments += [key]
        }
        switch filter.outcome {
        case .all: break
        case .completed: conditions.append("(status = 'completed' OR (status = 'recovered' AND verified_resources = total_resources))")
        case .unfinished:
            conditions.append("""
                (status IN ('running', 'failed', 'cancelled', 'interrupted')
                OR (status = 'recovered' AND verified_resources < total_resources))
                """)
        }
        if let cursor {
            conditions.append("(started_at, id) < (?, ?)")
            arguments += [cursor.startedAt, cursor.id]
        }
        let clause = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        arguments += [limit]
        return try Row.fetchAll(db, sql: "SELECT * FROM backup_session" + clause + " ORDER BY started_at DESC, id DESC LIMIT ?",
                               arguments: arguments)
    }

    static func session(_ row: Row) throws -> StoredBackupSession {
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
