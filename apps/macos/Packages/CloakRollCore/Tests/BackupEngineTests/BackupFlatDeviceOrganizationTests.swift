import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Flat device original folders")
struct BackupFlatDeviceOrganizationTests {
    @Test(arguments: [true, false])
    func allLivePhotoComponentsStayDirectlyInDeviceFolderIncludingUnknownDates(hasDate: Bool) async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = asset(createdAt: hasDate ? Self.date : nil, companion: true)
        let session = UUID()
        let result = try await BackupEngine(timeZone: .gmt).run(
            assets: [selected], sessionID: session, destination: root, folderLayout: .byDeviceFlat
        ) { request, _ in
            try writeOriginal(request, data: Data(repeating: 7, count: Int(request.resource.byteCount)))
        }
        #expect(result.snapshot.phase == .completed && result.snapshot.completedAssetIDs == [selected.id])
        #expect(result.snapshot.verifiedResources == 2 && result.snapshot.verifiedBytes == 5)
        let folder = try BackupFolderLayout.deviceFolderName(for: selected.deviceID)
        #expect(Set(result.records.map(\.relativePath)) == [folder + "/IMG.HEIC", folder + "/IMG.MOV"])
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path))
                == ["IMG.HEIC", "IMG.MOV"])
        for record in result.records {
            #expect(try Data(contentsOf: root.appendingPathComponent(record.relativePath))
                    == Data(repeating: 7, count: Int(record.byteCount)))
        }
        let verified = try await BackupVerification.validateExisting(
            assets: [selected], sessionID: session, destination: root, records: result.records
        )
        #expect(verified.snapshot.completedAssetIDs == [selected.id])
        #expect(verified.records == result.records)
    }

    @Test func flatteningRepeatedNamesAcrossDatesNeverOverwritesAnExistingFile() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = asset()
        let second = asset(id: "second", createdAt: Self.date.addingTimeInterval(90 * 86_400))
        let folder = try BackupFolderLayout.deviceFolderName(for: first.deviceID)
        let directory = root.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let sentinel = directory.appendingPathComponent("IMG.HEIC")
        try Data([9, 9, 9]).write(to: sentinel)
        let result = try await BackupEngine(timeZone: .gmt).run(
            assets: [first, second], sessionID: UUID(), destination: root, folderLayout: .byDeviceFlat
        ) { request, _ in
            let byte: UInt8 = request.resource.id == "first-still" ? 1 : 2
            return try writeOriginal(request, data: Data(repeating: byte, count: Int(request.resource.byteCount)))
        }
        #expect(result.snapshot.phase == .completed && result.snapshot.completedAssets == 2)
        #expect(result.records.map(\.relativePath) == [folder + "/IMG (1).HEIC", folder + "/IMG (2).HEIC"])
        #expect(try Data(contentsOf: sentinel) == Data([9, 9, 9]))
        #expect(try Data(contentsOf: directory.appendingPathComponent("IMG (1).HEIC")) == Data([1, 1, 1]))
        #expect(try Data(contentsOf: directory.appendingPathComponent("IMG (2).HEIC")) == Data([2, 2, 2]))
    }

    @Test(arguments: [BackupFolderLayout.byDate, .byDevice, .byDeviceFlat],
          [BackupFolderLayout.byDate, .byDevice, .byDeviceFlat])
    func changingLayoutReusesVerifiedPathsWithoutDownloadingOrMoving(
        previous: BackupFolderLayout, current: BackupFolderLayout
    ) async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = UUID()
        let selected = asset(companion: true)
        let original = try await BackupEngine(timeZone: .gmt).run(
            assets: [selected], sessionID: session, destination: root, folderLayout: previous
        ) { request, _ in
            try writeOriginal(request, data: Data(repeating: 4, count: Int(request.resource.byteCount)))
        }
        #expect(original.snapshot.phase == .completed)
        let before = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
        let repeated = try await BackupEngine(timeZone: .gmt, previousRecords: original.records).run(
            assets: [selected], sessionID: session, destination: root, folderLayout: current,
            onStaged: { _ in Issue.record("A verified existing path must not need new staging") }
        ) { _, _ in
            Issue.record("Changing organization must not copy a verified original again")
            throw BackupTestError.unexpectedLoad
        }
        #expect(repeated.snapshot.phase == .completed && repeated.snapshot.transferredBytes == 0)
        #expect(repeated.snapshot.completedAssetIDs == [selected.id] && repeated.records == original.records)
        #expect(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted() == before)
        for record in repeated.records {
            #expect(try Data(contentsOf: root.appendingPathComponent(record.relativePath))
                    == Data(repeating: 4, count: Int(record.byteCount)))
        }
    }

    @Test func changingToFlatLayoutPlacesOnlyNewOriginalsDirectlyInDeviceFolder() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = UUID()
        let first = asset()
        let added = asset(id: "added", createdAt: nil, companion: true)
        let original = try await BackupEngine(timeZone: .gmt).run(
            assets: [first], sessionID: session, destination: root, folderLayout: .byDevice
        ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        let recorder = BackupRecorder()
        let changed = try await BackupEngine(timeZone: .gmt, previousRecords: original.records).run(
            assets: [first, added], sessionID: session, destination: root, folderLayout: .byDeviceFlat
        ) { request, _ in
            await recorder.loaded(request.resource.id)
            return try writeOriginal(request, data: Data(repeating: 8, count: Int(request.resource.byteCount)))
        }
        let folder = try BackupFolderLayout.deviceFolderName(for: first.deviceID)
        #expect(changed.snapshot.phase == .completed && changed.snapshot.transferredBytes == 5)
        #expect(changed.records.first == original.records.first)
        #expect(await recorder.loadedIDs == added.resources.map(\.id))
        #expect(changed.records.dropFirst().map(\.relativePath) == [folder + "/IMG.HEIC", folder + "/IMG.MOV"])
        #expect(try Data(contentsOf: root.appendingPathComponent(folder + "/2026/09/IMG.HEIC")) == Data([1, 2, 3]))
    }

    private static let date = Date(timeIntervalSince1970: 1_789_214_400)

    private func asset(id: String = "first", createdAt: Date? = Self.date, companion: Bool = false) -> MediaAsset {
        var resources = [MediaResource(id: id + "-still", filename: "IMG.HEIC", byteCount: 3)]
        if companion { resources.append(MediaResource(id: id + "-motion", filename: "IMG.MOV", byteCount: 2)) }
        return MediaAsset(id: id, deviceID: "persistent:fixture-phone", resources: resources,
                          kind: companion ? .livePhoto : .photo, createdAt: createdAt)
    }
}
