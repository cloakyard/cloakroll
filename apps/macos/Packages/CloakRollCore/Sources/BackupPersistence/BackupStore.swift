import BackupEngine
import Foundation
import GRDB
import MediaModels

/// One application-owned store. SQLite work runs on GRDB's queue, never the UI actor.
public actor BackupStore {
    let database: DatabaseQueue

    public init(databaseURL: URL) async throws {
        do {
            database = try await Task.detached(priority: .utility) {
                try BackupStoreSchema.open(databaseURL)
            }.value
        } catch { throw Self.failure(error) }
    }

    public func beginSession(
        device: ConnectedDevice, destinationID: UUID, sourceSessionID: UUID,
        assets: [MediaAsset], identity: BackupCatalogIdentity
    ) async throws -> UUID {
        do {
            let registration = try BackupRegistration(
                device: device, sourceSessionID: sourceSessionID, assets: assets, identity: identity
            )
            let id = UUID()
            try await database.write { db in
                try BackupStoreWriting.begin(db, id: id, destinationID: destinationID, registration: registration)
            }
            return id
        } catch { throw Self.failure(error) }
    }

    /// Invoke after local finalization and await this transaction before completing its asset.
    public func recordVerified(sessionID: UUID, record: VerifiedBackupResource) async throws {
        do {
            try await database.write { db in
                try BackupStoreJournal.validatePublication(db, sessionID: sessionID, record: record)
                try BackupStoreWriting.record(db, sessionID: sessionID, record: record)
                try BackupStoreJournal.resolve(db, sessionID: sessionID, resourceID: record.resourceID)
            }
        } catch { throw Self.failure(error) }
    }

    /// Persist owned staging before the source download starts.
    public func recordStaging(sessionID: UUID, intent: BackupStagingIntent) async throws {
        do {
            try await database.write { db in try BackupStoreJournal.stage(db, sessionID: sessionID, intent: intent) }
        } catch { throw Self.failure(error) }
    }

    /// Persist verified source-file identity and the exact proposed path before each exclusive rename.
    public func recordPublication(sessionID: UUID, intent: BackupPublicationIntent) async throws {
        do {
            try await database.write { db in try BackupStoreJournal.publish(db, sessionID: sessionID, intent: intent) }
        } catch { throw Self.failure(error) }
    }

    /// Excludes running sessions. The caller must retain destination access throughout local inspection.
    public func pendingJournal(destinationID: UUID) async throws -> [StoredBackupJournalEntry] {
        do {
            return try await database.read { db in try BackupStoreJournal.pending(db, destinationID: destinationID) }
        } catch { throw Self.failure(error) }
    }

    /// Call only with fresh BackupRecovery evidence for this exact saved intent. This does not
    /// turn a failed, cancelled or interrupted session into a completed session.
    public func reconcilePublication(
        sessionID: UUID, intent: BackupPublicationIntent, record: VerifiedBackupResource
    ) async throws {
        do {
            try await database.write { db in
                try BackupStoreJournal.reconcile(db, sessionID: sessionID, intent: intent, record: record)
            }
        } catch { throw Self.failure(error) }
    }

    public func finishSession(id: UUID, result: BackupSnapshot) async throws {
        do {
            try await database.write { db in try BackupStoreWriting.finish(db, id: id, result: result) }
        } catch { throw Self.failure(error) }
    }

    public func candidates(
        deviceKey: String, destinationID: UUID, identity: BackupCatalogIdentity
    ) async throws -> [StoredBackupCandidate] {
        guard deviceKey == identity.deviceKey else { throw BackupStoreError.invalidIdentity }
        do {
            return try await database.read { db in
                try BackupStoreReading.candidates(db, deviceKey: deviceKey, destinationID: destinationID, identity: identity)
            }
        } catch { throw Self.failure(error) }
    }

    public func recentSessions(limit: Int = 20, filter: BackupHistoryFilter = .init()) async throws -> [StoredBackupSession] {
        do {
            return try await database.read { db in
                try BackupStoreReading.sessions(db, limit: min(200, max(0, limit)), filter: filter)
            }
        } catch { throw Self.failure(error) }
    }

    /// A bounded page using a stable date/ID boundary, independent of newly inserted sessions.
    public func sessionPage(
        limit: Int = 100, filter: BackupHistoryFilter = .init(), after cursor: BackupHistoryCursor? = nil
    ) async throws -> BackupHistoryPage {
        guard cursor == nil || cursor?.filter == filter else { throw BackupStoreError.invalidRecord }
        do {
            return try await database.read { db in
                try BackupStoreReading.sessionPage(db, limit: min(200, max(1, limit)), filter: filter, after: cursor)
            }
        } catch { throw Self.failure(error) }
    }

    /// The latest successfully finished backup for this exact device, across destinations.
    /// Recovery scans and unfinished attempts do not establish an original backup date.
    public func lastCompletedSession(deviceKey: String) async throws -> StoredBackupSession? {
        do {
            return try await database.read { db in
                try Row.fetchOne(db, sql: """
                    SELECT * FROM backup_session
                    WHERE device_key = ? AND status = 'completed' AND finished_at IS NOT NULL
                        AND total_assets > 0 AND completed_assets = total_assets AND verified_resources = total_resources
                    ORDER BY finished_at DESC, id DESC LIMIT 1
                    """, arguments: [deviceKey]).map(BackupStoreReading.session)
            }
        } catch { throw Self.failure(error) }
    }

    /// Reads only committed originals from one settled session and its exact destination.
    /// Reading does not promote partial backups or reconcile pending publication journals.
    public func savedFiles(sessionID: UUID, destinationID: UUID) async throws -> [VerifiedBackupResource] {
        do {
            return try await database.read { db in
                guard let session = try Row.fetchOne(db, sql: "SELECT * FROM backup_session WHERE id = ? AND destination_id = ?",
                                                    arguments: [sessionID.uuidString, destinationID.uuidString]),
                      let status = StoredBackupSessionStatus(rawValue: session["status"]), status != .running else {
                    throw BackupStoreError.unknownSession
                }
                let records = try Row.fetchAll(db, sql: """
                    SELECT * FROM backup_record WHERE session_id = ? AND destination_id = ? ORDER BY id
                    """, arguments: [sessionID.uuidString, destinationID.uuidString]).map(BackupStoreReading.record)
                guard records.count == session["verified_resources"] as Int else { throw BackupStoreError.invalidRecord }
                return records
            }
        } catch { throw Self.failure(error) }
    }

    public func historyDevices() async throws -> [BackupHistoryDevice] {
        do {
            return try await database.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT device_key, display_name FROM device d
                    WHERE EXISTS (SELECT 1 FROM backup_session s WHERE s.device_key = d.device_key)
                    ORDER BY display_name COLLATE NOCASE, device_key
                    """).map { BackupHistoryDevice(id: $0["device_key"], name: $0["display_name"]) }
            }
        } catch { throw Self.failure(error) }
    }

    static func failure(_ error: Error) -> Error {
        if let error = error as? BackupStoreError { return error }
        if error is CancellationError { return CancellationError() }
        return BackupStoreError.unavailable
    }
}
