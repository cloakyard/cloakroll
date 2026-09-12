import CryptoKit
import Foundation
import MediaModels

extension BackupEngine {
    /// Full current-session metadata signature. This is a scope check, not source-byte evidence
    /// and not a stable cross-connection identity by itself.
    public nonisolated static func sourceSignature(asset: MediaAsset, resource: MediaResource) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let value = BackupSourceSignature(asset: asset, resource: resource)
        return try SHA256.hash(data: encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    /// Rekeys a conservatively matched stored candidate to the current catalog. The caller must
    /// first prove unambiguous original identity; rebase neither matches identity nor verifies
    /// destination bytes. The result must pass fresh local verification before showing Backed Up.
    public nonisolated static func rebase(
        _ previous: VerifiedBackupResource, asset: MediaAsset, resource: MediaResource, sessionID: UUID
    ) throws -> VerifiedBackupResource {
        guard resource.byteCount > 0, previous.byteCount == resource.byteCount else { throw BackupEngineError.sourceSizeChanged }
        guard !asset.id.isEmpty, !asset.deviceID.isEmpty, !resource.id.isEmpty,
              asset.resources.filter({ $0.id == resource.id }) == [resource] else { throw BackupEngineError.invalidSelection }
        return try VerifiedBackupResource(
            assetID: asset.id, resourceID: resource.id, deviceID: asset.deviceID, sourceSessionID: sessionID,
            filename: resource.filename, relativePath: previous.relativePath, byteCount: previous.byteCount,
            sha256: previous.sha256, verifiedAt: previous.verifiedAt, sourceModifiedAt: resource.modifiedAt,
            destinationIdentity: previous.destinationIdentity, sourceMetadataSignature: sourceSignature(asset: asset, resource: resource)
        )
    }
}

private struct BackupSourceSignature: Encodable {
    let asset: MediaAsset
    let resource: MediaResource
}
