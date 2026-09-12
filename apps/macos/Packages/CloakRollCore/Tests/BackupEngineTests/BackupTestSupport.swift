import Foundation
import MediaModels
import Testing
@testable import BackupEngine

enum BackupTestError: Error { case source, timeout, unexpectedLoad }

func backupDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CloakRollBackupTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

func backupAsset(_ id: String = "asset", resources: [MediaResource]? = nil) -> MediaAsset {
    MediaAsset(
        id: id, deviceID: "device", resources: resources ?? [MediaResource(id: "original", filename: "IMG_0001.HEIC", byteCount: 3)],
        kind: resources?.count == 2 ? .livePhoto : .photo,
        createdAt: Date(timeIntervalSince1970: 1_789_214_400)
    )
}

func writeOriginal(_ request: BackupDownloadRequest, data: Data, expectedByteCount: Int64? = nil) throws -> DownloadedOriginal {
    let url = request.directory.appendingPathComponent(request.filename)
    try data.write(to: url, options: [.withoutOverwriting])
    return DownloadedOriginal(url: url, expectedByteCount: expectedByteCount ?? request.resource.byteCount)
}

actor HeldOriginalSource {
    private(set) var requests: [BackupDownloadRequest] = []
    private var pending: CheckedContinuation<Data, any Error>?
    private var progress: (@Sendable (DownloadProgress) -> Void)?

    func download(_ request: BackupDownloadRequest, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> DownloadedOriginal {
        requests.append(request)
        self.progress = progress
        let data = try await withCheckedThrowingContinuation { pending = $0 }
        let result = try writeOriginal(request, data: data)
        try Task.checkCancellation()
        return result
    }

    func report(_ bytes: Int64) { progress?(DownloadProgress(downloadedBytes: bytes, totalBytes: nil)) }
    func finish(_ data: Data = Data([1, 2, 3])) {
        pending?.resume(returning: data)
        pending = nil
    }
}

actor BackupRecorder {
    private(set) var snapshots: [BackupSnapshot] = []
    private(set) var finished = false
    private(set) var loadedIDs: [String] = []
    func receive(_ snapshot: BackupSnapshot) { snapshots.append(snapshot) }
    func finish() { finished = true }
    func loaded(_ id: String) { loadedIDs.append(id) }
}

func observe(_ engine: BackupEngine, recorder: BackupRecorder) -> Task<Void, Never> {
    Task {
        for await snapshot in engine.snapshots {
            guard !Task.isCancelled else { return }
            await recorder.receive(snapshot)
        }
    }
}

func waitForBackup(_ message: String, condition: @escaping @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record(Comment(rawValue: message))
    throw BackupTestError.timeout
}
