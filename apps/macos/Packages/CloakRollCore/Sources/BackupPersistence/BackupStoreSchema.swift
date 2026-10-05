import Foundation
import GRDB

enum BackupStoreSchema {
    static func open(_ url: URL) throws -> DatabaseQueue {
        guard url.isFileURL else { throw BackupStoreError.unavailable }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values?.isSymbolicLink != true, values?.isDirectory != true else { throw BackupStoreError.unavailable }
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in try db.execute(sql: "PRAGMA synchronous = FULL") }
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        var migrator = DatabaseMigrator()
        // Append migrations after this baseline; never erase data when a schema changes.
        migrator.registerMigration("v1_original_backup_history", migrate: createBaseline)
        migrator.registerMigration("v2_publication_journal", migrate: createJournal)
        migrator.registerMigration("v3_session_asset_lookup") { db in
            // Completion checks concern one logical asset, not every resource in a large run.
            try db.execute(sql: "CREATE INDEX session_resource_asset_lookup ON session_resource(session_id, runtime_asset_id)")
        }
        migrator.registerMigration("v4_folder_recovery") { db in
            try db.execute(sql: """
                CREATE TABLE recovery_import (
                    destination_id TEXT NOT NULL REFERENCES destination(id),
                    destination_identity TEXT NOT NULL, entry_key TEXT NOT NULL,
                    PRIMARY KEY(destination_id, destination_identity, entry_key));
                """)
        }
        try migrator.migrate(queue)
        try queue.write { db in
            try db.execute(
                sql: "UPDATE backup_session SET status = 'interrupted', finished_at = ? WHERE status = 'running'",
                arguments: [Date().timeIntervalSince1970]
            )
        }
        return queue
    }

    private static func createJournal(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE backup_journal (
                id TEXT PRIMARY KEY NOT NULL, session_id TEXT NOT NULL,
                runtime_resource_id TEXT NOT NULL, staging_payload BLOB NOT NULL,
                publication_payload BLOB, created_at DOUBLE NOT NULL, resolved_at DOUBLE,
                UNIQUE(session_id, runtime_resource_id),
                FOREIGN KEY(session_id, runtime_resource_id)
                    REFERENCES session_resource(session_id, runtime_resource_id));
            CREATE INDEX journal_pending ON backup_journal(session_id, resolved_at);
            """)
    }

    private static func createBaseline(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE device (
                device_key TEXT PRIMARY KEY NOT NULL, display_name TEXT NOT NULL,
                persistent INTEGER NOT NULL, first_seen DOUBLE NOT NULL, last_seen DOUBLE NOT NULL);
            CREATE TABLE destination (id TEXT PRIMARY KEY NOT NULL, created_at DOUBLE NOT NULL);
            CREATE TABLE asset (
                id INTEGER PRIMARY KEY, device_key TEXT NOT NULL REFERENCES device(device_key),
                canonical TEXT NOT NULL, digest TEXT NOT NULL, reusable INTEGER NOT NULL,
                UNIQUE(device_key, canonical));
            CREATE INDEX asset_lookup ON asset(device_key, digest);
            CREATE TABLE resource (
                id INTEGER PRIMARY KEY, asset_id INTEGER NOT NULL REFERENCES asset(id),
                canonical TEXT NOT NULL, digest TEXT NOT NULL, reusable INTEGER NOT NULL,
                filename TEXT NOT NULL, expected_bytes INTEGER NOT NULL CHECK(expected_bytes > 0),
                UNIQUE(asset_id, canonical));
            CREATE INDEX resource_lookup ON resource(asset_id, digest);
            CREATE TABLE backup_session (
                id TEXT PRIMARY KEY NOT NULL, device_key TEXT NOT NULL REFERENCES device(device_key),
                device_name TEXT NOT NULL, destination_id TEXT NOT NULL REFERENCES destination(id),
                source_session_id TEXT NOT NULL, status TEXT NOT NULL,
                started_at DOUBLE NOT NULL, finished_at DOUBLE,
                total_assets INTEGER NOT NULL, total_resources INTEGER NOT NULL,
                expected_bytes INTEGER NOT NULL, completed_assets INTEGER NOT NULL DEFAULT 0,
                verified_resources INTEGER NOT NULL DEFAULT 0, verified_bytes INTEGER NOT NULL DEFAULT 0,
                transferred_bytes INTEGER NOT NULL DEFAULT 0);
            CREATE INDEX session_recent ON backup_session(started_at DESC);
            CREATE TABLE session_resource (
                session_id TEXT NOT NULL REFERENCES backup_session(id),
                resource_id INTEGER NOT NULL REFERENCES resource(id), runtime_asset_id TEXT NOT NULL,
                runtime_resource_id TEXT NOT NULL, source_signature TEXT NOT NULL,
                PRIMARY KEY(session_id, runtime_resource_id));
            CREATE TABLE backup_record (
                id INTEGER PRIMARY KEY, session_id TEXT NOT NULL REFERENCES backup_session(id),
                resource_id INTEGER NOT NULL REFERENCES resource(id),
                destination_id TEXT NOT NULL REFERENCES destination(id), device_id TEXT NOT NULL,
                source_session_id TEXT NOT NULL, runtime_asset_id TEXT NOT NULL, runtime_resource_id TEXT NOT NULL,
                filename TEXT NOT NULL, relative_path TEXT NOT NULL, byte_count INTEGER NOT NULL CHECK(byte_count > 0),
                sha256 TEXT NOT NULL, verified_at DOUBLE NOT NULL, source_modified_at DOUBLE,
                destination_identity TEXT NOT NULL, source_signature TEXT NOT NULL,
                verification_method TEXT NOT NULL DEFAULT 'exact-size-local-sha256',
                UNIQUE(session_id, runtime_resource_id));
            CREATE INDEX record_destination ON backup_record(destination_id, resource_id);
            """
        )
    }
}
