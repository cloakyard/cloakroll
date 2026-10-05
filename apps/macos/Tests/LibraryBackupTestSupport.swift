import BackupEngine
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

enum BackupLibraryFixture {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)

    static func asset(
        id: String = "asset", deviceID: String = "phone", createdAt: Date? = date, kind: MediaKind = .photo,
        duration: Double? = nil, width: Int? = 4000, height: Int? = 3000, primary: String = "still",
        companion: Bool = false, resource: MediaResource? = nil
    ) -> MediaAsset {
        var resources = [resource ?? MediaResource(id: "still", filename: "IMG.HEIC", byteCount: 3, modifiedAt: date)]
        if companion { resources.append(MediaResource(id: "motion", filename: "IMG.MOV", byteCount: 2, modifiedAt: date)) }
        return MediaAsset(
            id: id, deviceID: deviceID, resources: resources, kind: companion ? .livePhoto : kind,
            createdAt: createdAt, duration: duration, pixelWidth: width, pixelHeight: height, primaryResourceID: primary
        )
    }

    static func record(
        _ asset: MediaAsset, resource: MediaResource, sessionID: UUID, dateOffset: TimeInterval = 0
    ) -> VerifiedBackupResource {
        VerifiedBackupResource(
            assetID: asset.id, resourceID: resource.id, deviceID: asset.deviceID, sourceSessionID: sessionID,
            filename: resource.filename, relativePath: "2023/11/" + resource.filename, byteCount: resource.byteCount,
            sha256: "fixture-only", verifiedAt: date.addingTimeInterval(dateOffset), sourceModifiedAt: resource.modifiedAt,
            destinationIdentity: "fixture-destination", sourceMetadataSignature: "fixture-signature"
        )
    }
}

@MainActor
final class BackupControllerFixture {
    let folder: URL
    let controller: LibraryBackupController
    let scope: BackupScopeProbe
    let source = ControlledBackupOriginals()

    init(hasSelection: Bool = true, allowsFolderSelection: Bool = false) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("CloakRollLibraryBackupTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        scope = BackupScopeProbe(folder: folder)
        let record = hasSelection ? BackupDestination(
            id: UUID(), displayName: "Test Backup", lastKnownPath: folder.path, bookmarkData: Data([1, 2, 3])
        ) : nil
        let defaults = BackupMemoryDefaults(data: try record.map { try JSONEncoder().encode($0) })
        let selectedFolder = folder
        let destination = BackupDestinationStore(defaults: defaults, operations: scope.operations,
            selectFolder: { allowsFolderSelection ? selectedFolder : nil }, saveRecord: { _ in })
        controller = LibraryBackupController(destination: destination)
    }

    func start(_ assets: [MediaAsset], session: UUID) {
        let source = source
        controller.start(assets: assets, sessionID: session) { request, progress in
            try await source.download(request, progress: progress)
        }
    }

    func regularFiles() throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]))
        return try enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true ? url : nil
        }
    }

    deinit { try? FileManager.default.removeItem(at: folder) }
}

/// The only defaults lookup the destination store uses is overridden. No production defaults
/// are read, and the injected save closure never writes a persistent domain.
private final class BackupMemoryDefaults: UserDefaults, @unchecked Sendable {
    private let initialData: Data?

    init(data: Data?) {
        initialData = data
        super.init(suiteName: "CloakRollInMemoryBackupTests-" + UUID().uuidString)!
    }

    override func data(forKey defaultName: String) -> Data? { initialData }
}

final class BackupScopeProbe: @unchecked Sendable {
    struct Counts {
        var started = 0
        var stopped = 0
        var active: Int { started - stopped }
    }

    private let lock = NSLock()
    private var recorded = Counts()
    private let folder: URL
    var counts: Counts { lock.withLock { recorded } }

    init(folder: URL) { self.folder = folder }

    var operations: BackupDestinationOperations {
        BackupDestinationOperations(
            resolveBookmark: { [folder] _ in ResolvedBackupBookmark(url: folder, isStale: false) },
            makeBookmark: { _ in Data([1, 2, 3]) },
            startAccess: { [self] _ in lock.withLock { recorded.started += 1 }; return true },
            stopAccess: { [self] _ in lock.withLock { recorded.stopped += 1 } },
            requiresSecurityScope: { _ in true },
            validateFolder: { [folder] url in
                guard url == folder, try url.checkResourceIsReachable() else { throw BackupDestinationError.unavailable }
                return "Test Backup"
            },
            sameFolder: { $0 == $1 }
        )
    }
}

/// No hardware or UI. A fake physical callback explicitly closes the output file and releases
/// the waiting source; task cancellation is observed only after that callback, as in production.
actor ControlledBackupOriginals {
    private struct StartWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var counts: [String: Int] = [:]
    private var requests: [String: BackupDownloadRequest] = [:]
    private var starts: [String: [StartWaiter]] = [:]
    private var pending: [String: CheckedContinuation<DownloadedOriginal, any Error>] = [:]
    private var progressCallbacks: [String: @Sendable (DownloadProgress) -> Void] = [:]
    private var cancelled: Set<String> = []
    private var cancellationWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    var totalCalls: Int { counts.values.reduce(0, +) }
    func callCount(_ id: String) -> Int { counts[id, default: 0] }
    func lastRequest(_ id: String) -> BackupDownloadRequest? { requests[id] }

    func download(
        _ request: BackupDownloadRequest, progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadedOriginal {
        let id = request.resource.id
        requests[id] = request
        progressCallbacks[id] = progress
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                counts[id, default: 0] += 1
                let waiters = starts.removeValue(forKey: id) ?? []
                for waiter in waiters {
                    if counts[id, default: 0] >= waiter.count { waiter.continuation.resume() }
                    else { starts[id, default: []].append(waiter) }
                }
            }
        } onCancel: {
            Task { await self.observeCancellation(id) }
        }
        try Task.checkCancellation()
        return result
    }

    func waitForStart(_ id: String, count: Int = 1) async {
        guard counts[id, default: 0] < count else { return }
        await withCheckedContinuation { starts[id, default: []].append(StartWaiter(count: count, continuation: $0)) }
    }

    func waitForCancellation(_ id: String) async {
        guard !cancelled.contains(id) else { return }
        await withCheckedContinuation { cancellationWaiters[id, default: []].append($0) }
    }

    func finish(_ id: String, bytes: Data) throws {
        let request = try #require(requests[id])
        let waiting = pending.removeValue(forKey: id)
        let continuation = try #require(waiting)
        do {
            let url = request.directory.appendingPathComponent(request.filename)
            try bytes.write(to: url)
            continuation.resume(returning: DownloadedOriginal(url: url, expectedByteCount: request.resource.byteCount))
        } catch {
            continuation.resume(throwing: error)
            throw error
        }
    }

    func fail(_ id: String) throws {
        let waiting = pending.removeValue(forKey: id)
        let continuation = try #require(waiting)
        continuation.resume(throwing: OriginalDownloadError.failed(domain: "CloakRollTest", code: 1))
    }

    func report(_ id: String, downloadedBytes: Int64) {
        progressCallbacks[id]?(DownloadProgress(downloadedBytes: downloadedBytes, totalBytes: requests[id]?.resource.byteCount))
    }

    private func observeCancellation(_ id: String) {
        cancelled.insert(id)
        cancellationWaiters.removeValue(forKey: id)?.forEach { $0.resume() }
    }
}
