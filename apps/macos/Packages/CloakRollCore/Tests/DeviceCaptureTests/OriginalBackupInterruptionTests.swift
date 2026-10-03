import BackupEngine
import Foundation
import MediaModels
import Testing
@testable import DeviceCapture

@Suite("Original backup interruption boundaries", .timeLimit(.minutes(1)))
@MainActor
struct OriginalBackupInterruptionTests {
    @Test(arguments: [false, true])
    func disconnectDuringACompanionRetainsOwnershipAndOnlyRetriesUnverifiedBytes(cancelRun: Bool) async throws {
        let source = try InterruptedBackupSource()
        defer { source.removeDirectory() }
        let session = UUID()
        source.coordinator.begin(sessionID: session)
        let asset = Self.asset(prefix: "first")
        let engine = BackupEngine()
        var finished = false
        let run = Task {
            defer { finished = true }
            return try await engine.run(
                assets: [asset], sessionID: session, destination: source.directory,
                onPublication: { await source.publication($0) }, onVerified: { await source.verified($0) }
            ) { request, progress in try await source.download(request, progress: progress) }
        }
        try await source.waitForRequests(1)
        try source.finish(0, bytes: Data([1, 2, 3]))
        try await source.waitForRequests(2)
        let verified = try #require(source.records.first)
        let final = source.directory.appendingPathComponent(verified.relativePath)
        #expect(try Data(contentsOf: final) == Data([1, 2, 3]))
        let unfinished = source.file(1)
        try Data([4, 5]).write(to: unfinished, options: .withoutOverwriting)

        source.coordinator.retire(sessionID: session)
        if cancelRun { run.cancel(); await engine.cancel() }
        let reconnected = UUID()
        source.coordinator.begin(sessionID: reconnected)
        #expect(!finished && source.coordinator.isBusy)
        #expect(source.cancelled == [1] && source.cleaned == [0])
        #expect(FileManager.default.fileExists(atPath: unfinished.path))
        await #expect(throws: OriginalDownloadError.busy) {
            try await source.coordinator.download(sessionID: reconnected, progress: { _ in }) { _ in
                Issue.record("A retired physical transfer must still own the source slot")
                return OriginalDownloadHandle(cancel: {}, cleanup: {})
            }
        }
        await #expect(throws: BackupEngineError.busy) {
            try await engine.run(assets: [asset], sessionID: reconnected, destination: source.directory) { _, _ in
                throw InterruptionTestFailure.unexpectedSourceCall
            }
        }

        // Simulate the source continuing to write after unplug/Stop, then returning success.
        // Physical settlement releases ownership, but retirement must reject these late bytes.
        try source.finish(1, bytes: Data([4, 5, 6]))
        let result = try await run.value
        #expect(result.snapshot.phase == (cancelRun ? .cancelled : .failed))
        #expect(result.snapshot.completedAssets == 0 && result.snapshot.completedAssetIDs.isEmpty)
        #expect(result.snapshot.verifiedResources == 1 && result.snapshot.verifiedBytes == 3)
        #expect(result.records == [verified] && source.records == [verified] && source.publications.count == 1)
        #expect(source.cleaned == [0, 1] && !source.coordinator.isBusy)
        #expect(try Data(contentsOf: unfinished) == Data([4, 5, 6]))
        let marker = unfinished.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".owner")
        #expect(FileManager.default.fileExists(atPath: marker.path))

        let nextAsset = Self.asset(prefix: "reconnected")
        // This generated fixture defines the same unambiguous originals across sessions.
        // Persistent candidate matching is tested separately; rebase itself grants no trust.
        let rebased = try BackupEngine.rebase(
            verified, asset: nextAsset, resource: nextAsset.resources[0], sessionID: reconnected
        )
        let checked = try await BackupVerification.validateExisting(
            assets: [nextAsset], sessionID: reconnected, destination: source.directory, records: [rebased]
        )
        #expect(checked.records == [rebased] && checked.snapshot.completedAssetIDs.isEmpty)
        let retryEngine = BackupEngine(previousRecords: checked.records)
        let retry = Task {
            try await retryEngine.run(assets: [nextAsset], sessionID: reconnected, destination: source.directory) { request, progress in
                try await source.download(request, progress: progress)
            }
        }
        try await source.waitForRequests(3)
        #expect(source.requests[2].resource.id == nextAsset.resources[1].id)
        source.report(1, bytes: 100)
        source.repeatCompletion(1)
        source.report(2, bytes: 1)
        try await source.waitForForwardedProgress()
        #expect(source.forwarded.values == [DownloadProgress(downloadedBytes: 1, totalBytes: 3)])
        #expect(source.cleaned == [0, 1] && source.coordinator.isBusy)
        try source.finish(2, bytes: Data([7, 8, 9]))
        let resumed = try await retry.value
        #expect(resumed.snapshot.phase == .completed && resumed.snapshot.completedAssetIDs == [nextAsset.id])
        #expect(resumed.snapshot.verifiedResources == 2 && resumed.snapshot.transferredBytes == 3)
        #expect(source.requests.count == 3 && source.highWater == 1 && source.cleaned == [0, 1, 2])
        #expect(try Data(contentsOf: final) == Data([1, 2, 3]))
        #expect(try Data(contentsOf: unfinished) == Data([4, 5, 6]))
        #expect(FileManager.default.fileExists(atPath: marker.path))
        let motion = try #require(resumed.records.first { $0.resourceID == nextAsset.resources[1].id })
        #expect(try Data(contentsOf: source.directory.appendingPathComponent(motion.relativePath)) == Data([7, 8, 9]))
    }

    private static func asset(prefix: String) -> MediaAsset {
        MediaAsset(id: "\(prefix)-asset", deviceID: "fixture-phone", resources: [
            MediaResource(id: "\(prefix)-still", filename: "IMG_TEST.HEIC", byteCount: 3),
            MediaResource(id: "\(prefix)-motion", filename: "IMG_TEST.MOV", byteCount: 3)
        ], kind: .livePhoto, createdAt: Date(timeIntervalSince1970: 1_789_214_400))
    }
}

@MainActor
private final class InterruptedBackupSource {
    let coordinator = OriginalDownloadCoordinator()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CloakRollInterruption-\(UUID())")
    let forwarded = InterruptionProgress()
    private(set) var requests: [BackupDownloadRequest] = []
    private(set) var cancelled: [Int] = []
    private(set) var cleaned: [Int] = []
    private(set) var records: [VerifiedBackupResource] = []
    private(set) var publications: [BackupPublicationIntent] = []
    private(set) var highWater = 0
    private var callbacks: [OriginalDownloadCoordinator.Callback] = []
    private var outstanding = 0

    init() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false) }

    func download(_ request: BackupDownloadRequest, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> DownloadedOriginal {
        let forwarded = forwarded
        return try await coordinator.download(sessionID: request.sessionID, progress: {
            forwarded.append($0)
            progress($0)
        }) { receive in
            let index = self.requests.count
            self.requests.append(request)
            self.callbacks.append(receive)
            self.outstanding += 1
            self.highWater = max(self.highWater, self.outstanding)
            return OriginalDownloadHandle(cancel: { self.cancelled.append(index) }, cleanup: {
                self.cleaned.append(index)
                self.outstanding -= 1
            })
        }
    }

    func file(_ index: Int) -> URL { requests[index].directory.appendingPathComponent(requests[index].filename) }
    func publication(_ intent: BackupPublicationIntent) { publications.append(intent) }
    func verified(_ record: VerifiedBackupResource) { records.append(record) }

    func finish(_ index: Int, bytes: Data) throws {
        try bytes.write(to: file(index))
        repeatCompletion(index)
    }

    func repeatCompletion(_ index: Int) {
        callbacks[index](.completed(.success(DownloadedOriginal(url: file(index), expectedByteCount: 3))))
    }

    func report(_ index: Int, bytes: Int64) {
        callbacks[index](.progress(DownloadProgress(downloadedBytes: bytes, totalBytes: 3)))
    }

    func waitForRequests(_ count: Int) async throws { try await waitFor { self.requests.count == count } }
    func waitForForwardedProgress() async throws { try await waitFor { !self.forwarded.values.isEmpty } }
    func removeDirectory() { try? FileManager.default.removeItem(at: directory) }

    private func waitFor(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        guard predicate() else { throw InterruptionTestFailure.timeout }
    }
}

private final class InterruptionProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DownloadProgress] = []
    var values: [DownloadProgress] { lock.withLock { storage } }
    func append(_ value: DownloadProgress) { lock.withLock { storage.append(value) } }
}

private enum InterruptionTestFailure: Error { case unexpectedSourceCall, timeout }
