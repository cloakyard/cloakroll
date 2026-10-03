import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Backup cancellation and progress")
struct BackupCancellationTests {
    @Test(arguments: [false, true])
    func cancellationKeepsStagingAndRunAliveUntilTheSourceActuallySettles(cancelCallingTask: Bool) async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let engine = BackupEngine()
        let source = HeldOriginalSource()
        let recorder = BackupRecorder()
        let observer = observe(engine, recorder: recorder)
        defer { observer.cancel() }
        let run = Task {
            let result = try await engine.run(assets: [backupAsset()], sessionID: UUID(), destination: destination) { request, progress in
                try await source.download(request, progress: progress)
            }
            await recorder.finish()
            return result
        }
        try await waitForBackup("source starts") { await source.requests.count == 1 }
        let staged = try #require(await source.requests.first).directory
        if cancelCallingTask { run.cancel() } else { await engine.cancel() }
        try await waitForBackup("cancelling remains visible") { await recorder.snapshots.last?.phase == .cancelling }
        #expect(await recorder.finished == false)
        #expect(FileManager.default.fileExists(atPath: staged.path))
        await source.finish()
        let result = try await run.value
        #expect(result.snapshot.phase == .cancelled)
        #expect(result.records.isEmpty)
        #expect(result.snapshot.completedAssets == 0)
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().appendingPathComponent(".owner").path))
    }

    @Test func aConcurrentRunIsRejectedWhileTheFirstSourceIsStillActive() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let engine = BackupEngine()
        let source = HeldOriginalSource()
        let first = Task {
            try await engine.run(assets: [backupAsset()], sessionID: UUID(), destination: destination) { request, progress in
                try await source.download(request, progress: progress)
            }
        }
        try await waitForBackup("first source starts") { await source.requests.count == 1 }
        await #expect(throws: BackupEngineError.busy) {
            try await engine.run(assets: [backupAsset()], sessionID: UUID(), destination: destination) { _, _ in
                throw BackupTestError.unexpectedLoad
            }
        }
        await source.finish()
        #expect(try await first.value.snapshot.phase == .completed)
    }

    @Test func transferProgressNeverClaimsVerificationBeforeSourceCompletion() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let engine = BackupEngine()
        let source = HeldOriginalSource()
        let recorder = BackupRecorder()
        let observer = observe(engine, recorder: recorder)
        defer { observer.cancel() }
        let run = Task {
            try await engine.run(assets: [backupAsset()], sessionID: UUID(), destination: destination) { request, progress in
                try await source.download(request, progress: progress)
            }
        }
        try await waitForBackup("source starts") { await source.requests.count == 1 }
        await source.report(2)
        try await waitForBackup("partial transfer is published") { await recorder.snapshots.last?.transferredBytes == 2 }
        let partial = try #require(await recorder.snapshots.last)
        #expect(partial.phase == .downloading)
        #expect(partial.verifiedResources == 0)
        #expect(partial.verifiedBytes == 0)
        #expect(partial.completedAssets == 0)
        await source.report(1)
        await source.report(100)
        await source.finish()
        let result = try await run.value
        #expect(result.snapshot.transferredBytes == 3)
        #expect(result.snapshot.verifiedBytes == 3)
        #expect(result.snapshot.phase == .completed)
        #expect(await recorder.snapshots.allSatisfy { $0.transferredBytes <= 3 })
    }
}
