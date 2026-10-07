import Foundation

/// An opaque position in one filtered history. Keep the database timestamp unchanged:
/// converting through Date can round older timestamps and repeat a boundary row.
public struct BackupHistoryCursor: Sendable, Equatable {
    let startedAt: Double
    let id: String
    let filter: BackupHistoryFilter
}

public struct BackupHistoryPage: Sendable, Equatable {
    public let sessions: [StoredBackupSession]
    public let nextCursor: BackupHistoryCursor?

    public init(sessions: [StoredBackupSession], nextCursor: BackupHistoryCursor? = nil) {
        self.sessions = sessions
        self.nextCursor = nextCursor
    }
}
