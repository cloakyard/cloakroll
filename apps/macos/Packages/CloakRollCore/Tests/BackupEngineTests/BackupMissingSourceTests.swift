import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Missing source originals", .timeLimit(.minutes(1)))
struct BackupMissingSourceTests {
    @Test func missingOriginalContinuesCompanionsAndLaterAssetsWithoutFalseCompletion() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let live = backupAsset("live", resources: [
            MediaResource(id: "missing", filename: "IMG.HEIC", byteCount: 3),
            MediaResource(id: "motion", filename: "IMG.MOV", byteCount: 3)
        ])
        let later = backupAsset("later", resources: [MediaResource(id: "later-photo", filename: "NEXT.JPG", byteCount: 3)])
        let engine = BackupEngine()
        let session = UUID()
        let calls = BackupRecorder()
        let first = try await engine.run(assets: [live, later], sessionID: session, destination: destination) { request, _ in
            await calls.loaded(request.resource.id)
            if request.resource.id == "missing" { throw MediaSourceError.missingResource }
            return try writeOriginal(request, data: Data([1, 2, 3]))
        }
        #expect(await calls.loadedIDs == ["missing", "motion", "later-photo"])
        #expect(first.snapshot.phase == .failed)
        #expect(first.snapshot.completedAssetIDs == ["later"])
        #expect(first.snapshot.verifiedResources == 2)
        #expect(first.snapshot.verifiedBytes == 6 && first.snapshot.transferredBytes == 6)
        #expect(first.snapshot.unavailableOriginals == [.init(id: "missing", filename: "IMG.HEIC")])
        #expect(first.snapshot.message?.contains("MediaSourceError") == false)
        #expect(Set(first.records.map(\.resourceID)) == ["motion", "later-photo"])
        let paths = first.records.map(\.relativePath)
        let retryCalls = BackupRecorder()
        let retry = try await engine.run(assets: [live, later], sessionID: session, destination: destination) { request, _ in
            await retryCalls.loaded(request.resource.id)
            return try writeOriginal(request, data: Data([4, 5, 6]))
        }
        #expect(await retryCalls.loadedIDs == ["missing"])
        #expect(retry.snapshot.phase == .completed && retry.snapshot.completedAssets == 2)
        #expect(retry.snapshot.unavailableOriginals.isEmpty)
        #expect(retry.snapshot.transferredBytes == 3)
        for path in paths { #expect(try Data(contentsOf: destination.appendingPathComponent(path)) == Data([1, 2, 3])) }
    }

    @Test func everyMissingOriginalRemainsAnIncompleteBackup() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try await BackupEngine().run(assets: [backupAsset()], sessionID: UUID(), destination: destination) { _, _ in
            throw MediaSourceError.missingResource
        }
        #expect(result.snapshot.phase == .failed)
        #expect(result.snapshot.completedAssets == 0 && result.snapshot.verifiedResources == 0)
        #expect(result.snapshot.currentResourceBytes == 0)
        #expect(result.records.isEmpty && result.snapshot.unavailableOriginals.count == 1)
    }

    @Test(arguments: [MediaSourceError.staleSession, .unavailable])
    func sessionAndAccessFailuresStillStopTheBackup(error: MediaSourceError) async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let assets = [backupAsset(), backupAsset("later", resources: [MediaResource(id: "later", filename: "NEXT.JPG", byteCount: 3)])]
        let calls = BackupRecorder()
        let result = try await BackupEngine().run(assets: assets, sessionID: UUID(), destination: destination) { request, _ in
            await calls.loaded(request.resource.id)
            throw error
        }
        #expect(await calls.loadedIDs == ["original"])
        #expect(result.snapshot.phase == .failed && result.records.isEmpty)
        #expect(result.snapshot.unavailableOriginals.isEmpty)
        #expect(result.snapshot.message == error.errorDescription)
    }

    @Test func cancellationDuringMissingSourceDoesNotContinueTheQueue() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let calls = BackupRecorder()
        let engine = BackupEngine()
        let result = try await engine.run(assets: [backupAsset()], sessionID: UUID(), destination: destination) { request, _ in
            await calls.loaded(request.resource.id)
            await engine.cancel()
            throw MediaSourceError.missingResource
        }
        #expect(result.snapshot.phase == .cancelled)
        #expect(result.snapshot.unavailableOriginals.isEmpty && result.records.isEmpty)
    }
}
