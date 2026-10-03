import BackupEngine
import BackupPersistence
import Foundation
import MediaModels
import SQLite3
import Testing
@testable import CloakRoll

@MainActor
final class RecoveryLibraryFixture {
    let library: PersistentLibraryFixture
    let source = RecoveryOriginalSource()

    init() throws { library = try PersistentLibraryFixture() }

    /// A real temporary original is finalized, but its record transaction never begins.
    /// Leaving the session running models process loss before the terminal session update.
    func publishWithoutRecord(_ catalog: PersistentLibraryCatalog) async throws -> BackupPublicationIntent {
        try await library.accept(catalog)
        let context = try await LibraryBackupPersistence.prepare(
            source: catalog.source, assets: [catalog.asset], device: catalog.device
        )
        let destinationID = try #require(library.controller.destination.selection?.id)
        let store = try await library.persistence.store()
        let id = try await store.beginSession(
            device: catalog.device, destinationID: destinationID, sourceSessionID: catalog.source.sessionID,
            assets: [catalog.asset], identity: context.identity
        )
        let databaseURL = library.databaseURL
        let source = source
        let result = try await BackupEngine().run(
            assets: [catalog.asset], sessionID: catalog.source.sessionID, destination: library.destinationFixture.folder,
            onStaged: { try await store.recordStaging(sessionID: id, intent: $0) },
            onPublication: { try await store.recordPublication(sessionID: id, intent: $0) },
            onVerified: { record in
                let journal = try RecoveryJournalReader.read(databaseURL, resourceID: record.resourceID)
                #expect(journal.publication?.verifiedRecord == record)
                #expect(!journal.isResolved)
                throw RecoveryFixtureError.recordWriteFailed
            }, download: { request, _ in try await source.copy(request) }
        )
        #expect(result.snapshot.phase == .failed)
        #expect(result.snapshot.completedAssetIDs.isEmpty)
        #expect(result.records.count == 1)
        #expect(try await library.candidates(catalog).isEmpty)
        let journal = try RecoveryJournalReader.read(databaseURL, resourceID: catalog.asset.resources[0].id)
        return try #require(journal.publication)
    }

    func reopen() -> (LibraryBackupPersistence, LibraryBackupController) {
        let persistence = LibraryBackupPersistence(databaseURL: library.databaseURL)
        return (persistence, LibraryBackupController(destination: library.controller.destination, persistence: persistence))
    }
}

actor RecoveryOriginalSource {
    private(set) var calls = 0

    func copy(_ request: BackupDownloadRequest) throws -> DownloadedOriginal {
        calls += 1
        return try writePersistentOriginal(request, byte: 1)
    }
}

/// A separate read-only SQLite connection observes committed hook evidence while the session
/// is running. Opening another BackupStore here would incorrectly simulate an app restart.
enum RecoveryJournalReader {
    struct Entry: Sendable {
        let staging: BackupStagingIntent
        let publication: BackupPublicationIntent?
        let isResolved: Bool
    }

    static func read(_ url: URL, resourceID: String) throws -> Entry {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw RecoveryFixtureError.databaseReadFailed
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        let sql = """
            SELECT staging_payload, publication_payload, resolved_at FROM backup_journal
            WHERE runtime_resource_id = ? ORDER BY created_at DESC LIMIT 1
            """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw RecoveryFixtureError.databaseReadFailed
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, resourceID, -1, transient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { throw RecoveryFixtureError.databaseReadFailed }
        let staging = try JSONDecoder().decode(BackupStagingIntent.self, from: blob(statement, column: 0))
        let publication = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil
            : try JSONDecoder().decode(BackupPublicationIntent.self, from: blob(statement, column: 1))
        return Entry(staging: staging, publication: publication, isResolved: sqlite3_column_type(statement, 2) != SQLITE_NULL)
    }

    private static func blob(_ statement: OpaquePointer?, column: Int32) throws -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else { throw RecoveryFixtureError.databaseReadFailed }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
}

enum RecoveryFixtureError: Error { case recordWriteFailed, databaseReadFailed }

enum RecoveryOriginalMutation: String, CaseIterable, Sendable {
    case sameSizeBytes, identicalReplacement

    func apply(to url: URL) throws {
        switch self {
        case .sameSizeBytes:
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.write(contentsOf: Data([9, 9, 9]))
            try handle.synchronize()
        case .identicalReplacement:
            let replacement = url.appendingPathExtension("replacement")
            try Data(contentsOf: url).write(to: replacement, options: [.withoutOverwriting])
            // Keep the original inode allocated so the replacement cannot reuse its identity.
            try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("preserved"))
            try FileManager.default.moveItem(at: replacement, to: url)
        }
    }
}
