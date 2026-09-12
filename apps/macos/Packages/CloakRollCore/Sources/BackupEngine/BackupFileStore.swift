import Darwin
import Foundation

struct StagedOriginal: Sendable {
    let directory: URL
    let filename: String
    let container: String
    let descriptor: BackupDescriptor
}

struct FinalizedOriginal: Sendable {
    let relativePath: String
    let byteCount: Int64
    let sha256: String
}

/// One run owns one private staging directory on the destination volume. Failed cleanup removes
/// no unknown files: empty-directory removal simply fails when unexpected contents are present.
final class BackupFileStore: @unchecked Sendable {
    let destinationIdentity: String
    private let root: BackupDescriptor
    private let staging: BackupDescriptor
    private let stagingName: String
    private let timeZone: TimeZone
    private let markerName = ".owner"

    init(destination: URL, runID: UUID, timeZone: TimeZone) throws {
        guard destination.isFileURL else { throw BackupFileError.unsafePath }
        root = try BackupDescriptor(open(destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        let status = try root.status()
        destinationIdentity = "\(status.st_dev):\(status.st_ino)"
        stagingName = ".cloakroll-staging-" + runID.uuidString.lowercased()
        staging = try root.createDirectory(stagingName)
        self.timeZone = timeZone
        let marker = try BackupDescriptor(openat(staging.value, markerName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600))
        let bytes = Array(("CloakRoll original staging 1\n" + runID.uuidString + "\n").utf8)
        let written = bytes.withUnsafeBytes { Darwin.write(marker.value, $0.baseAddress, $0.count) }
        guard written == bytes.count else { throw BackupFileError.unavailable(errno) }
    }

    func prepare(filename: String) throws -> StagedOriginal {
        try Task.checkCancellation()
        let container = UUID().uuidString.lowercased()
        let descriptor = try staging.createDirectory(container)
        return try StagedOriginal(
            directory: descriptor.path(), filename: BackupPathNaming.filename(filename), container: container, descriptor: descriptor
        )
    }

    func verifyAndFinalize(
        _ staged: StagedOriginal, returnedURL: URL, expectedByteCount: Int64, createdAt: Date?
    ) throws -> FinalizedOriginal {
        try Task.checkCancellation()
        let expectedURL = staged.directory.appendingPathComponent(staged.filename, isDirectory: false)
        guard returnedURL.isFileURL, returnedURL.standardizedFileURL == expectedURL.standardizedFileURL else {
            throw BackupFileError.unexpectedDownload
        }
        let file = try staged.descriptor.file(staged.filename)
        let evidence = try BackupFileEvidence.inspect(file, expectedBytes: expectedByteCount)
        // Surface delayed write errors before publishing verified evidence. This alone is not a
        // claim about a filesystem's behavior under physical power loss.
        guard fsync(file.value) == 0 else { throw BackupFileError.unavailable(errno) }
        let folders = BackupPathNaming.folders(createdAt: createdAt, timeZone: timeZone)
        var destination = root
        for folder in folders { destination = try destination.directory(folder, create: true) }
        try Task.checkCancellation()
        // Verify the source directory name still identifies the exact inode we hashed.
        let named = try staged.descriptor.file(staged.filename)
        guard try evidence.matches(named.status()) else { throw BackupFileError.changedDuringVerification }
        for collision in 0..<10_000 {
            try Task.checkCancellation()
            let current = try staged.descriptor.file(staged.filename)
            guard try evidence.matches(current.status()) else { throw BackupFileError.changedDuringVerification }
            let filename = BackupPathNaming.filename(staged.filename, collision: collision)
            if renameatx_np(staged.descriptor.value, staged.filename, destination.value, filename, UInt32(RENAME_EXCL)) == 0 {
                let published = try destination.file(filename)
                // Rename itself can update ctime. Inode, bytes and content-modification time
                // must still match the exact regular file that was hashed.
                guard try evidence.matches(published.status(), includingChangeTime: false) else {
                    throw BackupFileError.changedDuringVerification
                }
                // Publication is exclusive and same-volume. No process-restart/power-loss durability
                // claim is made here; the digest records verified local bytes for later persistence.
                _ = unlinkat(staging.value, staged.container, AT_REMOVEDIR)
                return FinalizedOriginal(
                    relativePath: (folders + [filename]).joined(separator: "/"), byteCount: evidence.bytes, sha256: evidence.sha256
                )
            }
            guard errno == EEXIST else { throw BackupFileError.unavailable(errno) }
        }
        throw BackupFileError.tooManyCollisions
    }

    func verifyExisting(relativePath: String, expectedByteCount: Int64, sha256: String) throws -> Bool {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, components.allSatisfy(BackupDescriptor.isComponent), let filename = components.last else { return false }
        do {
            var directory = root
            for component in components.dropLast() { directory = try directory.directory(component) }
            let file = try directory.file(filename)
            let evidence = try BackupFileEvidence.inspect(file, expectedBytes: expectedByteCount)
            return evidence.sha256 == sha256
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return false
        }
    }

    func discard(_ staged: StagedOriginal) {
        // The engine calls this only after the source operation has actually settled.
        _ = unlinkat(staged.descriptor.value, staged.filename, 0)
        _ = unlinkat(staging.value, staged.container, AT_REMOVEDIR)
    }

    func closeStaging() {
        _ = unlinkat(staging.value, markerName, 0)
        _ = unlinkat(root.value, stagingName, AT_REMOVEDIR)
    }
}
