import BackupEngine
import Foundation
import GRDB

/// A dated check of one session's committed originals, not proof of whole-library coverage.
public struct StoredIntegrityCheck: Sendable, Equatable {
    public let checkedAt: Date
    public let totalFiles: Int
    public let matchingFiles: Int
}

public struct BackupHealthEntry: Sendable, Identifiable {
    public var id: UUID { latestSession.id }
    public let deviceKey: String
    public let latestSession: StoredBackupSession
    public let lastCompletedAt: Date?
    public let integrityCheck: StoredIntegrityCheck?
}

extension BackupStore {
    public func recordIntegrityCheck(sessionID: UUID, result: SavedBackupCheckProgress, at date: Date = Date()) async throws {
        guard result.totalFiles > 0, result.checkedFiles == result.totalFiles,
              (0...result.totalFiles).contains(result.matchingFiles), date.timeIntervalSince1970.isFinite else {
            throw BackupStoreError.invalidRecord
        }
        do {
            try await database.write { db in
                guard let session = try Row.fetchOne(db, sql: "SELECT * FROM backup_session WHERE id = ?",
                                                    arguments: [sessionID.uuidString]),
                      session["status"] as String != "running", session["verified_resources"] as Int == result.totalFiles else {
                    throw BackupStoreError.invalidRecord
                }
                try db.execute(sql: """
                    INSERT INTO integrity_check(session_id, checked_at, total_files, matching_files) VALUES (?, ?, ?, ?)
                    ON CONFLICT(session_id) DO UPDATE SET checked_at = excluded.checked_at,
                        total_files = excluded.total_files, matching_files = excluded.matching_files
                    WHERE excluded.checked_at >= integrity_check.checked_at
                    """, arguments: [sessionID.uuidString, date.timeIntervalSince1970, result.totalFiles, result.matchingFiles])
            }
        } catch { throw Self.failure(error) }
    }

    public func backupHealth() async throws -> [BackupHealthEntry] {
        do {
            return try await database.read { db in
                try Row.fetchAll(db, sql: """
                    WITH ranked AS (
                        SELECT *, ROW_NUMBER() OVER (
                            PARTITION BY device_key, destination_id ORDER BY started_at DESC, id DESC
                        ) AS position FROM backup_session
                    )
                    SELECT s.*, c.checked_at, c.total_files, c.matching_files,
                        (SELECT MAX(finished_at) FROM backup_session done WHERE done.device_key = s.device_key
                            AND done.destination_id = s.destination_id AND done.status = 'completed'
                            AND done.total_assets > 0 AND done.completed_assets = done.total_assets
                            AND done.verified_resources = done.total_resources) AS last_completed
                    FROM ranked s LEFT JOIN integrity_check c ON c.session_id = s.id
                    WHERE position = 1 ORDER BY s.device_name COLLATE NOCASE, s.started_at DESC
                    """).map { row in
                        let checkedAt: Double? = row["checked_at"]
                        let completed: Double? = row["last_completed"]
                        return BackupHealthEntry(
                            deviceKey: row["device_key"], latestSession: try BackupStoreReading.session(row),
                            lastCompletedAt: completed.map(Date.init(timeIntervalSince1970:)),
                            integrityCheck: checkedAt.map {
                                StoredIntegrityCheck(checkedAt: Date(timeIntervalSince1970: $0),
                                                     totalFiles: row["total_files"], matchingFiles: row["matching_files"])
                            }
                        )
                    }
            }
        } catch { throw Self.failure(error) }
    }
}
