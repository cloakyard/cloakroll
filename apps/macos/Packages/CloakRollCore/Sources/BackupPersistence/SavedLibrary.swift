import BackupEngine
import Foundation
import GRDB
import MediaModels

public struct SavedLibraryQuery: Sendable, Hashable {
    public let deviceKey: String
    public let destinationID: UUID
    public var kind: MediaKind?
    public var capturedAfter: Date?
    public var capturedBefore: Date?

    public init(deviceKey: String, destinationID: UUID, kind: MediaKind? = nil,
                capturedAfter: Date? = nil, capturedBefore: Date? = nil) {
        self.deviceKey = deviceKey
        self.destinationID = destinationID
        self.kind = kind
        self.capturedAfter = capturedAfter
        self.capturedBefore = capturedBefore
    }
}

public struct SavedLibraryCursor: Sendable, Equatable {
    public let query: SavedLibraryQuery
    public let date: Double
    public let assetID: Int64
}

public struct SavedLibraryItem: Sendable, Identifiable {
    public let id: Int64
    public let kind: MediaKind?
    public let capturedAt: Date?
    public let expectedOriginals: Int
    /// Primary resource first when metadata is available. Includes all committed companions.
    public let originals: [VerifiedBackupResource]
}

public struct SavedLibraryPage: Sendable {
    public let items: [SavedLibraryItem]
    public let nextCursor: SavedLibraryCursor?
}

extension BackupStore {
    public func savedLibrary(
        query: SavedLibraryQuery, after cursor: SavedLibraryCursor? = nil, limit: Int = 60
    ) async throws -> SavedLibraryPage {
        guard cursor == nil || cursor?.query == query else { throw BackupStoreError.invalidRecord }
        do {
            return try await database.read { db in
                try SavedLibraryReading.page(db, query: query, after: cursor, limit: min(100, max(1, limit)))
            }
        } catch { throw Self.failure(error) }
    }
}

enum SavedLibraryReading {
    static func recordMetadata(_ db: Database, assets: [MediaAsset], identity: BackupCatalogIdentity) throws {
        for asset in assets {
            guard let evidence = identity.assets[asset.id] else { throw BackupStoreError.invalidIdentity }
            let primary = asset.primaryResourceID.flatMap { evidence.resources[$0]?.canonical }
            try db.execute(sql: "UPDATE asset SET kind = ?, captured_at = ?, primary_canonical = ? WHERE device_key = ? AND canonical = ?",
                           arguments: [asset.kind.rawValue, asset.createdAt?.timeIntervalSince1970, primary,
                                       identity.deviceKey, evidence.canonical])
        }
    }

    static func page(
        _ db: Database, query: SavedLibraryQuery, after cursor: SavedLibraryCursor?, limit: Int
    ) throws -> SavedLibraryPage {
        var clause = "a.device_key = ?"
        var arguments: StatementArguments = [query.deviceKey]
        if let kind = query.kind { clause += " AND a.kind = ?"; arguments += [kind.rawValue] }
        if let date = query.capturedAfter { clause += " AND a.captured_at >= ?"; arguments += [date.timeIntervalSince1970] }
        if let date = query.capturedBefore { clause += " AND a.captured_at < ?"; arguments += [date.timeIntervalSince1970] }
        if let cursor {
            clause += " AND (COALESCE(a.captured_at, 0) < ? OR (COALESCE(a.captured_at, 0) = ? AND a.id < ?))"
            arguments += [cursor.date, cursor.date, cursor.assetID]
        }
        arguments += [query.destinationID.uuidString, limit + 1]
        let rows = try Row.fetchAll(db, sql: """
            SELECT a.*, (SELECT COUNT(*) FROM resource r WHERE r.asset_id = a.id) AS expected_originals FROM asset a
            WHERE \(clause) AND EXISTS (
                SELECT 1 FROM resource r JOIN backup_record b ON b.resource_id = r.id
                    JOIN backup_session s ON s.id = b.session_id
                WHERE r.asset_id = a.id AND b.destination_id = ? AND s.status != 'running')
            ORDER BY COALESCE(a.captured_at, 0) DESC, a.id DESC LIMIT ?
            """, arguments: arguments)
        let selected = Array(rows.prefix(limit))
        var items: [SavedLibraryItem] = []
        for row in selected {
            try Task.checkCancellation()
            let id: Int64 = row["id"]
            let records = try Row.fetchAll(db, sql: """
                SELECT b.* FROM backup_record b JOIN resource r ON r.id = b.resource_id
                    JOIN backup_session s ON s.id = b.session_id
                WHERE r.asset_id = ? AND b.destination_id = ? AND s.status != 'running'
                    AND b.id = (SELECT MAX(b2.id) FROM backup_record b2 JOIN backup_session s2 ON s2.id = b2.session_id
                        WHERE b2.resource_id = r.id AND b2.destination_id = b.destination_id AND s2.status != 'running')
                ORDER BY CASE WHEN r.canonical = ? THEN 0 ELSE 1 END, r.id
                """, arguments: [id, query.destinationID.uuidString, row["primary_canonical"] as String?])
                .map(BackupStoreReading.record)
            items.append(SavedLibraryItem(id: id, kind: (row["kind"] as String?).flatMap(MediaKind.init(rawValue:)),
                                          capturedAt: (row["captured_at"] as Double?).map(Date.init(timeIntervalSince1970:)),
                                          expectedOriginals: row["expected_originals"], originals: records))
        }
        let next = rows.count > limit ? selected.last.map {
            SavedLibraryCursor(query: query, date: ($0["captured_at"] as Double?) ?? 0, assetID: $0["id"])
        } : nil
        return SavedLibraryPage(items: items, nextCursor: next)
    }
}
