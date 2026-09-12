import Foundation
import MediaCatalog
import MediaModels
import Testing

@Suite("Conservative thumbnail reuse identity")
struct ThumbnailReuseIndexTests {
    @Test func uniqueMetadataProducesDeterministicDigest() throws {
        let records = [record("first"), record("second", filename: "OTHER.HEIC")]
        let index = ThumbnailReuseIndex.make(records: records)
        #expect(index.count == 2)
        #expect(index == ThumbnailReuseIndex.make(records: records.reversed()))
        let digest = try #require(index["first"])
        #expect(digest.count == 64)
        #expect(digest.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func sessionResourceAndPairIDsNeverEnterDigest() throws {
        let first = record("session-one", sidecars: ["old-sidecar"], pairedRaw: "old-raw")
        let second = record("session-two", sidecars: ["new-sidecar"], pairedRaw: "new-raw")
        let expected = try #require(ThumbnailReuseIndex.make(records: [first])[first.id])
        #expect(ThumbnailReuseIndex.make(records: [second])[second.id] == expected)
    }

    @Test func duplicateMetadataExcludesEveryAmbiguousCandidate() {
        let records = [record("first"), record("second"), record("unique", filename: "OTHER.HEIC")]
        let index = ThumbnailReuseIndex.make(records: records)
        #expect(Set(index.keys) == ["unique"])
        #expect(ThumbnailReuseIndex.make(records: [record("same"), record("same")]).isEmpty)
    }

    @Test func duplicateResourceIDsRemainAmbiguousEvenWithDifferentMetadata() {
        #expect(ThumbnailReuseIndex.make(records: [
            record("same"), record("same", filename: "OTHER.HEIC")
        ]).isEmpty)
    }

    @Test func changedMetadataAndDifferentDevicesDoNotReuseDigest() throws {
        let expected = try #require(ThumbnailReuseIndex.make(records: [record("baseline")])["baseline"])
        let changes = [
            record("changed", deviceID: "another-phone"),
            record("changed", filename: "OTHER.HEIC"),
            record("changed", originalFilename: "ORIGINAL.HEIC"),
            record("changed", context: ["DCIM", "101APPLE"]),
            record("changed", byteCount: 201),
            record("changed", createdAt: Date(timeIntervalSince1970: 1_700_000_001)),
            record("changed", modifiedAt: Date(timeIntervalSince1970: 1_700_000_002)),
            record("changed", uti: "public.jpeg"),
            record("changed", origin: "another-origin"),
            record("changed", width: 4001),
            record("changed", height: 3001),
            record("changed", duration: 2)
        ]
        for changed in changes {
            let digest = try #require(ThumbnailReuseIndex.make(records: [changed])[changed.id])
            #expect(digest != expected)
        }
    }

    @Test func structuredPathsDoNotCollideAtSeparators() throws {
        let nested = record("nested", context: ["DCIM", "100APPLE"])
        let flat = record("flat", context: ["DCIM/100APPLE"])
        let index = ThumbnailReuseIndex.make(records: [nested, flat])
        #expect(index.count == 2)
        let nestedDigest = try #require(index[nested.id])
        let flatDigest = try #require(index[flat.id])
        #expect(nestedDigest != flatDigest)
    }

    @Test func missingRequiredEvidenceNeverProducesEligibility() {
        let records = [
            record(""),
            record("device", deviceID: " \n"),
            record("filename", filename: ""),
            record("uti", uti: nil),
            record("blank-uti", uti: " \n"),
            record("bytes", byteCount: 0),
            record("date", createdAt: nil),
            record("path-and-origin", context: [], origin: nil),
            record("blank-path-and-origin", context: [" \n"], origin: " \n")
        ]
        #expect(ThumbnailReuseIndex.make(records: records).isEmpty)
    }

    @Test func originCanSupplyContextButNeitherIsInvented() {
        let byOrigin = record("origin", context: [], origin: "asset-origin")
        let byPath = record("path", origin: nil)
        let index = ThumbnailReuseIndex.make(records: [byOrigin, byPath])
        #expect(Set(index.keys) == ["origin", "path"])
    }

    @Test func nonfiniteDatesAreRejected() {
        let records = [
            record("created", createdAt: Date(timeIntervalSince1970: .infinity)),
            record("modified", modifiedAt: Date(timeIntervalSince1970: .nan))
        ]
        #expect(ThumbnailReuseIndex.make(records: records).isEmpty)
    }

    @Test func decodedNonfiniteDurationIsRejected() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(record("duration", duration: 2))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["duration"] = "NaN"
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        let decoded = try decoder.decode(SourceMediaRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(ThumbnailReuseIndex.make(records: [decoded]).isEmpty)
    }

    private func record(
        _ id: String, deviceID: String = "persistent-phone", filename: String = "IMG.HEIC",
        originalFilename: String? = nil, context: [String] = ["DCIM", "100APPLE"],
        uti: String? = "public.heic", byteCount: Int64 = 200,
        createdAt: Date? = Date(timeIntervalSince1970: 1_700_000_000), modifiedAt: Date? = nil,
        origin: String? = "asset-origin", width: Int? = 4000, height: Int? = 3000,
        duration: Double? = nil, sidecars: [String] = [], pairedRaw: String? = nil
    ) -> SourceMediaRecord {
        SourceMediaRecord(
            id: id, deviceID: deviceID, filename: filename, originalFilename: originalFilename,
            contextPath: context, uti: uti, byteCount: byteCount, createdAt: createdAt, modifiedAt: modifiedAt,
            pixelWidth: width, pixelHeight: height, duration: duration, originatingAssetID: origin,
            sidecarIDs: sidecars, pairedRawID: pairedRaw
        )
    }
}
