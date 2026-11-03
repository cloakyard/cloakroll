import BackupEngine
import Foundation
import GRDB
import MediaModels

public struct BackupContinuationPlan: Sendable {
    public let assetIDs: [String]
    public let unavailableAssets: Int
    public let folderLayout: BackupFolderLayout
}

extension BackupStore {
    public func continuation(
        sessionID: UUID, destinationID: UUID, identity: BackupCatalogIdentity
    ) async throws -> BackupContinuationPlan {
        do {
            return try await database.read { db in
                try BackupContinuation.read(db, sessionID: sessionID, destinationID: destinationID, identity: identity)
            }
        } catch { throw Self.failure(error) }
    }
}

enum BackupContinuation {
    static func read(
        _ db: Database, sessionID: UUID, destinationID: UUID, identity: BackupCatalogIdentity
    ) throws -> BackupContinuationPlan {
        guard let session = try Row.fetchOne(db, sql: """
            SELECT s.*, d.persistent FROM backup_session s JOIN device d ON d.device_key = s.device_key
            WHERE s.id = ? AND s.destination_id = ? AND s.device_key = ?
                AND s.status IN ('failed', 'cancelled', 'interrupted')
                AND NOT EXISTS(SELECT 1 FROM backup_session child WHERE child.continued_from = s.id)
            """, arguments: [sessionID.uuidString, destinationID.uuidString, identity.deviceKey]),
              let layoutText: String = session["folder_layout"], let layout = BackupFolderLayout(rawValue: layoutText) else {
            throw BackupStoreError.invalidIdentity
        }
        // Session-only evidence can retry on its original live connection, never after reconnect.
        // In that case both runtime addresses and the complete canonical evidence must still match.
        let sameConnection = session["source_session_id"] as String == identity.sessionID.uuidString
        guard sameConnection || session["persistent"] as Bool else { throw BackupStoreError.invalidIdentity }
        let rows = try Row.fetchAll(db, sql: """
            SELECT sr.runtime_asset_id, sr.runtime_resource_id, a.canonical, a.digest, a.reusable,
                r.canonical AS resource_canonical, r.digest AS resource_digest, r.reusable AS resource_reusable
            FROM session_resource sr JOIN resource r ON r.id = sr.resource_id JOIN asset a ON a.id = r.asset_id
            WHERE sr.session_id = ? ORDER BY sr.runtime_asset_id
            """, arguments: [sessionID.uuidString])
        let groups = Dictionary(grouping: rows) { $0["runtime_asset_id"] as String }
        guard groups.count == session["total_assets"] as Int else { throw BackupStoreError.invalidRecord }
        let current = Dictionary(grouping: identity.assets.values.filter {
            sameConnection || $0.isReusableAcrossConnections
        }, by: \.canonical)
        var ids: [String] = []
        for original in groups.values {
            try Task.checkCancellation()
            guard let first = original.first,
                  let matches = current[first["canonical"] as String], matches.count == 1,
                  let match = matches.first, match.digest == first["digest"] as String,
                  match.isReusableAcrossConnections == first["reusable"] as Bool,
                  !sameConnection || match.assetID == first["runtime_asset_id"] as String,
                  match.resources.count == original.count,
                  original.allSatisfy({ row in
                      match.resources.values.contains {
                          (sameConnection || $0.isReusableAcrossConnections)
                              && $0.isReusableAcrossConnections == row["resource_reusable"] as Bool
                              && (!sameConnection || $0.resourceID == row["runtime_resource_id"] as String)
                              && $0.canonical == row["resource_canonical"] as String && $0.digest == row["resource_digest"] as String
                      }
                  }) else { continue }
            ids.append(match.assetID)
        }
        guard Set(ids).count == ids.count else { throw BackupStoreError.invalidIdentity }
        return BackupContinuationPlan(assetIDs: ids.sorted(), unavailableAssets: groups.count - ids.count, folderLayout: layout)
    }
}
