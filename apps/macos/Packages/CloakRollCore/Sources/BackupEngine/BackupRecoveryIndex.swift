import Darwin
import Foundation

public struct BackupRecoveryScan: Sendable {
    public let entries: [BackupRecoveryEntry]
    public let checked: Int
    public let unavailable: Int
    public let invalid: Int
    public let ambiguous: Int
    public let destinationIdentity: String
}

/// Descriptor-relative, immutable receipts. Atomic exclusive publication never replaces an
/// unrelated file. Interrupted temporary metadata is ignored; media is always independently hashed.
public enum BackupRecoveryIndex {
    public static let directoryName = ".cloakroll-recovery"
    private static let format = Data("CloakRoll recovery index 1\n".utf8)
    private static let maximumEntries = 200_000
    private static let maximumReceiptBytes = 256 * 1_024

    public static func destinationIdentity(_ destination: URL) throws -> String {
        let status = try openRoot(destination).status()
        return "\(status.st_dev):\(status.st_ino)"
    }

    public static func write(_ entry: BackupRecoveryEntry, destination: URL) throws {
        try entry.validate()
        let root = try openRoot(destination)
        let status = try root.status()
        guard entry.record.destinationIdentity == "\(status.st_dev):\(status.st_ino)" else {
            throw BackupRecoveryError.invalidIndex
        }
        let directory = try indexDirectory(root, create: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(entry)
        guard data.count <= maximumReceiptBytes else { throw BackupRecoveryError.tooLarge }
        let name = entry.key + ".json"
        if try exists(directory, name: name) {
            let existing = try decode(directory, name: name)
            guard existing.key == entry.key else { throw BackupRecoveryError.invalidIndex }
        } else {
            try publish(data, name: name, directory: directory)
            guard try decode(directory, name: name).key == entry.key else { throw BackupRecoveryError.invalidIndex }
        }
        try verifyDirectory(root, directory: directory)
    }

    public static func scan(destination: URL, progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> BackupRecoveryScan {
        let root = try openRoot(destination)
        let status = try root.status()
        let identity = "\(status.st_dev):\(status.st_ino)"
        guard try exists(root, name: directoryName) else {
            return BackupRecoveryScan(entries: [], checked: 0, unavailable: 0, invalid: 0, ambiguous: 0, destinationIdentity: identity)
        }
        let directory = try indexDirectory(root, create: false)
        let names = try directory.entries(limit: maximumEntries + 1).filter { $0.hasSuffix(".json") }.sorted()
        guard names.count <= maximumEntries else { throw BackupRecoveryError.tooLarge }
        var entries: [BackupRecoveryEntry] = []
        var unavailable = 0
        var invalid = 0
        var metadataBytes: Int64 = 0
        for (offset, name) in names.enumerated() {
            try Task.checkCancellation()
            let size = (try? directory.file(name).status().st_size) ?? 0
            let sum = metadataBytes.addingReportingOverflow(max(0, size))
            guard !sum.overflow, sum.partialValue <= 512 * 1_024 * 1_024 else { throw BackupRecoveryError.tooLarge }
            metadataBytes = sum.partialValue
            do {
                let entry = try decode(directory, name: name)
                if try BackupReadOnlyFiles.verifyExisting(root: root, relativePath: entry.record.relativePath,
                                                        expectedByteCount: entry.record.byteCount, sha256: entry.record.sha256) {
                    entries.append(entry)
                } else { unavailable += 1 }
            } catch is CancellationError { throw CancellationError() } catch { invalid += 1 }
            progress(offset + 1, names.count)
        }
        try verifyDirectory(root, directory: directory)
        return resolved(entries, checked: names.count, unavailable: unavailable, invalid: invalid, identity: identity)
    }

    /// Used when app history survives but predates portable receipts. Only records tied to the
    /// actual selected root may be exported; a similarly named or copied folder is insufficient.
    public static func prepare(entries: [BackupRecoveryEntry], destination: URL,
                               progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> Int {
        let files = try BackupReadOnlyFiles(destination: destination)
        var written = 0
        for (offset, entry) in entries.enumerated() {
            try Task.checkCancellation()
            if entry.record.destinationIdentity == files.destinationIdentity,
               try files.verifyExisting(relativePath: entry.record.relativePath, expectedByteCount: entry.record.byteCount,
                                        sha256: entry.record.sha256) {
                try write(entry, destination: destination)
                written += 1
            }
            progress(offset + 1, entries.count)
        }
        return written
    }

    static func resolved(_ entries: [BackupRecoveryEntry], checked: Int, unavailable: Int, invalid: Int,
                         identity: String) -> BackupRecoveryScan {
        let groups = Dictionary(grouping: entries) { [$0.deviceKey, $0.assetDigest, $0.resourceDigest] }
        var accepted: [BackupRecoveryEntry] = []
        var ambiguous = 0
        for group in groups.values {
            let contents = Set(group.map { String($0.record.byteCount) + ":" + $0.record.sha256 })
            guard contents.count == 1 else { ambiguous += group.count; continue }
            if let entry = group.sorted(by: { $0.record.relativePath < $1.record.relativePath }).first { accepted.append(entry) }
        }
        return BackupRecoveryScan(entries: accepted, checked: checked, unavailable: unavailable,
                                  invalid: invalid, ambiguous: ambiguous, destinationIdentity: identity)
    }

    static func openRoot(_ destination: URL) throws -> BackupDescriptor {
        guard destination.isFileURL else { throw BackupFileError.unsafePath }
        return try BackupDescriptor(open(destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
    }

    private static func exists(_ directory: BackupDescriptor, name: String) throws -> Bool {
        var status = stat()
        if fstatat(directory.value, name, &status, AT_SYMLINK_NOFOLLOW) == 0 { return true }
        guard errno == ENOENT else { throw BackupFileError.unavailable(errno) }
        return false
    }

    private static func indexDirectory(_ root: BackupDescriptor, create: Bool) throws -> BackupDescriptor {
        if create, try !exists(root, name: directoryName) {
            let temporaryName = ".cloakroll-recovery-" + UUID().uuidString + ".tmp"
            let temporary = try root.createDirectory(temporaryName)
            try publish(format, name: "FORMAT", directory: temporary)
            if renameatx_np(root.value, temporaryName, root.value, directoryName, UInt32(RENAME_EXCL)) != 0 {
                guard errno == EEXIST else { throw BackupFileError.unavailable(errno) }
                // Preserve a losing temporary directory rather than delete anything whose name
                // could have been replaced by another process. It contains no original media.
            }
            try root.sync()
        }
        let directory = try root.directory(directoryName)
        guard try read(directory, name: "FORMAT", limit: 128) == format else { throw BackupRecoveryError.invalidIndex }
        return directory
    }

    private static func verifyDirectory(_ root: BackupDescriptor, directory: BackupDescriptor) throws {
        let named = try root.directory(directoryName).status()
        let opened = try directory.status()
        guard named.st_dev == opened.st_dev, named.st_ino == opened.st_ino else { throw BackupFileError.changedDuringVerification }
    }

    private static func decode(_ directory: BackupDescriptor, name: String) throws -> BackupRecoveryEntry {
        let data = try read(directory, name: name, limit: maximumReceiptBytes)
        let entry = try JSONDecoder().decode(BackupRecoveryEntry.self, from: data)
        try entry.validate()
        guard name == entry.key + ".json" else { throw BackupRecoveryError.invalidIndex }
        return entry
    }

    private static func read(_ directory: BackupDescriptor, name: String, limit: Int) throws -> Data {
        let file = try directory.file(name)
        let initial = try file.status()
        guard initial.st_size > 0, initial.st_size <= limit else { throw BackupRecoveryError.invalidIndex }
        let evidence = try BackupFileEvidence.inspect(file, expectedBytes: initial.st_size)
        guard lseek(file.value, 0, SEEK_SET) == 0 else { throw BackupFileError.unavailable(errno) }
        var bytes = [UInt8](repeating: 0, count: Int(initial.st_size))
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(file.value, $0.baseAddress!.advanced(by: offset), $0.count - offset) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw BackupRecoveryError.invalidIndex }
            offset += count
        }
        guard BackupReadOnlyFiles.matches(root: directory, relativePath: name, evidence: evidence),
              BackupRecoveryEntry.digest(Data(bytes)) == evidence.sha256 else { throw BackupRecoveryError.invalidIndex }
        return Data(bytes)
    }

    private static func publish(_ data: Data, name: String, directory: BackupDescriptor) throws {
        let temporaryName = UUID().uuidString + ".tmp"
        let file = try BackupDescriptor(openat(directory.value, temporaryName, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600))
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { Darwin.write(file.value, $0.baseAddress!.advanced(by: offset), $0.count - offset) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw BackupFileError.unavailable(errno) }
            offset += count
        }
        try file.sync()
        guard lseek(file.value, 0, SEEK_SET) == 0 else { throw BackupFileError.unavailable(errno) }
        let evidence = try BackupFileEvidence.inspect(file, expectedBytes: Int64(data.count))
        guard BackupReadOnlyFiles.matches(root: directory, relativePath: temporaryName, evidence: evidence) else {
            throw BackupFileError.changedDuringVerification
        }
        if renameatx_np(directory.value, temporaryName, directory.value, name, UInt32(RENAME_EXCL)) != 0 {
            guard errno == EEXIST else { throw BackupFileError.unavailable(errno) }
        }
        try directory.sync()
    }
}
