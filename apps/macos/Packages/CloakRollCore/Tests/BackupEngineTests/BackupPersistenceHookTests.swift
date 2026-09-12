import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Finalized original persistence ownership")
struct BackupPersistenceHookTests {
    @Test func failedWriteRetainsOriginalAndRetryReverifiesBeforeRecordingWithoutDownloading() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let session = UUID()
        let asset = backupAsset()
        let engine = BackupEngine()
        let first = try await engine.run(
            assets: [asset], sessionID: session, destination: destination,
            onVerified: { _ in throw BackupTestError.source }
        ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        #expect(first.snapshot.phase == .failed)
        #expect(first.snapshot.completedAssetIDs.isEmpty)
        #expect(first.snapshot.verifiedResources == 1)
        let record = try #require(first.records.first)
        #expect(try Data(contentsOf: destination.appendingPathComponent(record.relativePath)) == Data([1, 2, 3]))
        let recorder = HookRecorder()
        let retry = try await engine.run(
            assets: [asset], sessionID: session, destination: destination,
            onVerified: { await recorder.record($0) }
        ) { _, _ in throw BackupTestError.unexpectedLoad }
        #expect(retry.snapshot.phase == .completed)
        #expect(retry.snapshot.completedAssetIDs == [asset.id])
        #expect(retry.snapshot.transferredBytes == 0)
        #expect(retry.records == first.records)
        #expect(await recorder.records == first.records)
    }

    @Test(arguments: [false, true])
    func cancellationAfterPublicationAwaitsUncancelledWriteAndRetainsEvidence(writeFails: Bool) async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let engine = BackupEngine()
        let held = HeldBackupRecord()
        let completion = BackupRecorder()
        let run = Task {
            let result = try await engine.run(
                assets: [backupAsset()], sessionID: UUID(), destination: destination,
                onVerified: { try await held.record($0) }
            ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
            await completion.finish()
            return result
        }
        await held.waitForStart()
        let record = try #require(await held.received)
        let finalURL = destination.appendingPathComponent(record.relativePath)
        #expect(try Data(contentsOf: finalURL) == Data([1, 2, 3]))
        run.cancel()
        await engine.cancel()
        #expect(await completion.finished == false)
        await #expect(throws: BackupEngineError.busy) {
            try await engine.run(assets: [backupAsset()], sessionID: UUID(), destination: destination) { _, _ in
                throw BackupTestError.unexpectedLoad
            }
        }
        await held.finish(failing: writeFails)
        let result = try await run.value
        #expect(await held.sawCancellation == false)
        #expect(result.snapshot.phase == (writeFails ? .failed : .cancelled))
        #expect(result.snapshot.completedAssetIDs.isEmpty)
        #expect(result.records == [record])
        #expect(try Data(contentsOf: finalURL) == Data([1, 2, 3]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).allSatisfy { !$0.hasPrefix(".cloakroll-staging-") })
    }
}

private actor HookRecorder {
    private(set) var records: [VerifiedBackupResource] = []
    func record(_ value: VerifiedBackupResource) { records.append(value) }
}

private actor HeldBackupRecord {
    private(set) var received: VerifiedBackupResource?
    private(set) var sawCancellation = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Bool, Never>?

    func record(_ value: VerifiedBackupResource) async throws {
        received = value
        let failing = await withCheckedContinuation { continuation in
            pending = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
        sawCancellation = Task.isCancelled
        try Task.checkCancellation()
        if failing { throw BackupTestError.source }
    }

    func waitForStart() async {
        guard pending == nil else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish(failing: Bool) {
        pending?.resume(returning: failing)
        pending = nil
    }
}
