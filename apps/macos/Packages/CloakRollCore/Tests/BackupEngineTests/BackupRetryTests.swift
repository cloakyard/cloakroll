import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Verified component retry evidence")
struct BackupRetryTests {
    @Test func retryRevalidatesAndReusesOnlyPreviouslyVerifiedComponents() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let session = UUID()
        let asset = backupAsset(resources: [
            MediaResource(id: "photo", filename: "IMG.HEIC", byteCount: 3),
            MediaResource(id: "motion", filename: "IMG.MOV", byteCount: 3)
        ])
        let first = try await BackupEngine().run(assets: [asset], sessionID: session, destination: destination) { request, _ in
            if request.resource.id == "motion" { throw BackupTestError.source }
            return try writeOriginal(request, data: Data([1, 2, 3]))
        }
        #expect(first.snapshot.phase == .failed)
        #expect(first.records.count == 1)
        let recorder = BackupRecorder()
        let retry = try await BackupEngine(previousRecords: first.records).run(
            assets: [asset], sessionID: session, destination: destination
        ) { request, _ in
            await recorder.loaded(request.resource.id)
            return try writeOriginal(request, data: Data([4, 5, 6]))
        }
        #expect(retry.snapshot.phase == .completed)
        #expect(await recorder.loadedIDs == ["motion"])
        #expect(retry.records[0] == first.records[0])
        #expect(retry.snapshot.verifiedResources == 2)
        #expect(retry.snapshot.verifiedBytes == 6)
        #expect(retry.snapshot.transferredBytes == 3)
        #expect(retry.snapshot.completedAssetIDs == [asset.id])
    }

    @Test func modifiedDestinationBytesArePreservedAndSourceDownloadsToANewExclusiveName() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let session = UUID()
        let asset = backupAsset()
        let original = try await BackupEngine().run(assets: [asset], sessionID: session, destination: destination) { request, _ in
            try writeOriginal(request, data: Data([1, 2, 3]))
        }
        let firstRecord = try #require(original.records.first)
        let changed = destination.appendingPathComponent(firstRecord.relativePath)
        try Data([9, 9, 9]).write(to: changed)
        let retry = try await BackupEngine(previousRecords: original.records).run(
            assets: [asset], sessionID: session, destination: destination
        ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        #expect(retry.snapshot.phase == .completed)
        #expect(retry.snapshot.transferredBytes == 3)
        #expect(retry.records.first?.relativePath != firstRecord.relativePath)
        #expect(try Data(contentsOf: changed) == Data([9, 9, 9]))
    }

    @Test(arguments: ["session", "device", "metadata", "destination"])
    func evidenceNeverCrossesItsSourceOrDestinationScope(change: String) async throws {
        let firstDestination = try backupDirectory()
        let secondDestination = try backupDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDestination)
            try? FileManager.default.removeItem(at: secondDestination)
        }
        let session = UUID()
        let originalAsset = backupAsset()
        let original = try await BackupEngine().run(assets: [originalAsset], sessionID: session, destination: firstDestination) { request, _ in
            try writeOriginal(request, data: Data([1, 2, 3]))
        }
        let resource = try #require(originalAsset.resources.first)
        let nextResource = MediaResource(
            id: resource.id, filename: resource.filename, byteCount: resource.byteCount,
            modifiedAt: change == "metadata" ? Date(timeIntervalSince1970: 42) : resource.modifiedAt
        )
        let nextAsset = MediaAsset(
            id: originalAsset.id, deviceID: change == "device" ? "another-device" : originalAsset.deviceID,
            resources: [nextResource], kind: originalAsset.kind, createdAt: originalAsset.createdAt
        )
        let next = try await BackupEngine(previousRecords: original.records).run(
            assets: [nextAsset], sessionID: change == "session" ? UUID() : session,
            destination: change == "destination" ? secondDestination : firstDestination
        ) { request, _ in try writeOriginal(request, data: Data([4, 5, 6])) }
        #expect(next.snapshot.phase == .completed)
        #expect(next.snapshot.transferredBytes == 3)
        #expect(next.records.first?.sha256 != original.records.first?.sha256)
    }

    @Test func alreadyCompleteSelectionReusesEveryVerifiedFileAfterCheckingItsDigest() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let session = UUID()
        let asset = backupAsset()
        let first = try await BackupEngine().run(assets: [asset], sessionID: session, destination: destination) { request, _ in
            try writeOriginal(request, data: Data([1, 2, 3]))
        }
        let next = try await BackupEngine(previousRecords: first.records).run(assets: [asset], sessionID: session, destination: destination) { _, _ in
            throw BackupTestError.unexpectedLoad
        }
        #expect(next.snapshot.phase == .completed)
        #expect(next.snapshot.transferredBytes == 0)
        #expect(next.snapshot.verifiedBytes == 3)
        #expect(next.records == first.records)
    }
}
