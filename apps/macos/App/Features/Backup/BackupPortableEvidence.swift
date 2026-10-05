import BackupEngine
import BackupPersistence
import Foundation

/// Persist alongside the media before success is announced in the app's database.
enum BackupPortableEvidence {
    static func save(store: BackupStore, sessionID: UUID, record: VerifiedBackupResource, destination: URL) async throws {
        let entry = try await store.recoveryEntry(sessionID: sessionID, record: record)
        try await Task.detached(priority: .utility) { try BackupRecoveryIndex.write(entry, destination: destination) }.value
    }
}
