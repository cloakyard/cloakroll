import BackupEngine
import Foundation
import GRDB
import MediaModels

/// One application-owned store. SQLite work runs on GRDB's queue, never the UI actor.
public actor BackupStore {
    private let database: DatabaseQueue

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
                try BackupStoreWriting.record(db, sessionID: sessionID, record: record)
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

    public func recentSessions(limit: Int = 20) async throws -> [StoredBackupSession] {
        do {
            return try await database.read { db in
                try BackupStoreReading.sessions(db, limit: min(200, max(0, limit)))
            }
        } catch { throw Self.failure(error) }
    }

    private static func failure(_ error: Error) -> Error {
        if let error = error as? BackupStoreError { return error }
        if error is CancellationError { return CancellationError() }
        return BackupStoreError.unavailable
    }
}
