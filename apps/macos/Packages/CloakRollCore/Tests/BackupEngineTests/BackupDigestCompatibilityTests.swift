import CryptoKit
import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Backup source digest compatibility")
struct BackupDigestCompatibilityTests {
    @Test func previouslyPersistedSourceSignatureRemainsExact() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_061)
        let resource = MediaResource(id: "first-1-still", filename: "IMG_0000001.HEIC", byteCount: 4_000_000, modifiedAt: date)
        let asset = MediaAsset(
            id: "first-1", deviceID: "persistent:generated-scale-device", resources: [resource], kind: .photo,
            createdAt: date, pixelWidth: 4032, pixelHeight: 3024
        )
        #expect(try BackupEngine.sourceSignature(asset: asset, resource: resource) ==
                "57dc7fc444508932ab969dbaf22095a5cfe6767cc3b199beb545a109248e3beb")
    }

    @Test func unicodeSourceAndEveryCompanionMatchTheLegacySignatureEncoding() throws {
        struct LegacySignature: Encodable { let asset: MediaAsset; let resource: MediaResource }
        let asset = backupAsset("Café 📷", resources: [
            MediaResource(id: "still", filename: "Cafe\u{301}.HEIC", byteCount: 200, modifiedAt: Date(timeIntervalSince1970: 123.5)),
            MediaResource(id: "motion", filename: "日本語.MOV", byteCount: 300)
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for resource in asset.resources {
            let data = try encoder.encode(LegacySignature(asset: asset, resource: resource))
            let legacy = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(try BackupEngine.sourceSignature(asset: asset, resource: resource) == legacy)
        }
    }
}
