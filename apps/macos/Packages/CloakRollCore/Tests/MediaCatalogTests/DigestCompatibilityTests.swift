import CryptoKit
import Foundation
import MediaCatalog
import MediaModels
import Testing

@Suite("Catalog digest storage compatibility")
struct DigestCompatibilityTests {
    @Test func preoptimizationPersistentKeysAndThumbnailKeysRemainExact() throws {
        let fixture = fixture()
        let identity = try BackupIdentityIndex.make(
            source: fixture.source, assets: [fixture.asset], deviceIdentity: fixture.device
        )
        let asset = try #require(identity.assets[fixture.asset.id])
        // Captured from the unchanged implementation before replacing hexadecimal formatting.
        #expect(asset.digest == "a8507de1f17c7b4ae3dae3c032f66ddb696dee4d7fb6a8f57ea4c073ae31f198")
        #expect(asset.resources["first-1-still"]?.digest == "046e539bedebd979e57579bcac093fecd1e5101e2c990cc6287e12ffa95004b7")
        #expect(ThumbnailReuseIndex.make(records: fixture.source.records)["first-1-still"] ==
                "55689152b50235f610244adfe464398f5164a7a9981114a070e2758c85463f42")
    }

    @Test(arguments: [false, true])
    func unicodeAndCompanionIdentitiesKeepLegacyDigestBytes(sessionOnly: Bool) throws {
        let device = DeviceIdentity(kind: sessionOnly ? .sessionOnly : .persistent, value: "digest-fixture")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let still = SourceMediaRecord(
            id: "still", deviceID: device.key, filename: "Cafe\u{301} 📷.HEIC", contextPath: ["DCIM", "日本語"],
            uti: "public.heic", byteCount: 200, createdAt: date, modifiedAt: date, sidecarIDs: ["motion"]
        )
        let motion = SourceMediaRecord(
            id: "motion", deviceID: device.key, filename: "Café 📷.MOV", contextPath: ["DCIM", "日本語"],
            uti: "com.apple.quicktime-movie", byteCount: 300, createdAt: date, modifiedAt: date, duration: 3
        )
        let records = [still, motion]
        let identity = try BackupIdentityIndex.make(
            source: DeviceMediaSnapshot(sessionID: UUID(), deviceID: device.key, revision: 1, records: records, state: .complete),
            assets: CatalogAssembler.assemble(records: records), deviceIdentity: device
        )
        #expect(identity.assets.count == 1)
        for asset in identity.assets.values {
            #expect(asset.isReusableAcrossConnections == !sessionOnly)
            #expect(asset.digest == legacyDigest(asset.canonical))
            #expect(asset.resources.count == 2)
            for resource in asset.resources.values { #expect(resource.digest == legacyDigest(resource.canonical)) }
        }
    }

    private func legacyDigest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func fixture() -> (device: DeviceIdentity, source: DeviceMediaSnapshot, asset: MediaAsset) {
        let device = DeviceIdentity(kind: .persistent, value: "generated-scale-device")
        let date = Date(timeIntervalSince1970: 1_700_000_061)
        let record = SourceMediaRecord(
            id: "first-1-still", deviceID: device.key, filename: "IMG_0000001.HEIC", contextPath: ["DCIM", "100APPLE"],
            uti: "public.heic", byteCount: 4_000_000, createdAt: date, modifiedAt: date,
            pixelWidth: 4032, pixelHeight: 3024, originatingAssetID: "generated-1"
        )
        let asset = MediaAsset(
            id: "first-1", deviceID: device.key,
            resources: [MediaResource(id: record.id, filename: record.filename, byteCount: record.byteCount, modifiedAt: date)],
            kind: .photo, createdAt: date, pixelWidth: 4032, pixelHeight: 3024
        )
        let source = DeviceMediaSnapshot(sessionID: UUID(), deviceID: device.key, revision: 1, records: [record], state: .complete)
        return (device, source, asset)
    }
}
