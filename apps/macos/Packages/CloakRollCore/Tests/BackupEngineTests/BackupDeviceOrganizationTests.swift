import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Device-organized original backups")
struct BackupDeviceOrganizationTests {
    @Test func deviceFolderIsVersionedStableAndContainsNoRawDeviceKey() throws {
        let folder = try BackupFolderLayout.deviceFolderName(for: "persistent:fixture-phone")
        #expect(folder == "iPhone 14c48b46900c90b4083a3a28f96e96ff")
        #expect(try BackupFolderLayout.deviceFolderName(for: "persistent:Café")
                == BackupFolderLayout.deviceFolderName(for: "persistent:Cafe\u{301}"))
        let untrustedKey = "session:../../private\\phone\0"
        let safe = try BackupFolderLayout.deviceFolderName(for: untrustedKey)
        #expect(BackupDescriptor.isComponent(safe) && safe.utf8.count == 39)
        #expect(!safe.contains("private") && !safe.contains("session:"))
        #expect(throws: BackupEngineError.invalidSelection) { try BackupFolderLayout.deviceFolderName(for: "") }
    }

    @Test func identicalNamesFromDifferentPhonesHaveSeparateFoldersAndNeverReuseEachOthersEvidence() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = UUID()
        let firstAsset = asset(deviceID: "persistent:first")
        let secondAsset = asset(deviceID: "persistent:second")
        let first = try await BackupEngine(timeZone: .gmt).run(
            assets: [firstAsset], sessionID: session, destination: root, folderLayout: .byDevice
        ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        let second = try await BackupEngine(timeZone: .gmt, previousRecords: first.records).run(
            assets: [secondAsset], sessionID: session, destination: root, folderLayout: .byDevice
        ) { request, _ in try writeOriginal(request, data: Data([4, 5, 6])) }
        #expect(first.snapshot.phase == .completed && second.snapshot.phase == .completed)
        #expect(first.snapshot.transferredBytes == 3 && second.snapshot.transferredBytes == 3)
        let one = try #require(first.records.first)
        let two = try #require(second.records.first)
        #expect(one.relativePath == "\(try BackupFolderLayout.deviceFolderName(for: firstAsset.deviceID))/2026/09/IMG.HEIC")
        #expect(two.relativePath == "\(try BackupFolderLayout.deviceFolderName(for: secondAsset.deviceID))/2026/09/IMG.HEIC")
        #expect(one.relativePath != two.relativePath)
        #expect(try Data(contentsOf: root.appendingPathComponent(one.relativePath)) == Data([1, 2, 3]))
        #expect(try Data(contentsOf: root.appendingPathComponent(two.relativePath)) == Data([4, 5, 6]))

        let repeated = try await BackupEngine(previousRecords: first.records + second.records).run(
            assets: [firstAsset], sessionID: session, destination: root, folderLayout: .byDevice
        ) { _, _ in throw BackupTestError.unexpectedLoad }
        #expect(repeated.snapshot.phase == .completed && repeated.snapshot.transferredBytes == 0)
        #expect(repeated.records == first.records)

        // Removing one phone's local original invalidates only that phone's reuse evidence.
        try FileManager.default.removeItem(at: root.appendingPathComponent(one.relativePath))
        let restored = try await BackupEngine(previousRecords: first.records + second.records).run(
            assets: [firstAsset], sessionID: session, destination: root, folderLayout: .byDevice
        ) { request, _ in try writeOriginal(request, data: Data([7, 8, 9])) }
        #expect(restored.snapshot.phase == .completed && restored.snapshot.transferredBytes == 3)
        #expect(restored.records.first?.relativePath == one.relativePath)
        #expect(try Data(contentsOf: root.appendingPathComponent(two.relativePath)) == Data([4, 5, 6]))
    }

    @Test func enablingDeviceFoldersReusesLegacyOriginalsAndPlacesOnlyNewOriginalsInTheDeviceFolder() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = UUID()
        let oldAsset = asset(deviceID: "persistent:first")
        let legacy = try await BackupEngine(timeZone: .gmt).run(assets: [oldAsset], sessionID: session, destination: root) { request, _ in
            try writeOriginal(request, data: Data([1, 2, 3]))
        }
        let original = try #require(legacy.records.first)
        #expect(original.relativePath == "2026/09/IMG.HEIC")
        let addedAsset = asset(deviceID: oldAsset.deviceID, prefix: "added")
        let calls = BackupRecorder()
        let upgraded = try await BackupEngine(timeZone: .gmt, previousRecords: legacy.records).run(
            assets: [oldAsset, addedAsset], sessionID: session, destination: root, folderLayout: .byDevice
        ) { request, _ in
            await calls.loaded(request.resource.id)
            return try writeOriginal(request, data: Data([4, 5, 6]))
        }
        #expect(upgraded.snapshot.phase == .completed && upgraded.snapshot.transferredBytes == 3)
        #expect(upgraded.records.first == original)
        #expect(await calls.loadedIDs == [addedAsset.resources[0].id])
        #expect(upgraded.records.last?.relativePath.hasPrefix(try BackupFolderLayout.deviceFolderName(for: oldAsset.deviceID)) == true)
        #expect(try Data(contentsOf: root.appendingPathComponent(original.relativePath)) == Data([1, 2, 3]))
    }

    @Test(arguments: [BackupFolderLayout.byDate, .byDevice])
    func mixedDeviceSelectionsFailBeforeAnySourceOrFilesystemWork(layout: BackupFolderLayout) async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await BackupEngine().run(
            assets: [asset(deviceID: "first"), asset(deviceID: "second", prefix: "second")],
            sessionID: UUID(), destination: root, folderLayout: layout,
            onStaged: { _ in Issue.record("A mixed-device selection must not register staging") }
        ) { _, _ in throw BackupTestError.unexpectedLoad }
        #expect(result.snapshot.phase == .failed && result.records.isEmpty)
        #expect(result.snapshot.message == BackupEngineError.mixedDevices.errorDescription)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func publicationJournalRecoveryIncludesTheExactDeviceFolder() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = JournalCapture()
        let selected = asset(deviceID: "persistent:first")
        let result = try await BackupEngine().run(
            assets: [selected], sessionID: UUID(), destination: root, folderLayout: .byDevice,
            onPublication: { await capture.publication($0) },
            onVerified: { _ in throw BackupTestError.source }
        ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        #expect(result.snapshot.phase == .failed)
        let publication = try #require(await capture.publications.first)
        let record = try #require(result.records.first)
        #expect(publication.relativePath == record.relativePath)
        #expect(publication.relativePath.hasPrefix(try BackupFolderLayout.deviceFolderName(for: selected.deviceID) + "/"))
        #expect(try await BackupRecovery.inspect(destination: root, intent: publication) == .published(record))
    }

    @Test func aDeviceFolderSymlinkCannotRedirectOriginalPublication() async throws {
        let root = try backupDirectory()
        let outside = try backupDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let selected = asset(deviceID: "persistent:first")
        let folder = try BackupFolderLayout.deviceFolderName(for: selected.deviceID)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(folder), withDestinationURL: outside)
        let result = try await BackupEngine().run(
            assets: [selected], sessionID: UUID(), destination: root, folderLayout: .byDevice
        ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        #expect(result.snapshot.phase == .failed && result.records.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    private func asset(deviceID: String, prefix: String = "first") -> MediaAsset {
        MediaAsset(
            id: "\(prefix)-asset", deviceID: deviceID,
            resources: [MediaResource(id: "\(prefix)-resource", filename: "IMG.HEIC", byteCount: 3)],
            kind: .photo, createdAt: Date(timeIntervalSince1970: 1_789_214_400)
        )
    }
}
