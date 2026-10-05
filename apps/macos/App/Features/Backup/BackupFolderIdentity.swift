import Darwin
import Foundation

/// Filesystem identity, independent of display paths and mount points. Birth time prevents
/// a deleted folder's reused inode from inheriting its remembered backup namespace.
struct BackupFolderIdentity: Codable, Sendable, Equatable {
    let volumeUUID: String
    let fileNumber: UInt64
    let createdSeconds: Int64
    let createdNanoseconds: Int64

    static func read(_ url: URL) throws -> Self? {
        guard let volume = try url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString else { return nil }
        var status = stat()
        guard url.withUnsafeFileSystemRepresentation({ path in path.map { lstat($0, &status) == 0 } ?? false }),
              (status.st_mode & S_IFMT) == S_IFDIR else { throw BackupDestinationError.unavailable }
        return Self(volumeUUID: volume, fileNumber: UInt64(status.st_ino),
                    createdSeconds: Int64(status.st_birthtimespec.tv_sec), createdNanoseconds: Int64(status.st_birthtimespec.tv_nsec))
    }
}
