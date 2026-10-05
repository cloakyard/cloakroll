import Darwin
import Foundation

struct StagedOriginal: Sendable {
    let directory: URL
    let filename: String
    let container: String
    let descriptor: BackupDescriptor
}

struct VerifiedStagedOriginal: Sendable {
    let staged: StagedOriginal
    let evidence: BackupFileEvidence
    let folders: [String]
    let verifiedAt: Date
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
    let stagingName: String
    private let timeZone: TimeZone
    private let folderPrefix: [String]
    private let usesDateFolders: Bool
    private let markerName = ".owner"
    private let markerBytes: [UInt8]
    private let markerEvidence: BackupFileEvidence

    init(
        destination: URL, runID: UUID, timeZone: TimeZone, folderPrefix: [String] = [], usesDateFolders: Bool = true
    ) throws {
        guard destination.isFileURL, folderPrefix.allSatisfy(BackupDescriptor.isComponent) else { throw BackupFileError.unsafePath }
        root = try BackupDescriptor(open(destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        let status = try root.status()
        destinationIdentity = "\(status.st_dev):\(status.st_ino)"
        stagingName = ".cloakroll-staging-" + runID.uuidString.lowercased()
        staging = try root.createDirectory(stagingName)
        self.timeZone = timeZone
        self.folderPrefix = folderPrefix
        self.usesDateFolders = usesDateFolders
        let marker = try BackupDescriptor(openat(staging.value, markerName, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600))
        let bytes = Array(("CloakRoll original staging 1\n" + runID.uuidString + "\n").utf8)
        markerBytes = bytes
        let written = bytes.withUnsafeBytes { Darwin.write(marker.value, $0.baseAddress, $0.count) }
        guard written == bytes.count else { throw BackupFileError.unavailable(errno) }
        guard lseek(marker.value, 0, SEEK_SET) == 0 else { throw BackupFileError.unavailable(errno) }
        markerEvidence = try BackupFileEvidence.inspect(marker, expectedBytes: Int64(bytes.count))
        try marker.sync()
        try staging.sync()
        try root.sync()
    }

    func prepare(filename: String) throws -> StagedOriginal {
        try Task.checkCancellation()
        let container = UUID().uuidString.lowercased()
        let descriptor = try staging.createDirectory(container)
        try descriptor.sync()
        try staging.sync()
        return try StagedOriginal(
            directory: descriptor.path(), filename: BackupPathNaming.filename(filename), container: container, descriptor: descriptor
        )
    }

    func checkCapacity(for byteCount: Int64, using capacity: BackupCapacity) throws {
        // Resolve the owned directory descriptor, rather than a stale display/bookmark path.
        try capacity.check(directory: root.path(), requiredBytes: byteCount)
    }

    func verifyAndFinalize(
        _ staged: StagedOriginal, returnedURL: URL, expectedByteCount: Int64, createdAt: Date?,
        afterPublication: @Sendable () throws -> Void = {}
    ) throws -> FinalizedOriginal {
        let verified = try verifyStaged(staged, returnedURL: returnedURL, expectedByteCount: expectedByteCount, createdAt: createdAt)
        for collision in 0..<10_000 {
            let filename = BackupPathNaming.filename(staged.filename, collision: collision)
            if let result = try publish(verified, filename: filename, afterPublication: afterPublication) { return result }
        }
        throw BackupFileError.tooManyCollisions
    }

    func verifyStaged(
        _ staged: StagedOriginal, returnedURL: URL, expectedByteCount: Int64, createdAt: Date?
    ) throws -> VerifiedStagedOriginal {
        try Task.checkCancellation()
        let expectedURL = staged.directory.appendingPathComponent(staged.filename, isDirectory: false)
        guard returnedURL.isFileURL, returnedURL.standardizedFileURL == expectedURL.standardizedFileURL else {
            throw BackupFileError.unexpectedDownload
        }
        let file = try staged.descriptor.file(staged.filename)
        let evidence = try BackupFileEvidence.inspect(file, expectedBytes: expectedByteCount)
        try file.sync()
        try staged.descriptor.sync()
        let folders = folderPrefix + (usesDateFolders ? BackupPathNaming.folders(createdAt: createdAt, timeZone: timeZone) : [])
        var destination = root
        for folder in folders {
            let child = try destination.directory(folder, create: true)
            try destination.sync()
            destination = child
        }
        try destination.sync()
        return VerifiedStagedOriginal(staged: staged, evidence: evidence, folders: folders, verifiedAt: Date())
    }

    func relativePath(_ staged: StagedOriginal) -> String {
        [stagingName, staged.container, staged.filename].joined(separator: "/")
    }

    func publication(_ verified: VerifiedStagedOriginal, staging intent: BackupStagingIntent, collision: Int) -> BackupPublicationIntent {
        let filename = BackupPathNaming.filename(verified.staged.filename, collision: collision)
        return BackupPublicationIntent(
            staging: intent, relativePath: (verified.folders + [filename]).joined(separator: "/"),
            byteCount: verified.evidence.bytes, sha256: verified.evidence.sha256,
            verifiedAt: verified.verifiedAt, fileIdentity: verified.evidence.identity
        )
    }

    /// Called only after the complete candidate intent has been durably recorded. Fresh evidence
    /// across that await protects against both same-inode mutation and path replacement.
    func publish(
        _ verified: VerifiedStagedOriginal, filename: String,
        afterPublication: @Sendable () throws -> Void = {}
    ) throws -> FinalizedOriginal? {
        try Task.checkCancellation()
        let staged = verified.staged
        let evidence = verified.evidence
        let current = try staged.descriptor.file(staged.filename)
        guard try evidence.matches(current.status()), BackupReadOnlyFiles.matches(
            root: root, relativePath: relativePath(staged), evidence: evidence
        ) else { throw BackupFileError.changedDuringVerification }
        var destination = root
        for folder in verified.folders { destination = try destination.directory(folder) }
        if renameatx_np(staged.descriptor.value, staged.filename, destination.value, filename, UInt32(RENAME_EXCL)) != 0 {
            guard errno == EEXIST else { throw BackupFileError.unavailable(errno) }
            return nil
        }
        try afterPublication()
        let published = try destination.file(filename)
        let relativePath = (verified.folders + [filename]).joined(separator: "/")
        guard try evidence.matches(published.status(), includingChangeTime: false), BackupReadOnlyFiles.matches(
            root: root, relativePath: relativePath, evidence: evidence, includingChangeTime: false
        ) else { throw BackupFileError.changedDuringVerification }
        try published.sync()
        try destination.sync()
        try staged.descriptor.sync()
        _ = unlinkat(staging.value, staged.container, AT_REMOVEDIR)
        try staging.sync()
        return FinalizedOriginal(relativePath: relativePath, byteCount: evidence.bytes, sha256: evidence.sha256)
    }

    func verifyExisting(relativePath: String, expectedByteCount: Int64, sha256: String) throws -> Bool {
        try BackupReadOnlyFiles.verifyExisting(root: root, relativePath: relativePath, expectedByteCount: expectedByteCount, sha256: sha256)
    }

    /// A completed USB comparison may discard only its own freshly verified temporary copy.
    func discardVerified(_ verified: VerifiedStagedOriginal) throws {
        let staged = verified.staged
        guard BackupReadOnlyFiles.matches(root: root, relativePath: relativePath(staged), evidence: verified.evidence),
              try verified.evidence.matches(staged.descriptor.file(staged.filename).status()) else {
            throw BackupFileError.changedDuringVerification
        }
        guard unlinkat(staged.descriptor.value, staged.filename, 0) == 0 else { throw BackupFileError.unavailable(errno) }
        try staged.descriptor.sync()
        _ = unlinkat(staging.value, staged.container, AT_REMOVEDIR)
        try staging.sync()
    }

    func discard(_ staged: StagedOriginal) {
        // No filename-only deletion: an unverified source failure can leave partial bytes, or
        // another process can replace that name. Preserve such files with the ownership marker.
        _ = unlinkat(staging.value, staged.container, AT_REMOVEDIR)
    }

    func closeStaging() {
        // Retain the marker whenever any private container or unexpected content survives.
        guard (try? staging.entries()) == [markerName],
              let named = try? root.directory(stagingName),
              let original = try? staging.status(), let current = try? named.status(),
              original.st_dev == current.st_dev, original.st_ino == current.st_ino,
              let marker = try? staging.file(markerName), let markerStatus = try? marker.status(),
              markerEvidence.matches(markerStatus), unlinkat(staging.value, markerName, 0) == 0 else { return }
        guard unlinkat(root.value, stagingName, AT_REMOVEDIR) != 0 else { return }
        // If unexpected content arrived after enumeration, restore the ownership marker without
        // replacing any newly created marker. Surviving unknown artifacts are never removed.
        guard let restored = try? BackupDescriptor(openat(
            staging.value, markerName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600
        )) else { return }
        _ = markerBytes.withUnsafeBytes { Darwin.write(restored.value, $0.baseAddress, $0.count) }
        try? restored.sync()
        try? staging.sync()
    }
}
