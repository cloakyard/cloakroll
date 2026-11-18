import Darwin
import Foundation

public enum SavedOriginalAccess {
    /// Validate the original folder and every child without following symlinks. This is a
    /// read-access check, not an integrity check. The caller must retain its folder lease.
    public static func url(destination: URL, record: VerifiedBackupResource) async throws -> URL {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let root = try BackupDescriptor(open(destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
            let rootStatus = try root.status()
            guard "\(rootStatus.st_dev):\(rootStatus.st_ino)" == record.destinationIdentity else {
                throw SavedBackupCheckError.differentFolder
            }
            let file = try BackupReadOnlyFiles.namedFile(root: root, relativePath: record.relativePath)
            let status = try file.status()
            guard status.st_mode & S_IFMT == S_IFREG else { throw BackupFileError.unsafePath }
            guard status.st_size == record.byteCount else { throw BackupFileError.sizeMismatch }
            try Task.checkCancellation()
            return destination.appendingPathComponent(record.relativePath)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
