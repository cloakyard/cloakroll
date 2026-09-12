import Foundation

struct ResolvedBackupBookmark: Sendable {
    let url: URL
    let isStale: Bool
}

/// Synchronous Foundation operations run only in the store's detached worker. These narrow
/// closures also permit deterministic permission, stale-bookmark and volume-failure tests.
struct BackupDestinationOperations: Sendable {
    var resolveBookmark: @Sendable (Data) throws -> ResolvedBackupBookmark
    var makeBookmark: @Sendable (URL) throws -> Data
    var startAccess: @Sendable (URL) -> Bool
    var stopAccess: @Sendable (URL) -> Void
    var requiresSecurityScope: @Sendable (URL) -> Bool
    var validateFolder: @Sendable (URL) throws -> String
    var sameFolder: @Sendable (URL, URL) throws -> Bool

    static let live = Self(
        resolveBookmark: { data in
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                relativeTo: nil, bookmarkDataIsStale: &stale
            )
            return ResolvedBackupBookmark(url: url, isStale: stale)
        },
        makeBookmark: { url in
            try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        },
        startAccess: { $0.startAccessingSecurityScopedResource() },
        stopAccess: { $0.stopAccessingSecurityScopedResource() },
        requiresSecurityScope: { !BackupFolderValidation.isInsideAppContainer($0) },
        validateFolder: BackupFolderValidation.validate,
        sameFolder: BackupFolderValidation.isSameFolder
    )

    func prepareSelection(url: URL, previous: BackupDestination?) throws -> BackupDestination {
        let lease = try open(url, destinationID: previous?.id ?? UUID())
        defer { lease.release() }
        let name = try validateFolder(url)
        let bookmark = try createBookmark(url)
        let identifier = previous.flatMap { matches($0, url: url) ? $0.id : nil } ?? UUID()
        try Task.checkCancellation()
        return BackupDestination(id: identifier, displayName: name, lastKnownPath: url.path, bookmarkData: bookmark)
    }

    func acquire(_ record: BackupDestination) throws -> AcquiredBackupDestination {
        let resolved: ResolvedBackupBookmark
        do { resolved = try resolveBookmark(record.bookmarkData) } catch { throw BackupDestinationError.unavailable }
        let lease = try open(resolved.url, destinationID: record.id)
        do {
            let name = try validateFolder(resolved.url)
            let bookmark = resolved.isStale ? try createBookmark(resolved.url) : record.bookmarkData
            let refreshed = BackupDestination(
                id: record.id, displayName: name, lastKnownPath: resolved.url.path, bookmarkData: bookmark
            )
            try Task.checkCancellation()
            return AcquiredBackupDestination(lease: lease, record: refreshed)
        } catch {
            lease.release()
            throw error
        }
    }

    private func open(_ url: URL, destinationID: UUID) throws -> DestinationLease {
        guard url.isFileURL else { throw BackupDestinationError.notDirectory }
        let started = startAccess(url)
        guard started || !requiresSecurityScope(url) else { throw BackupDestinationError.accessDenied }
        let stop = stopAccess
        let relinquish: (@Sendable () -> Void)?
        if started { relinquish = { stop(url) } } else { relinquish = nil }
        return DestinationLease(url: url, destinationID: destinationID, relinquish: relinquish)
    }

    private func createBookmark(_ url: URL) throws -> Data {
        do {
            let data = try makeBookmark(url)
            guard !data.isEmpty else { throw BackupDestinationError.bookmarkCreationFailed }
            return data
        } catch { throw BackupDestinationError.bookmarkCreationFailed }
    }

    private func matches(_ previous: BackupDestination, url: URL) -> Bool {
        do {
            let resolved = try resolveBookmark(previous.bookmarkData)
            let lease = try open(resolved.url, destinationID: previous.id)
            defer { lease.release() }
            _ = try validateFolder(resolved.url)
            return try sameFolder(resolved.url, url)
        } catch {
            // A display path alone never preserves destination identity.
            return false
        }
    }
}

struct AcquiredBackupDestination: Sendable {
    let lease: DestinationLease
    let record: BackupDestination
}

private enum BackupFolderValidation {
    static func validate(_ url: URL) throws -> String {
        guard url.isFileURL else { throw BackupDestinationError.notDirectory }
        do {
            guard try url.checkResourceIsReachable() else { throw BackupDestinationError.unavailable }
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey, .isWritableKey, .volumeIsReadOnlyKey, .localizedNameKey
            ])
            guard values.isDirectory == true else { throw BackupDestinationError.notDirectory }
            guard values.isWritable == true, values.volumeIsReadOnly != true else { throw BackupDestinationError.notWritable }
            return values.localizedName ?? url.lastPathComponent
        } catch let error as BackupDestinationError {
            throw error
        } catch { throw BackupDestinationError.unavailable }
    }

    static func isSameFolder(_ first: URL, _ second: URL) throws -> Bool {
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey, .volumeIdentifierKey]
        let firstValues = try first.resourceValues(forKeys: keys)
        let secondValues = try second.resourceValues(forKeys: keys)
        guard let firstFile = firstValues.fileResourceIdentifier as? NSObject,
              let secondFile = secondValues.fileResourceIdentifier as? NSObject,
              let firstVolume = firstValues.volumeIdentifier as? NSObject,
              let secondVolume = secondValues.volumeIdentifier as? NSObject else { return false }
        return firstFile.isEqual(secondFile) && firstVolume.isEqual(secondVolume)
    }

    static func isInsideAppContainer(_ url: URL) -> Bool {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
        // An unsandboxed process's entire home directory is not an app container.
        guard home.lastPathComponent == "Data",
              home.deletingLastPathComponent().lastPathComponent == Bundle.main.bundleIdentifier,
              home.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Containers" else { return false }
        let root = home.resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }
}
