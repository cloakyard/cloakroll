import Foundation
import MediaModels
import Testing

@Suite("Device media value boundaries")
struct DeviceMediaModelsTests {
    @Test func malformedNumericMetadataDoesNotBecomeUsableDimensionsOrDuration() {
        let record = SourceMediaRecord(id: "resource", deviceID: "phone", filename: "IMG.MOV", byteCount: -10,
                                       pixelWidth: 0, pixelHeight: -100, duration: .nan)
        #expect(record.byteCount == 0)
        #expect(record.pixelWidth == nil)
        #expect(record.pixelHeight == nil)
        #expect(record.duration == nil)
    }

    @Test func metadataEvidenceSurvivesRoundTripWithoutFilenameIdentity() throws {
        let record = SourceMediaRecord(id: "session:resource", deviceID: "phone", filename: "IMG.HEIC",
                                       originalFilename: "Original.HEIC", contextPath: ["DCIM", "100APPLE"],
                                       uti: "public.heic", byteCount: 123, createdAt: Date(timeIntervalSince1970: 456),
                                       pixelWidth: 4_032, pixelHeight: 3_024, originatingAssetID: "origin",
                                       groupUUID: "group", relatedUUID: "related", burstUUID: "burst",
                                       sidecarIDs: ["motion", "adjustment"], pairedRawID: "raw")
        let decoded = try JSONDecoder().decode(SourceMediaRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
        #expect(decoded.id != decoded.filename)
    }

    @Test func scanPercentIsBoundedAndUnknownCoverageStaysUnknown() {
        let sessionID = UUID()
        let first = DeviceMediaSnapshot(sessionID: sessionID, deviceID: "phone", revision: 1, records: [],
                                         state: .scanning, percentComplete: -12)
        let complete = DeviceMediaSnapshot(sessionID: sessionID, deviceID: "phone", revision: 2, records: [],
                                            state: .complete, percentComplete: 200)
        #expect(first.percentComplete == 0)
        #expect(complete.percentComplete == 100)
        #expect(complete.iCloudPhotosEnabled == nil)
        #expect(first != complete)
    }

    @Test func explicitPrimaryResourceControlsThePreviewAndFilename() {
        let resources = [MediaResource(id: "raw", filename: "IMG.DNG", byteCount: 100),
                         MediaResource(id: "still", filename: "IMG.JPG", byteCount: 30)]
        let asset = MediaAsset(id: "asset", deviceID: "phone", resources: resources, kind: .raw,
                               createdAt: nil, primaryResourceID: "still")
        #expect(asset.primaryResource == resources[1])
        #expect(asset.filename == "IMG.JPG")
        #expect(asset.byteCount == 130)
    }
}
