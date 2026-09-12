import Foundation
import ImageCaptureCore
import MediaModels
import Testing
@testable import DeviceCapture

@Suite("Camera catalog accumulation", .timeLimit(.minutes(1)))
@MainActor
struct CameraCatalogTests {
    @Test("Rapid incremental batches accumulate before replaceable snapshots are emitted")
    func incrementalBatchesDoNotDropFiles() async throws {
        let harness = CatalogHarness()
        let files = (0..<1_024).map { CatalogTestFile(name: "IMG_\($0).HEIC") }
        harness.begin()
        for offset in stride(from: 0, to: files.count, by: 32) {
            harness.catalog.add(
                Array(files[offset..<offset + 32]), sessionID: harness.sessionID,
                percent: 67, iCloudPhotosEnabled: true
            )
        }
        let snapshot = try await harness.next { $0.records.count == files.count }
        #expect(snapshot.state == .scanning)
        #expect(snapshot.percentComplete == 67)
        #expect(snapshot.iCloudPhotosEnabled == true)
        #expect(Set(snapshot.records.map(\.filename)).count == files.count)
        #expect(Set(snapshot.records.map(\.id)).count == files.count)
    }

    @Test("Complete traversal includes explicit sidecars and RAW, deduplicating repeated object references")
    func companionsAndReconciliation() async throws {
        let harness = CatalogHarness()
        let image = CatalogTestFile(name: "IMG_1.HEIC")
        let movie = CatalogTestFile(name: "IMG_1.MOV")
        let raw = CatalogTestFile(name: "IMG_1.DNG")
        let obsolete = CatalogTestFile(name: "REMOVED.JPG")
        image.companions = [movie, movie, raw]
        image.rawCompanion = raw
        movie.companions = [image]
        harness.begin()
        harness.catalog.add([obsolete], sessionID: harness.sessionID, percent: 5, iCloudPhotosEnabled: false)
        harness.catalog.complete(
            [image, movie, image], sessionID: harness.sessionID, percent: 92, iCloudPhotosEnabled: false
        )
        let snapshot = try await harness.next { $0.state == .complete }
        #expect(snapshot.records.count == 3)
        #expect(snapshot.percentComplete == 92) // Do not invent 100 from a distinct readiness event.
        let imageRecord = try #require(snapshot.records.first { $0.filename == image.name })
        let movieRecord = try #require(snapshot.records.first { $0.filename == movie.name })
        let rawRecord = try #require(snapshot.records.first { $0.filename == raw.name })
        #expect(Set(imageRecord.sidecarIDs) == [movieRecord.id, rawRecord.id])
        #expect(imageRecord.pairedRawID == rawRecord.id)
        #expect(try harness.catalog.file(for: imageRecord.id, sessionID: harness.sessionID) === image)
    }

    @Test("Incremental removal and rename preserve surviving object identity")
    func removalAndRename() async throws {
        let harness = CatalogHarness()
        let first = CatalogTestFile(name: "SAME.JPG")
        let second = CatalogTestFile(name: "SAME.JPG")
        harness.begin()
        harness.catalog.complete([first, second], sessionID: harness.sessionID, percent: 100, iCloudPhotosEnabled: nil)
        let before = try await harness.next { $0.state == .complete }
        let firstID = try #require(before.records.first {
            (try? harness.catalog.file(for: $0.id, sessionID: harness.sessionID)) === first
        }?.id)
        let secondID = try #require(before.records.first { $0.id != firstID }?.id)
        first.suppliedName = "RENAMED.JPG"
        harness.catalog.add([first], sessionID: harness.sessionID, percent: 100, iCloudPhotosEnabled: nil)
        harness.catalog.remove([second], sessionID: harness.sessionID, percent: 100, iCloudPhotosEnabled: nil)
        let after = try await harness.next { $0.revision > before.revision }
        #expect(after.records.count == 1)
        #expect(after.records.first?.id == firstID)
        #expect(after.records.first?.filename == "RENAMED.JPG")
        #expect(throws: MediaSourceError.missingResource) {
            try harness.catalog.file(for: secondID, sessionID: harness.sessionID)
        }
    }

    @Test("Removed folders remove descendants while identical names in other folders remain")
    func folderRemoval() async throws {
        let harness = CatalogHarness()
        let firstFolder = CatalogTestFolder(name: "100APPLE")
        let secondFolder = CatalogTestFolder(name: "101APPLE")
        let first = CatalogTestFile(name: "SAME.JPG")
        let second = CatalogTestFile(name: "SAME.JPG")
        first.folder = firstFolder
        second.folder = secondFolder
        firstFolder.items = [first]
        secondFolder.items = [second]
        harness.begin()
        harness.catalog.complete([firstFolder, secondFolder], sessionID: harness.sessionID, percent: 100, iCloudPhotosEnabled: nil)
        let before = try await harness.next { $0.state == .complete }
        firstFolder.items = [] // Removal cannot depend on framework retaining the removed folder's contents.
        harness.catalog.remove([firstFolder], sessionID: harness.sessionID, percent: 100, iCloudPhotosEnabled: nil)
        let after = try await harness.next { $0.revision > before.revision }
        #expect(after.records.count == 1)
        #expect(after.records.first?.contextPath == ["101APPLE"])
    }

    @Test("Interruption retains visible values but invalidates all framework handles and later callbacks")
    func interruptedCatalog() async throws {
        let harness = CatalogHarness()
        harness.begin()
        harness.catalog.complete([CatalogTestFile(name: "ONE.JPG")], sessionID: harness.sessionID,
                                 percent: 100, iCloudPhotosEnabled: true)
        let before = try await harness.next { $0.state == .complete }
        harness.catalog.interrupt(sessionID: harness.sessionID)
        harness.catalog.add([CatalogTestFile(name: "LATE.JPG")], sessionID: harness.sessionID,
                            percent: 100, iCloudPhotosEnabled: true)
        let after = try await harness.next { $0.state == .interrupted }
        #expect(after.records == before.records)
        #expect(after.revision > before.revision)
        #expect(throws: MediaSourceError.staleSession) {
            try harness.catalog.file(for: before.records[0].id, sessionID: harness.sessionID)
        }
    }

    @Test("A new session cancels yielding work and rejects stale completion events")
    func replacedSessionRejectsOldWork() async throws {
        let harness = CatalogHarness()
        harness.begin()
        harness.catalog.add((0..<2_000).map { CatalogTestFile(name: "OLD_\($0).JPG") },
                            sessionID: harness.sessionID, percent: 45, iCloudPhotosEnabled: false)
        await Task.yield()
        let replacement = UUID()
        harness.catalog.begin(sessionID: replacement, deviceID: "other-phone", percent: 0, iCloudPhotosEnabled: true)
        harness.catalog.complete([CatalogTestFile(name: "STALE.JPG")], sessionID: harness.sessionID,
                                 percent: 100, iCloudPhotosEnabled: false)
        harness.catalog.complete([CatalogTestFile(name: "NEW.JPG")], sessionID: replacement,
                                 percent: 100, iCloudPhotosEnabled: true)
        let snapshot = try await harness.next { $0.sessionID == replacement && $0.state == .complete }
        #expect(snapshot.records.map(\.filename) == ["NEW.JPG"])
        #expect(snapshot.deviceID == "other-phone")
        #expect(snapshot.records.allSatisfy { $0.id.hasPrefix(replacement.uuidString) })
    }
}

@MainActor
private final class CatalogHarness {
    let sessionID = UUID()
    let catalog: CameraCatalog
    private let stream: AsyncStream<DeviceMediaSnapshot>

    init() {
        let stream = AsyncStream<DeviceMediaSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.stream = stream.stream
        catalog = CameraCatalog { stream.continuation.yield($0) }
    }

    func begin() {
        catalog.begin(sessionID: sessionID, deviceID: "phone", percent: 0, iCloudPhotosEnabled: nil)
    }

    func next(where predicate: (DeviceMediaSnapshot) -> Bool) async throws -> DeviceMediaSnapshot {
        for await snapshot in stream where predicate(snapshot) { return snapshot }
        throw MediaSourceError.unavailable
    }
}

final class CatalogTestFile: ICCameraFile {
    var suppliedName: String?
    var companions: [ICCameraItem] = []
    var rawCompanion: ICCameraFile?
    weak var folder: ICCameraFolder?

    init(name: String?) {
        suppliedName = name
        super.init()
    }

    override var name: String? { suppliedName }
    override var parentFolder: ICCameraFolder? { folder }
    override var sidecarFiles: [ICCameraItem]? { companions }
    override var pairedRawImage: ICCameraFile? { rawCompanion }
    override var uti: String? { "public.image" }
    override var fileSize: off_t { 123 }
}

private final class CatalogTestFolder: ICCameraFolder {
    let suppliedName: String
    var items: [ICCameraItem] = []

    init(name: String) {
        suppliedName = name
        super.init()
    }

    override var name: String? { suppliedName }
    override var contents: [ICCameraItem]? { items }
}
