import Darwin
import Foundation

/// A destination descriptor for local evidence checks. Opening this reader creates no directories
/// and requires no write access. The caller owns security-scoped access until verification settles.
struct BackupReadOnlyFiles: Sendable {
    let destinationIdentity: String
    private let root: BackupDescriptor

    init(destination: URL) throws {
        guard destination.isFileURL else { throw BackupFileError.unsafePath }
        root = try BackupDescriptor(open(destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        let status = try root.status()
        destinationIdentity = "\(status.st_dev):\(status.st_ino)"
    }

    func verifyExisting(relativePath: String, expectedByteCount: Int64, sha256: String) throws -> Bool {
        try Self.verifyExisting(root: root, relativePath: relativePath, expectedByteCount: expectedByteCount, sha256: sha256)
    }

    static func verifyExisting(root: BackupDescriptor, relativePath: String, expectedByteCount: Int64, sha256: String) throws -> Bool {
        do {
            let file = try namedFile(root: root, relativePath: relativePath)
            let evidence = try BackupFileEvidence.inspect(file, expectedBytes: expectedByteCount)
            // Rewalk every component after hashing: an open descriptor alone must not verify a
            // replaced directory entry or a path now redirected to a different original.
            return evidence.sha256 == sha256 && matches(root: root, relativePath: relativePath, evidence: evidence)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return false
        }
    }

    static func matches(
        root: BackupDescriptor, relativePath: String, evidence: BackupFileEvidence, includingChangeTime: Bool = true
    ) -> Bool {
        do {
            let current = try namedFile(root: root, relativePath: relativePath)
            return try evidence.matches(current.status(), includingChangeTime: includingChangeTime)
        } catch { return false }
    }

    static func namedFile(root: BackupDescriptor, relativePath: String) throws -> BackupDescriptor {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, components.allSatisfy(BackupDescriptor.isComponent), let filename = components.last else {
            throw BackupFileError.unsafePath
        }
        var directory = root
        for component in components.dropLast() { directory = try directory.directory(component) }
        return try directory.file(filename)
    }
}
