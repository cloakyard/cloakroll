import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Live Photo originals remain complete and unchanged")
struct LivePhotoBackupTests {
    @Test(arguments: [BackupFolderLayout.byDevice, .byDeviceFlat], ["HEIC", "JPG"])
    func repeatedNamesKeepEveryPairAndAdjustment(layout: BackupFolderLayout, stillExtension: String) async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let assets = [asset("one", stillExtension: stillExtension), asset("two", stillExtension: stillExtension)]
        let session = UUID()
        let result = try await BackupEngine().run(
            assets: assets, sessionID: session, destination: destination, folderLayout: layout
        ) { request, _ in
            try writeOriginal(request, data: bytes(for: request.resource))
        }
        #expect(result.snapshot.phase == .completed)
        #expect(result.snapshot.completedAssets == 2)
        #expect(result.snapshot.verifiedResources == 6)
        #expect(Set(result.records.map(\.relativePath)).count == 6)
        for asset in assets {
            let records = result.records.filter { $0.assetID == asset.id }
            #expect(records.count == 3)
            let folders = records.map { (destination.appendingPathComponent($0.relativePath)).deletingLastPathComponent() }
            #expect(Set(folders).count == 1)
            for resource in asset.resources {
                let record = try #require(records.first { $0.resourceID == resource.id })
                #expect(try Data(contentsOf: destination.appendingPathComponent(record.relativePath)) == bytes(for: resource))
            }
        }
        let repeated = try await BackupEngine(previousRecords: result.records).run(
            assets: assets, sessionID: session, destination: destination, folderLayout: layout
        ) { _, _ in throw BackupTestError.unexpectedLoad }
        #expect(repeated.snapshot.phase == .completed)
        #expect(repeated.snapshot.transferredBytes == 0)
        #expect(repeated.snapshot.completedAssets == 2)
    }

    @Test(arguments: [BackupFolderLayout.byDevice, .byDeviceFlat], ["HEIC", "JPG"])
    func unavailableMotionRemainsIncompleteAndRetryCopiesOnlyMotion(
        layout: BackupFolderLayout, stillExtension: String
    ) async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let asset = asset("one", stillExtension: stillExtension)
        let session = UUID()
        let first = try await BackupEngine().run(
            assets: [asset], sessionID: session, destination: destination, folderLayout: layout
        ) { request, _ in
            if request.resource.id == "one-motion" { throw MediaSourceError.missingResource }
            return try writeOriginal(request, data: bytes(for: request.resource))
        }
        #expect(first.snapshot.phase == .failed)
        #expect(first.snapshot.completedAssets == 0)
        #expect(Set(first.records.map(\.resourceID)) == ["one-photo", "one-adjustment"])
        #expect(first.snapshot.unavailableOriginals.map(\.id) == ["one-motion"])
        let loaded = BackupRecorder()
        let retry = try await BackupEngine(previousRecords: first.records).run(
            assets: [asset], sessionID: session, destination: destination, folderLayout: layout
        ) { request, _ in
            await loaded.loaded(request.resource.id)
            return try writeOriginal(request, data: bytes(for: request.resource))
        }
        #expect(await loaded.loadedIDs == ["one-motion"])
        #expect(retry.snapshot.phase == .completed)
        #expect(retry.snapshot.completedAssets == 1)
        #expect(retry.snapshot.verifiedResources == 3)
        #expect(retry.snapshot.transferredBytes == 5)
        #expect(first.records.allSatisfy { retry.records.contains($0) })
    }

    private func asset(_ id: String, stillExtension: String) -> MediaAsset {
        MediaAsset(id: id, deviceID: "phone", resources: [
            MediaResource(id: id + "-photo", filename: "IMG_0001." + stillExtension, byteCount: 3),
            MediaResource(id: id + "-motion", filename: "IMG_0001.MOV", byteCount: 5),
            MediaResource(id: id + "-adjustment", filename: "IMG_0001.AAE", byteCount: 7)
        ], kind: .livePhoto, createdAt: Date(timeIntervalSince1970: 1_789_214_400))
    }

    private func bytes(for resource: MediaResource) -> Data {
        // Distinct opaque payloads prove preservation; these are not playable media fixtures.
        Data(repeating: resource.id.hasPrefix("one") ? 0x31 : 0x72, count: Int(resource.byteCount))
    }
}
