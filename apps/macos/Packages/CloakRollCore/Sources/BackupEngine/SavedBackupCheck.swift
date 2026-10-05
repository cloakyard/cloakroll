import Foundation

public struct SavedBackupCheckProgress: Sendable, Equatable {
    public let totalFiles: Int
    public var checkedFiles = 0
    public var matchingFiles = 0
    /// Keep presentation memory bounded even when an entire drive becomes unavailable.
    public var unverifiedPaths: [String] = []
    public var unverifiedFiles: Int { checkedFiles - matchingFiles }

    public init(totalFiles: Int) { self.totalFiles = totalFiles }
}

public enum SavedBackupCheckError: Error, Sendable, Equatable, LocalizedError {
    case invalidRecords, differentFolder

    public var errorDescription: String? {
        switch self {
        case .invalidRecords: "The saved file records couldn’t be checked safely. The original files have not been changed."
        case .differentFolder:
            "This folder no longer matches the folder used for this backup. Select the original backup folder and try again."
        }
    }
}

/// A current, read-only integrity check of recorded destination files. It does not establish
/// source-library completeness, recover missing records or change the historical backup result.
public enum SavedBackupCheck {
    public static func run(
        destination: URL, records: [VerifiedBackupResource],
        progress: @escaping @Sendable (SavedBackupCheckProgress) async -> Void = { _ in }
    ) async throws -> SavedBackupCheckProgress {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            var paths: Set<String> = []
            for record in records {
                try Task.checkCancellation()
                guard paths.insert(record.relativePath).inserted, record.byteCount > 0,
                      record.sha256.count == 64, record.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                    throw SavedBackupCheckError.invalidRecords
                }
            }
            var state = SavedBackupCheckProgress(totalFiles: records.count)
            await progress(state)
            guard !records.isEmpty else { try Task.checkCancellation(); return state }
            let files = try BackupReadOnlyFiles(destination: destination)
            guard records.allSatisfy({ $0.destinationIdentity == files.destinationIdentity }) else {
                throw SavedBackupCheckError.differentFolder
            }
            let clock = ContinuousClock()
            var lastUpdate = clock.now
            for record in records {
                try Task.checkCancellation()
                let matches = try files.verifyExisting(
                    relativePath: record.relativePath, expectedByteCount: record.byteCount, sha256: record.sha256
                )
                state.checkedFiles += 1
                if matches { state.matchingFiles += 1 } else if state.unverifiedPaths.count < 100 {
                    state.unverifiedPaths.append(record.relativePath)
                }
                // Small originals can hash far faster than the screen can update.
                if lastUpdate.duration(to: clock.now) >= .milliseconds(100) || state.checkedFiles == state.totalFiles {
                    try Task.checkCancellation()
                    await progress(state)
                    lastUpdate = clock.now
                }
            }
            try Task.checkCancellation()
            return state
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
