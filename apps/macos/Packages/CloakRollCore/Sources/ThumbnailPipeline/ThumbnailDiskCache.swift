import Foundation

/// Owns only a marked schema directory and session namespaces beneath it. Startup and session
/// changes discard session-only entries. Explicit reusable preview identities share one bounded
/// runtime namespace; startup discards every prior runtime namespace.
struct ThumbnailDiskCache {
    private struct Entry {
        let url: URL
        let bytes: Int
        var access: UInt64
    }

    private static let markerData = Data("CloakRoll thumbnail cache schema 1\n".utf8)
    private let directory: URL?
    private let configuration: ThumbnailPipelineConfiguration
    private var root: URL?
    private var sessionDirectory: URL?
    private var didPrepare = false
    private var isUnavailable = false
    private var entries: [ThumbnailKey: Entry] = [:]
    private var clock: UInt64 = 0
    private(set) var bytes = 0
    private(set) var failures = 0
    var count: Int { entries.count }

    init(directory: URL?, configuration: ThumbnailPipelineConfiguration) {
        self.directory = directory
        self.configuration = configuration
    }

    mutating func setSession(_ sessionID: UUID?) {
        guard !isUnavailable else { return }
        prepareRoot()
        if sessionDirectory != nil, !validateNamespace() { return }
        for key in Array(entries.keys) where !key.permitsReuse {
            guard discard(key) else { isUnavailable = true; return }
        }
        // Reusable entries keep this runtime directory even while no device is connected.
        if !entries.isEmpty { return }
        if let sessionDirectory, !removeOwnedItem(sessionDirectory) {
            // Failed eviction cannot be counted as freed space or followed by more writes.
            isUnavailable = true
            self.sessionDirectory = nil
            root = nil
            return
        }
        entries.removeAll()
        bytes = 0
        sessionDirectory = nil
        guard let sessionID, let root else { return }
        let folder = root.appendingPathComponent("s-" + sessionID.uuidString.lowercased(), isDirectory: true)
        do {
            // A reused UUID still starts a new namespace. Never follow a pre-existing link.
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            sessionDirectory = folder
        } catch {
            failures += 1
        }
    }

    mutating func data(for key: ThumbnailKey) -> Data? {
        guard !isUnavailable, sessionDirectory != nil, var entry = entries[key] else { return nil }
        guard validateNamespace() else { return nil }
        do {
            let values = try Self.values(entry.url, keys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == entry.bytes,
                  let encoded = try Self.read(entry.url, maximumBytes: entry.bytes),
                  let payload = ThumbnailDiskCodec.decode(encoded, key: key, maximumDataBytes: configuration.maximumDataBytes) else {
                discard(key)
                return nil
            }
            clock &+= 1
            entry.access = clock
            entries[key] = entry
            return payload
        } catch {
            failures += 1
            discard(key)
            return nil
        }
    }

    mutating func insert(_ data: Data, for key: ThumbnailKey) {
        guard !isUnavailable, let sessionDirectory, configuration.diskItemLimit > 0,
              let filename = ThumbnailDiskCodec.filename(for: key),
              let encoded = ThumbnailDiskCodec.encode(data, key: key), encoded.count <= configuration.diskByteLimit else { return }
        guard validateNamespace() else { return }
        guard discard(key) else { return }
        while entries.count >= configuration.diskItemLimit || bytes > configuration.diskByteLimit - encoded.count {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
            guard discard(oldest) else { return }
        }
        let url = sessionDirectory.appendingPathComponent(filename, isDirectory: false)
        do {
            try encoded.write(to: url, options: [.atomic])
            clock &+= 1
            entries[key] = Entry(url: url, bytes: encoded.count, access: clock)
            bytes += encoded.count
        } catch {
            failures += 1
        }
    }

    private mutating func prepareRoot() {
        guard !didPrepare else { return }
        didPrepare = true
        guard let directory, directory.isFileURL, configuration.diskByteLimit > 0, configuration.diskItemLimit > 0 else { return }
        let candidate = directory.appendingPathComponent("CloakRollThumbnails-v1", isDirectory: true)
        let marker = candidate.appendingPathComponent(".owner", isDirectory: false)
        do {
            if FileManager.default.fileExists(atPath: candidate.path) {
                let values = try Self.values(candidate, keys: [.isDirectoryKey, .isSymbolicLinkKey])
                let markerValues = try Self.values(marker, keys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true,
                      markerValues.isRegularFile == true, markerValues.isSymbolicLink != true,
                      try Self.read(marker, maximumBytes: Self.markerData.count) == Self.markerData else {
                    failures += 1
                    return
                }
            } else {
                try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
                try Self.markerData.write(to: marker, options: [.atomic])
            }
            root = candidate
            let children = try FileManager.default.contentsOfDirectory(at: candidate, includingPropertiesForKeys: nil)
            for child in children where Self.isSessionNamespace(child.lastPathComponent) {
                guard removeOwnedItem(child) else { root = nil; isUnavailable = true; return }
            }
        } catch {
            root = nil
            failures += 1
        }
    }

    private mutating func validateNamespace() -> Bool {
        guard let root, let sessionDirectory else { return false }
        do {
            for folder in [root, sessionDirectory] {
                let values = try Self.values(folder, keys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    failures += 1
                    isUnavailable = true
                    return false
                }
            }
            return true
        } catch {
            failures += 1
            isUnavailable = true
            return false
        }
    }

    @discardableResult
    private mutating func discard(_ key: ThumbnailKey) -> Bool {
        guard let entry = entries[key] else { return true }
        guard removeOwnedItem(entry.url) else { return false }
        entries[key] = nil
        bytes -= entry.bytes
        return true
    }

    @discardableResult
    private mutating func removeOwnedItem(_ url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // An external cleanup already removed this disposable cache entry.
            return true
        } catch {
            failures += 1
            return false
        }
    }

    private static func isSessionNamespace(_ name: String) -> Bool {
        name.hasPrefix("s-") && UUID(uuidString: String(name.dropFirst(2))) != nil
    }

    private static func values(_ url: URL, keys: Set<URLResourceKey>) throws -> URLResourceValues {
        // URL caches resource values. Ownership checks must observe replacements since the last
        // read rather than reusing a cached directory type or file size.
        var fresh = url
        fresh.removeAllCachedResourceValues()
        return try fresh.resourceValues(forKeys: keys)
    }

    /// Bound the read even when a file grows or its size metadata is inaccurate.
    private static func read(_ url: URL, maximumBytes: Int) throws -> Data? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var result = Data()
        while result.count <= maximumBytes {
            let remaining = maximumBytes - result.count + 1
            guard let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)), !chunk.isEmpty else { return result }
            result.append(chunk)
        }
        return nil
    }
}
