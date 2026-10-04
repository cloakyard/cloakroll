import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Continuous backup byte accounting", .timeLimit(.minutes(1)))
struct BackupProgressAccountingTests {
    @Test func downloadingPublicationRecordingAndNextOriginalDoNotLoseOrDoubleCountBytes() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let asset = backupAsset(resources: [resource("first", bytes: 3), resource("second", bytes: 5)])
        let engine = BackupEngine()
        let source = ProgressAccountingSource()
        let boundary = ProgressAccountingBoundary()
        let recorder = BackupRecorder()
        let observer = observe(engine, recorder: recorder)
        defer { observer.cancel() }
        let run = Task {
            try await engine.run(
                assets: [asset], sessionID: UUID(), destination: destination,
                onPublication: { await boundary.pause("publication:" + $0.staging.resourceID) },
                onVerified: { await boundary.pause("record:" + $0.resourceID) },
                download: source.download
            )
        }
        try await waitForBackup("first original starts") { await source.requests.count == 1 }
        await source.report("first", bytes: 2)
        try await waitForBackup("partial bytes reach the stream") { await recorder.snapshots.last?.currentResourceBytes == 2 }
        let partial = try #require(await recorder.snapshots.last)
        #expect(partial.verifiedBytes == 0 && partial.transferredBytes == 2)
        await source.report("first", bytes: -1)
        await source.finish("first")
        try await waitForBackup("first publication is held") { await boundary.reached.contains("publication:first") }
        let downloaded = try await accountingSnapshot(recorder, verified: 0, current: 3, phase: .verifying)
        #expect(downloaded.transferredBytes == 3 && downloaded.completedAssets == 0)

        await boundary.resume("publication:first")
        try await waitForBackup("first record is held") { await boundary.reached.contains("record:first") }
        let firstRecorded = try await accountingSnapshot(recorder, verified: 3, current: 0, phase: .verifying)
        #expect(firstRecorded.verifiedResources == 1 && firstRecorded.transferredBytes == 3)
        #expect(firstRecorded.completedAssets == 0)
        // A callback retained by the finished source can never refill the cleared byte counter.
        await source.report("first", bytes: 100)
        await boundary.resume("record:first")
        try await waitForBackup("second original starts") { await source.requests.count == 2 }
        let secondStart = try await accountingSnapshot(recorder, verified: 3, current: 0, phase: .downloading)
        #expect(secondStart.expectedBytes == 8 && secondStart.currentResourceExpectedBytes == 5)
        await source.report("first", bytes: 100)
        await source.finish("second")
        try await waitForBackup("second publication is held") { await boundary.reached.contains("publication:second") }
        let secondDownloaded = try await accountingSnapshot(recorder, verified: 3, current: 5, phase: .verifying)
        #expect(secondDownloaded.transferredBytes == 8)
        await boundary.resume("publication:second")
        try await waitForBackup("second record is held") { await boundary.reached.contains("record:second") }
        let secondRecorded = try await accountingSnapshot(recorder, verified: 8, current: 0, phase: .verifying)
        #expect(secondRecorded.transferredBytes == 8 && secondRecorded.completedAssets == 0)
        await boundary.resume("record:second")
        let result = try await run.value
        #expect(result.snapshot.phase == .completed && result.snapshot.completedAssets == 1)
        #expect(result.snapshot.currentResourceBytes == 0 && result.snapshot.verifiedBytes == 8)
        assertContinuousAccounting(await recorder.snapshots + [result.snapshot])
    }

    @Test func reuseAdvancesVerifiedBytesWithoutInflatingTheActualTransferCount() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let session = UUID()
        let first = backupAsset("first", resources: [resource("first", bytes: 3)])
        let second = backupAsset("second", resources: [resource("second", bytes: 5)])
        let previous = try await BackupEngine().run(assets: [first], sessionID: session, destination: destination) { request, _ in
            try writeOriginal(request, data: Data([1, 2, 3]))
        }
        let engine = BackupEngine(previousRecords: previous.records)
        let source = ProgressAccountingSource()
        let boundary = ProgressAccountingBoundary()
        let recorder = BackupRecorder()
        let observer = observe(engine, recorder: recorder)
        defer { observer.cancel() }
        let run = Task {
            try await engine.run(
                assets: [first, second], sessionID: session, destination: destination,
                onVerified: { await boundary.pause($0.resourceID) }, download: source.download
            )
        }
        try await waitForBackup("reused record is held") { await boundary.reached.contains("first") }
        let reused = try await accountingSnapshot(recorder, verified: 3, current: 0, phase: .verifying)
        #expect(reused.transferredBytes == 0 && reused.expectedBytes == 8)
        #expect(await source.requests.isEmpty)
        await boundary.resume("first")
        try await waitForBackup("only missing original starts") { await source.requests.count == 1 }
        #expect(await source.requests.first?.resource.id == "second")
        let next = try await accountingSnapshot(recorder, verified: 3, current: 0, phase: .downloading)
        #expect(next.transferredBytes == 0)
        await source.finish("second")
        try await waitForBackup("downloaded record is held") { await boundary.reached.contains("second") }
        let recorded = try await accountingSnapshot(recorder, verified: 8, current: 0, phase: .verifying)
        #expect(recorded.transferredBytes == 5)
        await boundary.resume("second")
        let result = try await run.value
        #expect(result.snapshot.phase == .completed && result.snapshot.completedAssets == 2)
        assertContinuousAccounting(await recorder.snapshots + [result.snapshot])

        let repeatResult = try await BackupEngine(previousRecords: result.records).run(
            assets: [first, second], sessionID: session, destination: destination
        ) { _, _ in throw BackupTestError.unexpectedLoad }
        #expect(repeatResult.snapshot.phase == .completed)
        #expect(repeatResult.snapshot.verifiedBytes == 8 && repeatResult.snapshot.transferredBytes == 0)
        #expect(repeatResult.snapshot.currentResourceBytes == 0)
    }

    @Test(arguments: [false, true])
    func pendingPersistenceKeepsDisjointEvidenceThroughFailureOrStop(stop: Bool) async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let engine = BackupEngine()
        let boundary = ProgressAccountingBoundary()
        let recorder = BackupRecorder()
        let observer = observe(engine, recorder: recorder)
        defer { observer.cancel() }
        let run = Task {
            try await engine.run(
                assets: [backupAsset()], sessionID: UUID(), destination: destination,
                onVerified: { _ in
                    await boundary.pause("record")
                    if !stop { throw BackupTestError.source }
                }
            ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        }
        try await waitForBackup("record remains owned") { await boundary.reached.contains("record") }
        let recorded = try await accountingSnapshot(recorder, verified: 3, current: 0, phase: .verifying)
        #expect(recorded.completedAssets == 0 && recorded.transferredBytes == 3)
        if stop {
            await engine.cancel()
            _ = try await accountingSnapshot(recorder, verified: 3, current: 0, phase: .cancelling)
        }
        await boundary.resume("record")
        let result = try await run.value
        #expect(result.snapshot.phase == (stop ? .cancelled : .failed))
        #expect(result.snapshot.verifiedBytes == 3 && result.snapshot.currentResourceBytes == 0)
        #expect(result.snapshot.completedAssets == 0 && result.records.count == 1)
        assertContinuousAccounting(await recorder.snapshots + [result.snapshot])
    }

    @Test func stoppedPartialCopyIsNeverCountedAsVerified() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let engine = BackupEngine()
        let source = ProgressAccountingSource()
        let recorder = BackupRecorder()
        let observer = observe(engine, recorder: recorder)
        defer { observer.cancel() }
        let run = Task {
            try await engine.run(assets: [backupAsset()], sessionID: UUID(), destination: destination, download: source.download)
        }
        try await waitForBackup("partial original starts") { await source.requests.count == 1 }
        await source.report("original", bytes: 2)
        _ = try await accountingSnapshot(recorder, verified: 0, current: 2, phase: .downloading)
        await engine.cancel()
        _ = try await accountingSnapshot(recorder, verified: 0, current: 2, phase: .cancelling)
        await source.finish("original")
        let result = try await run.value
        #expect(result.snapshot.phase == .cancelled)
        #expect(result.snapshot.currentResourceBytes == 2 && result.snapshot.transferredBytes == 2)
        #expect(result.snapshot.verifiedBytes == 0 && result.snapshot.verifiedResources == 0)
        #expect(result.snapshot.completedAssets == 0 && result.records.isEmpty)
        assertContinuousAccounting(await recorder.snapshots + [result.snapshot])
    }

    @Test(arguments: [Data([1, 2]), Data([1, 2, 3, 4])])
    func sizeMismatchRetainsReportedBytesWithoutFillingTheExpectedRemainder(data: Data) async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let engine = BackupEngine()
        let source = HeldOriginalSource()
        let recorder = BackupRecorder()
        let observer = observe(engine, recorder: recorder)
        defer { observer.cancel() }
        let run = Task {
            try await engine.run(assets: [backupAsset()], sessionID: UUID(), destination: destination, download: source.download)
        }
        try await waitForBackup("source starts before returning malformed bytes") { await source.requests.count == 1 }
        await source.report(1)
        _ = try await accountingSnapshot(recorder, verified: 0, current: 1, phase: .downloading)
        await source.finish(data)
        let result = try await run.value
        #expect(result.snapshot.phase == .failed && result.snapshot.expectedBytes == 3)
        #expect(result.snapshot.currentResourceBytes == 1 && result.snapshot.transferredBytes == 1)
        #expect(result.snapshot.verifiedBytes == 0 && result.snapshot.verifiedResources == 0)
        #expect(result.snapshot.completedAssets == 0 && result.records.isEmpty)
        let snapshots = await recorder.snapshots + [result.snapshot]
        #expect(snapshots.allSatisfy { $0.currentResourceBytes <= 1 && $0.transferredBytes <= 1 })
        assertContinuousAccounting(snapshots)
    }

    private func resource(_ id: String, bytes: Int64) -> MediaResource {
        MediaResource(id: id, filename: id + ".HEIC", byteCount: bytes)
    }
}

private func accountingSnapshot(
    _ recorder: BackupRecorder, verified: Int64, current: Int64, phase: BackupPhase
) async throws -> BackupSnapshot {
    try await waitForBackup("expected byte accounting reaches the snapshot stream") {
        guard let value = await recorder.snapshots.last else { return false }
        return value.phase == phase && value.verifiedBytes == verified && value.currentResourceBytes == current
    }
    return try #require(await recorder.snapshots.last)
}

private func assertContinuousAccounting(_ snapshots: [BackupSnapshot]) {
    var previous: Int64 = 0
    for value in snapshots where value.expectedBytes > 0 {
        let bytes = value.verifiedBytes + value.currentResourceBytes
        #expect(bytes >= previous)
        #expect(bytes <= value.expectedBytes)
        #expect(value.transferredBytes >= 0 && value.transferredBytes <= value.expectedBytes)
        previous = bytes
    }
}

private actor ProgressAccountingBoundary {
    private(set) var reached: Set<String> = []
    private var pending: [String: CheckedContinuation<Void, Never>] = [:]

    func pause(_ key: String) async {
        reached.insert(key)
        await withCheckedContinuation { pending[key] = $0 }
    }

    func resume(_ key: String) { pending.removeValue(forKey: key)?.resume() }
}

private actor ProgressAccountingSource {
    private(set) var requests: [BackupDownloadRequest] = []
    private var pending: [String: CheckedContinuation<Void, Never>] = [:]
    private var progress: [String: @Sendable (DownloadProgress) -> Void] = [:]

    func download(
        _ request: BackupDownloadRequest, progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadedOriginal {
        requests.append(request)
        self.progress[request.resource.id] = progress
        await withCheckedContinuation { pending[request.resource.id] = $0 }
        return try writeOriginal(request, data: Data(repeating: 7, count: Int(request.resource.byteCount)))
    }

    func report(_ key: String, bytes: Int64) { progress[key]?(DownloadProgress(downloadedBytes: bytes, totalBytes: nil)) }
    func finish(_ key: String) { pending.removeValue(forKey: key)?.resume() }
}
