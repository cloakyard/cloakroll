import CryptoKit
import Darwin
import Foundation

enum BackupFileError: Error, Equatable, Sendable {
    case unsafePath
    case unavailable(Int32)
    case unexpectedDownload
    case invalidFile
    case sizeMismatch
    case changedDuringVerification
    case tooManyCollisions
}

extension BackupFileError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsafePath: "The backup path contains an unsafe or unavailable folder."
        case .unavailable(let code):
            switch code {
            case ENOSPC, EDQUOT: "The backup drive is full. Free some space or choose another folder, then try again."
            case EROFS: "The backup drive is read-only. Choose a writable folder, then try again."
            case EACCES, EPERM: "CloakRoll can’t access the backup folder. Choose the folder again, then try again."
            case ENOENT, ENODEV, ENXIO, ESTALE: "The backup drive or folder is unavailable. Reconnect the drive or choose the folder again."
            default: "The backup drive couldn’t complete the file operation. Check the drive and try again."
            }
        case .unexpectedDownload: "The iPhone returned an unexpected download location."
        case .invalidFile: "The downloaded original is not a regular file."
        case .sizeMismatch: "The downloaded original does not match its expected size."
        case .changedDuringVerification: "The original changed while it was being verified."
        case .tooManyCollisions: "A unique filename could not be created in the backup folder."
        }
    }
}

/// Immutable descriptor ownership. Operations use descriptor-relative names rather than walking
/// user-controlled child paths. Each store is used sequentially by one backup workflow.
final class BackupDescriptor: @unchecked Sendable {
    let value: Int32

    init(_ value: Int32) throws {
        guard value >= 0 else { throw BackupFileError.unavailable(errno) }
        self.value = value
    }

    deinit { Darwin.close(value) }

    func directory(_ name: String, create: Bool = false, permissions: mode_t = 0o755) throws -> BackupDescriptor {
        guard Self.isComponent(name) else { throw BackupFileError.unsafePath }
        if create, mkdirat(value, name, permissions) != 0, errno != EEXIST { throw BackupFileError.unavailable(errno) }
        return try BackupDescriptor(openat(value, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
    }

    func createDirectory(_ name: String) throws -> BackupDescriptor {
        guard Self.isComponent(name), mkdirat(value, name, 0o700) == 0 else { throw BackupFileError.unavailable(errno) }
        return try directory(name)
    }

    func file(_ name: String) throws -> BackupDescriptor {
        guard Self.isComponent(name) else { throw BackupFileError.unsafePath }
        // O_NONBLOCK prevents a malicious FIFO from suspending verification before fstat rejects it.
        return try BackupDescriptor(openat(value, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC))
    }

    func status() throws -> stat {
        var result = stat()
        guard fstat(value, &result) == 0 else { throw BackupFileError.unavailable(errno) }
        return result
    }

    func sync() throws {
        guard fsync(value) == 0 else { throw BackupFileError.unavailable(errno) }
    }

    func entries() throws -> Set<String> {
        let copied = openat(value, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copied >= 0 else { throw BackupFileError.unavailable(errno) }
        guard let directory = fdopendir(copied) else {
            Darwin.close(copied)
            throw BackupFileError.unavailable(errno)
        }
        defer { closedir(directory) }
        var names: Set<String> = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.insert(name) }
        }
        guard errno == 0 else { throw BackupFileError.unavailable(errno) }
        return names
    }

    func path() throws -> URL {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(value, F_GETPATH, &buffer) == 0 else { throw BackupFileError.unavailable(errno) }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let path = String(bytes: bytes, encoding: .utf8) else { throw BackupFileError.unsafePath }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func isComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.utf8.contains(0)
    }
}

struct BackupFileEvidence: Sendable {
    let bytes: Int64
    let sha256: String
    let device: dev_t
    let inode: ino_t
    let birthSeconds: Int
    let birthNanoseconds: Int
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    func matches(_ status: stat, includingChangeTime: Bool = true) -> Bool {
        (status.st_mode & S_IFMT) == S_IFREG && status.st_nlink == 1 && status.st_size == bytes
            && status.st_dev == device && status.st_ino == inode
            && status.st_birthtimespec.tv_sec == birthSeconds && status.st_birthtimespec.tv_nsec == birthNanoseconds
            && status.st_mtimespec.tv_sec == modifiedSeconds && status.st_mtimespec.tv_nsec == modifiedNanoseconds
            && (!includingChangeTime || (status.st_ctimespec.tv_sec == changedSeconds && status.st_ctimespec.tv_nsec == changedNanoseconds))
    }

    static func inspect(_ file: BackupDescriptor, expectedBytes: Int64) throws -> BackupFileEvidence {
        try Task.checkCancellation()
        let initial = try file.status()
        guard (initial.st_mode & S_IFMT) == S_IFREG, initial.st_nlink == 1 else { throw BackupFileError.invalidFile }
        guard expectedBytes > 0, initial.st_size == expectedBytes else { throw BackupFileError.sizeMismatch }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 256 * 1_024)
        var bytes: Int64 = 0
        while true {
            try Task.checkCancellation()
            let readCount = Darwin.read(file.value, &buffer, buffer.count)
            if readCount < 0 {
                if errno == EINTR { continue }
                throw BackupFileError.unavailable(errno)
            }
            if readCount == 0 { break }
            bytes += Int64(readCount)
            guard bytes <= expectedBytes else { throw BackupFileError.sizeMismatch }
            hasher.update(data: Data(buffer.prefix(readCount)))
        }
        let final = try file.status()
        guard bytes == expectedBytes, final.st_size == initial.st_size else { throw BackupFileError.sizeMismatch }
        guard final.st_ino == initial.st_ino, final.st_dev == initial.st_dev,
              final.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec,
              final.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec,
              final.st_ctimespec.tv_sec == initial.st_ctimespec.tv_sec,
              final.st_ctimespec.tv_nsec == initial.st_ctimespec.tv_nsec else { throw BackupFileError.changedDuringVerification }
        return BackupFileEvidence(
            bytes: bytes, sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
            device: initial.st_dev, inode: initial.st_ino,
            birthSeconds: initial.st_birthtimespec.tv_sec, birthNanoseconds: initial.st_birthtimespec.tv_nsec,
            modifiedSeconds: final.st_mtimespec.tv_sec, modifiedNanoseconds: final.st_mtimespec.tv_nsec,
            changedSeconds: final.st_ctimespec.tv_sec, changedNanoseconds: final.st_ctimespec.tv_nsec
        )
    }

    var identity: BackupFileIdentity {
        BackupFileIdentity(
            device: Int64(device), inode: UInt64(inode), birthSeconds: Int64(birthSeconds), birthNanoseconds: Int64(birthNanoseconds),
            modifiedSeconds: Int64(modifiedSeconds), modifiedNanoseconds: Int64(modifiedNanoseconds),
            changedSeconds: Int64(changedSeconds), changedNanoseconds: Int64(changedNanoseconds)
        )
    }
}
