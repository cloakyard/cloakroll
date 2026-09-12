import Foundation
import MediaModels

public enum BackupVerification {
    /// Reads local destination bytes only; never downloads or creates staging. Candidates must
    /// already be conservatively matched and rebased to the current source session. A completed
    /// scan can have zero complete assets. Only completedAssetIDs establishes complete evidence.
    /// Keep destination access open until this method returns, including cancellation cleanup.
    public static func validateExisting(
        assets: [MediaAsset], sessionID: UUID, destination: URL, records: [VerifiedBackupResource]
    ) async throws -> BackupResult {
        let task = Task.detached(priority: .utility) {
            try validate(assets: assets, sessionID: sessionID, destination: destination, records: records)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func validate(
        assets: [MediaAsset], sessionID: UUID, destination: URL, records: [VerifiedBackupResource]
    ) throws -> BackupResult {
        try Task.checkCancellation()
        guard Set(assets.map(\.id)).count == assets.count else { throw BackupEngineError.invalidSelection }
        let resourceIDs = assets.flatMap { $0.resources.map(\.id) }
        guard Set(resourceIDs).count == resourceIDs.count else { throw BackupEngineError.invalidSelection }
        let files = try BackupReadOnlyFiles(destination: destination)
        let candidates = Dictionary(grouping: records, by: BackupEvidenceKey.init(record:))
        var state = BackupSnapshot(phase: .completed, totalAssets: assets.count, totalResources: resourceIDs.count)
        var verified: [VerifiedBackupResource] = []
        for asset in assets {
            var complete = !asset.id.isEmpty && !asset.deviceID.isEmpty && !asset.resources.isEmpty
            for resource in asset.resources {
                try Task.checkCancellation()
                let total = state.expectedBytes.addingReportingOverflow(max(0, resource.byteCount))
                guard !total.overflow else { throw BackupEngineError.invalidResourceSize }
                state.expectedBytes = total.partialValue
                let key = try BackupEvidenceKey(
                    sessionID: sessionID, deviceID: asset.deviceID, assetID: asset.id, resource: resource,
                    destinationIdentity: files.destinationIdentity,
                    sourceMetadataSignature: BackupEngine.sourceSignature(asset: asset, resource: resource)
                )
                guard !resource.id.isEmpty, resource.byteCount > 0,
                      let matches = candidates[key], matches.count == 1, let candidate = matches.first,
                      try files.verifyExisting(
                        relativePath: candidate.relativePath, expectedByteCount: candidate.byteCount, sha256: candidate.sha256
                      ) else {
                    complete = false
                    continue
                }
                verified.append(candidate)
                state.verifiedResources += 1
                state.verifiedBytes += candidate.byteCount
            }
            if complete { state.completedAssetIDs.insert(asset.id) }
        }
        try Task.checkCancellation()
        state.completedAssets = state.completedAssetIDs.count
        return BackupResult(snapshot: state, records: verified)
    }
}

extension BackupEvidenceKey {
    init(record: VerifiedBackupResource) {
        self.init(
            sessionID: record.sourceSessionID, deviceID: record.deviceID, assetID: record.assetID,
            resource: MediaResource(id: record.resourceID, filename: record.filename,
                                    byteCount: record.byteCount, modifiedAt: record.sourceModifiedAt),
            destinationIdentity: record.destinationIdentity, sourceMetadataSignature: record.sourceMetadataSignature
        )
    }
}
