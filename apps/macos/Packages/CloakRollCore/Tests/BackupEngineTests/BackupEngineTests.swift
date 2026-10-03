import CryptoKit
import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Original backup state machine")
struct BackupEngineTests {
    @Test func preservesEveryOriginalAndMarksAnAssetOnlyAfterAllComponentsVerify() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let resources = [
            MediaResource(id: "photo", filename: "IMG_0001.HEIC", byteCount: 3),
            MediaResource(id: "motion", filename: "IMG_0001.MOV", byteCount: 4),
            MediaResource(id: "sidecar", filename: "IMG_0001.AAE", byteCount: 5)
        ]
        let asset = backupAsset(resources: resources)
        let session = UUID()
        let result = try await BackupEngine(timeZone: .gmt).run(assets: [asset], sessionID: session, destination: destination) { request, _ in
            try writeOriginal(request, data: Data(repeating: UInt8(request.resource.byteCount), count: Int(request.resource.byteCount)))
        }
        #expect(result.snapshot.phase == .completed)
        #expect(result.snapshot.completedAssetIDs == [asset.id])
        #expect(result.snapshot.verifiedResources == 3)
        #expect(result.snapshot.verifiedBytes == 12)
        #expect(result.snapshot.transferredBytes == 12)
        #expect(result.records.map(\.resourceID) == resources.map(\.id))
        for record in result.records {
            let data = try Data(contentsOf: destination.appendingPathComponent(record.relativePath))
            #expect(data == Data(repeating: UInt8(record.byteCount), count: Int(record.byteCount)))
            #expect(record.sha256 == SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            #expect(record.sourceSessionID == session)
            #expect(record.sourceMetadataSignature.count == 64)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).contains { $0.hasPrefix(".cloakroll-staging-") } == false)
    }

    @Test func aFailedCompanionPreservesVerifiedFilesWithoutMarkingTheAssetComplete() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let asset = backupAsset(resources: [
            MediaResource(id: "photo", filename: "IMG.HEIC", byteCount: 3),
            MediaResource(id: "motion", filename: "IMG.MOV", byteCount: 3)
        ])
        let result = try await BackupEngine().run(assets: [asset], sessionID: UUID(), destination: destination) { request, _ in
            if request.resource.id == "motion" { throw BackupTestError.source }
            return try writeOriginal(request, data: Data([1, 2, 3]))
        }
        #expect(result.snapshot.phase == .failed)
        #expect(result.snapshot.completedAssets == 0)
        #expect(result.snapshot.completedAssetIDs.isEmpty)
        #expect(result.records.count == 1)
        #expect(result.snapshot.verifiedResources == 1)
        #expect(try Data(contentsOf: destination.appendingPathComponent(result.records[0].relativePath)) == Data([1, 2, 3]))
    }

    @Test(arguments: [0, 4])
    func changedLaunchMetadataNeverCreatesAVerifiedRecord(returnedExpected: Int64) async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try await BackupEngine().run(assets: [backupAsset()], sessionID: UUID(), destination: destination) { request, _ in
            try writeOriginal(request, data: Data([1, 2, 3]), expectedByteCount: returnedExpected)
        }
        #expect(result.snapshot.phase == .failed)
        #expect(result.snapshot.verifiedResources == 0)
        #expect(result.records.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).allSatisfy { $0.hasPrefix(".cloakroll-staging-") })
    }

    @Test(arguments: [Data([1, 2]), Data([1, 2, 3, 4])])
    func localSizeMismatchNeverCreatesAVerifiedRecord(data: Data) async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try await BackupEngine().run(assets: [backupAsset()], sessionID: UUID(), destination: destination) { request, _ in
            try writeOriginal(request, data: data)
        }
        #expect(result.snapshot.phase == .failed)
        #expect(result.records.isEmpty)
        #expect(result.snapshot.verifiedBytes == 0)
    }

    @Test func unavailableDestinationFailsBeforeAnySourceCall() async throws {
        let parent = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let destination = parent.appendingPathComponent("not-a-folder")
        try Data([42]).write(to: destination)
        let result = try await BackupEngine().run(assets: [backupAsset()], sessionID: UUID(), destination: destination) { _, _ in
            throw BackupTestError.unexpectedLoad
        }
        #expect(result.snapshot.phase == .failed)
        #expect(result.records.isEmpty)
        #expect(try Data(contentsOf: destination) == Data([42]))
    }

    @Test func invalidSelectionIsRejectedBeforeTouchingDestination() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let invalid = backupAsset(resources: [MediaResource(id: "unknown", filename: "UNKNOWN.HEIC", byteCount: 0)])
        let result = try await BackupEngine().run(assets: [invalid], sessionID: UUID(), destination: destination) { _, _ in
            throw BackupTestError.unexpectedLoad
        }
        #expect(result.snapshot.phase == .failed)
        #expect(result.snapshot.verifiedResources == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    @Test func aWriteFailureAfterPartialBytesNeverBecomesAVerifiedBackup() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let sentinel = destination.appendingPathComponent("unrelated.txt")
        try Data([42]).write(to: sentinel)
        let result = try await BackupEngine().run(assets: [backupAsset()], sessionID: UUID(), destination: destination) { request, progress in
            try Data([1]).write(to: request.directory.appendingPathComponent(request.filename))
            progress(DownloadProgress(downloadedBytes: 1, totalBytes: 3))
            throw CocoaError(.fileWriteOutOfSpace)
        }
        #expect(result.snapshot.phase == .failed)
        #expect(result.records.isEmpty)
        #expect(result.snapshot.completedAssets == 0)
        #expect(try Data(contentsOf: sentinel) == Data([42]))
        let names = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        #expect(names.count == 2)
        #expect(names.contains { $0.hasPrefix(".cloakroll-staging-") })
    }
}
