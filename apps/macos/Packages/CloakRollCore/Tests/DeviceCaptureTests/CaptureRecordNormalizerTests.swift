import Foundation
import ImageCaptureCore
import Testing
@testable import DeviceCapture

@Suite("Camera metadata normalization")
@MainActor
struct CaptureRecordNormalizerTests {
    @Test("Supplied evidence is preserved without requesting metadata or using names as IDs")
    func suppliedEvidence() {
        let file = MetadataTestFile()
        let record = CaptureRecordNormalizer.record(for: file, id: "session:7", deviceID: "phone",
                                                    sidecarIDs: ["session:8"], pairedRawID: "session:9")
        #expect(record.id == "session:7")
        #expect(record.filename == "  IMG_é.DNG")
        #expect(record.originalFilename == "ORIGINAL.DNG")
        #expect(record.uti == "com.adobe.raw-image")
        #expect(record.isRaw)
        #expect(record.byteCount == 42_000)
        #expect(record.createdAt == Date(timeIntervalSince1970: 10))
        #expect(record.modifiedAt == Date(timeIntervalSince1970: 20))
        #expect(record.pixelWidth == 4_032)
        #expect(record.pixelHeight == 3_024)
        #expect(record.duration == 12.5)
        #expect(record.originatingAssetID == "asset")
        #expect(record.groupUUID == "group")
        #expect(record.relatedUUID == "related")
        #expect(record.burstUUID == "burst")
        #expect(record.sidecarIDs == ["session:8"])
        #expect(record.pairedRawID == "session:9")
    }

    @Test("Absent and invalid facts remain unknown instead of inventing metadata")
    func absentFacts() {
        let file = InvalidMetadataTestFile()
        let record = CaptureRecordNormalizer.record(for: file, id: "session:1", deviceID: "phone",
                                                    sidecarIDs: [], pairedRawID: nil)
        #expect(record.filename == "Unnamed resource")
        #expect(record.originalFilename == nil)
        #expect(record.uti == nil)
        #expect(record.byteCount == 0)
        #expect(record.pixelWidth == nil)
        #expect(record.pixelHeight == nil)
        #expect(record.duration == nil)
        #expect(record.groupUUID == nil)
        #expect(record.createdAt == nil)
    }
}

private final class MetadataTestFile: ICCameraFile {
    override var name: String? { "  IMG_é.DNG" }
    override var originalFilename: String? { "ORIGINAL.DNG" }
    override var uti: String? { "com.adobe.raw-image" }
    override var isRaw: Bool { true }
    override var fileSize: off_t { 42_000 }
    override var creationDate: Date? { Date(timeIntervalSince1970: 10) }
    override var modificationDate: Date? { Date(timeIntervalSince1970: 20) }
    override var width: Int { 4_032 }
    override var height: Int { 3_024 }
    override var duration: Double { 12.5 }
    override var originatingAssetID: String? { "asset" }
    override var groupUUID: String? { "group" }
    override var relatedUUID: String? { "related" }
    override var burstUUID: String? { "burst" }
}

private final class InvalidMetadataTestFile: ICCameraFile {
    override var name: String? { "  " }
    override var originalFilename: String? { nil }
    override var uti: String? { "" }
    override var fileSize: off_t { -1 }
    override var width: Int { 0 }
    override var height: Int { -1 }
    override var duration: Double { .infinity }
    override var groupUUID: String? { "\n" }
    override var creationDate: Date? { nil }
}
