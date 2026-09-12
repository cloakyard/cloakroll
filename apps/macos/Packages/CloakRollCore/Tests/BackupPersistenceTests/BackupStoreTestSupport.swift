import BackupEngine
import BackupPersistence
import CryptoKit
import Foundation
import GRDB
import MediaModels

struct HistoryFixture {
    let device: ConnectedDevice
    let sourceSessionID: UUID
    let destinationID: UUID
    let assets: [MediaAsset]

    init(
        deviceValue: String = "device-one", sessionID: UUID = UUID(), destinationID: UUID = UUID(),
        prefix: String = "old", motionBytes: Int64 = 5, persistent: Bool = true
    ) {
        device = ConnectedDevice(identity: DeviceIdentity(kind: persistent ? .persistent : .sessionOnly, value: deviceValue), name: "iPhone")
        sourceSessionID = sessionID
        self.destinationID = destinationID
        assets = [MediaAsset(
            id: "\(prefix)-asset", deviceID: device.id,
            resources: [
                MediaResource(id: "\(prefix)-still", filename: "IMG_0001.HEIC", byteCount: 3, modifiedAt: Date(timeIntervalSince1970: 100)),
                MediaResource(id: "\(prefix)-motion", filename: "IMG_0001.MOV", byteCount: motionBytes)
            ],
            kind: .livePhoto, createdAt: Date(timeIntervalSince1970: 100)
        )]
    }

    func identity(reusable: Bool = true) throws -> BackupCatalogIdentity {
        struct Component: Encodable { let filename: String; let byteCount: Int64; let modifiedAt: Date? }
        struct Asset: Encodable { let kind: MediaKind; let createdAt: Date?; let components: [Component] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let asset = assets[0]
        let value = Asset(kind: asset.kind, createdAt: asset.createdAt, components: asset.resources.map {
            Component(filename: $0.filename, byteCount: $0.byteCount, modifiedAt: $0.modifiedAt)
        })
        let canonical = String(decoding: try encoder.encode(value), as: UTF8.self)
        let digest = Self.digest(Data(canonical.utf8))
        var resources: [String: BackupResourceIdentity] = [:]
        for resource in asset.resources {
            let component = Component(filename: resource.filename, byteCount: resource.byteCount, modifiedAt: resource.modifiedAt)
            let resourceCanonical = digest + ":" + String(decoding: try encoder.encode(component), as: UTF8.self)
            resources[resource.id] = BackupResourceIdentity(
                resourceID: resource.id, canonical: resourceCanonical, digest: Self.digest(Data(resourceCanonical.utf8)),
                isReusableAcrossConnections: reusable
            )
        }
        return BackupCatalogIdentity(deviceKey: device.id, sessionID: sourceSessionID, assets: [asset.id: BackupAssetIdentity(
            assetID: asset.id, canonical: canonical, digest: digest, isReusableAcrossConnections: reusable, resources: resources
        )])
    }

    func begin(_ store: BackupStore, reusable: Bool = true) async throws -> UUID {
        try await store.beginSession(device: device, destinationID: destinationID, sourceSessionID: sourceSessionID,
                                     assets: assets, identity: identity(reusable: reusable))
    }

    func record(_ index: Int = 0, byte: UInt8 = 1, path: String? = nil) throws -> VerifiedBackupResource {
        let asset = assets[0]
        let resource = asset.resources[index]
        return VerifiedBackupResource(
            assetID: asset.id, resourceID: resource.id, deviceID: device.id, sourceSessionID: sourceSessionID,
            filename: resource.filename, relativePath: path ?? "2026/09/\(resource.filename)", byteCount: resource.byteCount,
            sha256: Self.digest(Data(repeating: byte, count: Int(resource.byteCount))), verifiedAt: Date(timeIntervalSince1970: 200),
            sourceModifiedAt: resource.modifiedAt, destinationIdentity: "local-device:local-inode",
            sourceMetadataSignature: try BackupEngine.sourceSignature(asset: asset, resource: resource)
        )
    }

    func candidates(_ store: BackupStore, reusable: Bool = true) async throws -> [StoredBackupCandidate] {
        try await store.candidates(deviceKey: device.id, destinationID: destinationID, identity: identity(reusable: reusable))
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

struct HistoryDirectory {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cloakroll-history-tests-\(UUID().uuidString)")
    var databaseURL: URL { url.appendingPathComponent("History.sqlite") }
    func remove() { try? FileManager.default.removeItem(at: url) }
    func database() throws -> DatabaseQueue { try DatabaseQueue(path: databaseURL.path) }
}
