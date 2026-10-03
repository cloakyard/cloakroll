import Foundation
import Testing
@testable import BackupEngine

@Suite("Durable original publication boundary")
struct BackupJournalTests {
    @Test func stagingFailurePreventsAnySourceCall() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await BackupEngine().run(
            assets: [backupAsset()], sessionID: UUID(), destination: root,
            onStaged: { _ in throw BackupTestError.source }
        ) { _, _ in throw BackupTestError.unexpectedLoad }
        #expect(result.snapshot.phase == .failed)
        #expect(result.records.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func failedPublicationWriteKeepsVerifiedStageAndOwnershipMarkerWithoutPublishing() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = JournalCapture()
        let result = try await BackupEngine().run(
            assets: [backupAsset()], sessionID: UUID(), destination: root,
            onPublication: { intent in await capture.publication(intent); throw BackupTestError.source }
        ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        #expect(result.snapshot.phase == .failed)
        #expect(result.records.isEmpty)
        let intent = try #require(await capture.publications.first)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(intent.relativePath).path))
        #expect(try await BackupRecovery.inspect(destination: root, intent: intent) == .staged)
        let marker = root.appendingPathComponent(intent.staging.stagingRelativePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".owner")
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    @Test(arguments: [false, true])
    func cancellationAwaitsEachJournalBoundaryWithoutStartingItsNextOperation(publication: Bool) async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let held = HeldJournal()
        let engine = BackupEngine()
        let completion = BackupRecorder()
        let capture = JournalCapture()
        let run = Task {
            let result = try await engine.run(
                assets: [backupAsset()], sessionID: UUID(), destination: root,
                onStaged: { _ in if !publication { await held.wait() } },
                onPublication: { intent in await capture.publication(intent); if publication { await held.wait() } }
            ) { request, _ in
                await capture.source()
                return try writeOriginal(request, data: Data([1, 2, 3]))
            }
            await completion.finish()
            return result
        }
        try await waitForBackup("journal starts") { await held.started }
        run.cancel()
        await engine.cancel()
        #expect(await completion.finished == false)
        await held.finish()
        let result = try await run.value
        #expect(await held.wasCancelled == false)
        #expect(result.snapshot.phase == .cancelled)
        #expect(result.records.isEmpty)
        #expect(await capture.sourceCalls == (publication ? 1 : 0))
        if let intent = await capture.publications.first {
            #expect(try await BackupRecovery.inspect(destination: root, intent: intent) == .staged)
        }
    }

    @Test(arguments: [false, true])
    func stagedMutationAcrossDurableAwaitNeverPublishes(replaceInode: Bool) async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = JournalCapture()
        let result = try await BackupEngine().run(
            assets: [backupAsset()], sessionID: UUID(), destination: root,
            onPublication: { intent in
                await capture.publication(intent)
                let file = root.appendingPathComponent(intent.staging.stagingRelativePath)
                if replaceInode {
                    try FileManager.default.moveItem(at: file, to: file.appendingPathExtension("preserved"))
                    try Data([1, 2, 3]).write(to: file)
                } else {
                    let handle = try FileHandle(forWritingTo: file)
                    try handle.write(contentsOf: Data([3, 2, 1]))
                    try handle.close()
                }
            }
        ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        #expect(result.snapshot.phase == .failed)
        #expect(result.records.isEmpty)
        let intent = try #require(await capture.publications.first)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(intent.relativePath).path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(intent.staging.stagingRelativePath).path))
        #expect(try await BackupRecovery.inspect(destination: root, intent: intent) == .unavailable)
    }

    @Test func everyExclusiveCollisionAttemptGetsItsOwnDurableFinalPath() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = JournalCapture()
        let result = try await BackupEngine().run(
            assets: [backupAsset()], sessionID: UUID(), destination: root,
            onStaged: { await capture.staging($0) },
            onPublication: { intent in
                await capture.publication(intent)
                if await capture.publications.count == 1 {
                    // Deliberately identical bytes still belong to a different original inode.
                    try Data([1, 2, 3]).write(to: root.appendingPathComponent(intent.relativePath))
                }
            }
        ) { request, _ in
            #expect(await capture.stages.count == 1)
            return try writeOriginal(request, data: Data([1, 2, 3]))
        }
        #expect(result.snapshot.phase == .completed)
        let intents = await capture.publications
        #expect(intents.count == 2)
        #expect(intents[0].staging == intents[1].staging)
        #expect(intents[0].fileIdentity == intents[1].fileIdentity)
        #expect(intents[0].verifiedAt == intents[1].verifiedAt)
        #expect(intents[0].relativePath != intents[1].relativePath)
        #expect(try await BackupRecovery.inspect(destination: root, intent: intents[0]) == .unavailable)
        #expect(try await BackupRecovery.inspect(destination: root, intent: intents[1]) == .published(result.records[0]))
        #expect(try Data(contentsOf: root.appendingPathComponent(intents[0].relativePath)) == Data([1, 2, 3]))
    }
}

actor JournalCapture {
    private(set) var stages: [BackupStagingIntent] = []
    private(set) var publications: [BackupPublicationIntent] = []
    private(set) var sourceCalls = 0
    func staging(_ value: BackupStagingIntent) { stages.append(value) }
    func publication(_ value: BackupPublicationIntent) { publications.append(value) }
    func source() { sourceCalls += 1 }
}

private actor HeldJournal {
    private(set) var started = false
    private(set) var wasCancelled = false
    private var pending: CheckedContinuation<Void, Never>?
    func wait() async {
        started = true
        await withCheckedContinuation { pending = $0 }
        wasCancelled = Task.isCancelled
    }
    func finish() { pending?.resume(); pending = nil }
}
