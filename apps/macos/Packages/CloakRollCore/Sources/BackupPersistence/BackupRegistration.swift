import BackupEngine
import CryptoKit
import Foundation
import MediaModels

struct BackupRegistration: Sendable {
    struct Component: Sendable {
        let assetID: String
        let asset: BackupAssetIdentity
        let resource: MediaResource
        let identity: BackupResourceIdentity
        let sourceSignature: String
    }

    let device: ConnectedDevice
    let sourceSessionID: UUID
    let assetCount: Int
    let expectedBytes: Int64
    let components: [Component]

    init(
        device: ConnectedDevice, sourceSessionID: UUID, assets: [MediaAsset], identity: BackupCatalogIdentity,
        checkCancellation: () throws -> Void = { try Task.checkCancellation() }
    ) throws {
        try checkCancellation()
        guard !device.id.isEmpty, identity.deviceKey == device.id, identity.sessionID == sourceSessionID,
              !assets.isEmpty else { throw BackupStoreError.invalidIdentity }
        var reusableIdentities: Set<String> = []
        for assetIdentity in identity.assets.values {
            try checkCancellation()
            if assetIdentity.isReusableAcrossConnections,
               !reusableIdentities.insert(assetIdentity.canonical).inserted { throw BackupStoreError.invalidIdentity }
        }
        var components: [Component] = []
        var assetIDs: Set<String> = []
        var resourceIDs: Set<String> = []
        var bytes: Int64 = 0
        for asset in assets {
            try checkCancellation()
            guard assetIDs.insert(asset.id).inserted, asset.deviceID == device.id, !asset.resources.isEmpty,
                  let assetIdentity = identity.assets[asset.id], assetIdentity.assetID == asset.id,
                  assetIdentity.resources.count == asset.resources.count,
                  Self.valid(canonical: assetIdentity.canonical, digest: assetIdentity.digest),
                  !assetIdentity.isReusableAcrossConnections || device.identity?.isPersistent == true else {
                throw BackupStoreError.invalidIdentity
            }
            for resource in asset.resources {
                try checkCancellation()
                guard resource.byteCount > 0, resourceIDs.insert(resource.id).inserted,
                      let resourceIdentity = assetIdentity.resources[resource.id], resourceIdentity.resourceID == resource.id,
                      Self.valid(canonical: resourceIdentity.canonical, digest: resourceIdentity.digest),
                      !resourceIdentity.isReusableAcrossConnections || assetIdentity.isReusableAcrossConnections else {
                    throw BackupStoreError.invalidIdentity
                }
                let total = bytes.addingReportingOverflow(resource.byteCount)
                guard !total.overflow else { throw BackupStoreError.invalidIdentity }
                bytes = total.partialValue
                components.append(Component(
                    assetID: asset.id, asset: assetIdentity, resource: resource, identity: resourceIdentity,
                    sourceSignature: try BackupEngine.sourceSignature(asset: asset, resource: resource)
                ))
            }
        }
        try checkCancellation()
        self.device = device
        self.sourceSessionID = sourceSessionID
        self.assetCount = assets.count
        self.expectedBytes = bytes
        self.components = components
    }

    static func valid(canonical: String, digest: String) -> Bool {
        !canonical.isEmpty && HexEncoding.lowercase(SHA256.hash(data: Data(canonical.utf8))) == digest
    }
}
