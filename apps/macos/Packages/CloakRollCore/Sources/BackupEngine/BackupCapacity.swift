import Foundation

/// Advisory capacity only: other writers, quotas and filesystem overhead can still cause a
/// later write to fail. Unknown capacity must not be mistaken for an empty volume.
struct BackupCapacity: Sendable {
    var availableBytes: @Sendable (URL) throws -> Int64?

    static let live = Self { directory in
        // A fresh URL avoids reusing a cached resource value between original downloads.
        let url = URL(fileURLWithPath: directory.path, isDirectory: true)
        return try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    func check(directory: URL, requiredBytes: Int64) throws {
        try Task.checkCancellation()
        let available = try? availableBytes(directory)
        try Task.checkCancellation()
        guard let available, available >= 0 else { return }
        guard available >= requiredBytes else { throw BackupFileError.insufficientSpace }
    }
}
