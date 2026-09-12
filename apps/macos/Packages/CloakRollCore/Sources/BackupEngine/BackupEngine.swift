import CryptoKit
import Foundation
import MediaModels

/// Serial original transfers with a replaceable progress stream. The caller must keep its
/// destination security scope open until run returns, including the cancelling interval.
public actor BackupEngine {
    public typealias Download = @Sendable (
        BackupDownloadRequest, @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadedOriginal

    public nonisolated let snapshots: AsyncStream<BackupSnapshot>
    private let continuation: AsyncStream<BackupSnapshot>.Continuation
    private let timeZone: TimeZone
    private var worker: Task<BackupResult, Never>?
    private var state = BackupSnapshot()
    private var currentTransfer: UUID?
    private var records: [VerifiedBackupResource] = []
    private var history: [BackupEvidenceKey: VerifiedBackupResource] = [:]
    private var lastProgressPublication: ContinuousClock.Instant?

    public init(timeZone: TimeZone = .current, previousRecords: [VerifiedBackupResource] = []) {
        self.timeZone = timeZone
        let stream = AsyncStream.makeStream(of: BackupSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        snapshots = stream.stream
        continuation = stream.continuation
        continuation.yield(state)
        for record in previousRecords where !record.sourceMetadataSignature.isEmpty {
            history[BackupEvidenceKey(
                sessionID: record.sourceSessionID, deviceID: record.deviceID, assetID: record.assetID,
                resource: MediaResource(id: record.resourceID, filename: record.filename,
                                        byteCount: record.byteCount, modifiedAt: record.sourceModifiedAt),
                destinationIdentity: record.destinationIdentity, sourceMetadataSignature: record.sourceMetadataSignature
            )] = record
        }
    }

    /// Busy is rejected before starting. Once started, failures return a terminal result with
    /// every verified partial component retained; an incomplete asset is never marked complete.
    public func run(
        assets: [MediaAsset], sessionID: UUID, destination: URL, download: @escaping Download
    ) async throws -> BackupResult {
        guard worker == nil else { throw BackupEngineError.busy }
        let runID = UUID()
        state = BackupSnapshot(runID: runID, phase: .preparing, totalAssets: assets.count)
        records = []
        currentTransfer = nil
        publish()
        let task = Task { await execute(assets: assets, sessionID: sessionID, destination: destination, download: download) }
        worker = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
            Task { await self.markCancelling(runID: runID) }
        }
        if state.runID == runID { worker = nil }
        return result
    }

    public func cancel() {
        guard let worker else { return }
        markCancelling(runID: state.runID)
        worker.cancel()
    }

    private func markCancelling(runID: UUID?) {
        guard state.runID == runID, [.preparing, .downloading, .verifying].contains(state.phase) else { return }
        state.phase = .cancelling
        publish()
    }

    private func execute(
        assets: [MediaAsset], sessionID: UUID, destination: URL, download: @escaping Download
    ) async -> BackupResult {
        var store: BackupFileStore?
        do {
            try Task.checkCancellation()
            try validate(assets)
            guard let runID = state.runID else { throw BackupEngineError.invalidSelection }
            let timeZone = timeZone
            store = try await detached {
                try BackupFileStore(destination: destination, runID: runID, timeZone: timeZone)
            }
            guard let store else { throw BackupEngineError.invalidSelection }
            for asset in assets {
                for resource in asset.resources {
                    try Task.checkCancellation()
                    try await transfer(resource, asset: asset, sessionID: sessionID, store: store, download: download)
                }
                // Every original component has already been finalized and recorded at this point.
                state.completedAssetIDs.insert(asset.id)
                state.completedAssets = state.completedAssetIDs.count
                publish()
            }
            state.phase = .completed
            state.currentFilename = nil
            state.currentResourceBytes = 0
            state.currentResourceExpectedBytes = 0
        } catch is CancellationError {
            state.phase = .cancelled
            state.message = nil
        } catch {
            state.phase = Task.isCancelled ? .cancelled : .failed
            state.message = Task.isCancelled ? nil : (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        currentTransfer = nil
        if let store { await Task.detached(priority: .utility) { store.closeStaging() }.value }
        publish()
        return BackupResult(snapshot: state, records: records)
    }

    private func validate(_ assets: [MediaAsset]) throws {
        guard !assets.isEmpty, Set(assets.map(\.id)).count == assets.count else { throw BackupEngineError.invalidSelection }
        var identifiers: Set<String> = []
        var bytes: Int64 = 0
        var count = 0
        for asset in assets {
            guard !asset.id.isEmpty, !asset.deviceID.isEmpty, !asset.resources.isEmpty else { throw BackupEngineError.invalidSelection }
            for resource in asset.resources {
                guard !resource.id.isEmpty, identifiers.insert(resource.id).inserted else { throw BackupEngineError.invalidSelection }
                guard resource.byteCount > 0 else { throw BackupEngineError.invalidResourceSize }
                let total = bytes.addingReportingOverflow(resource.byteCount)
                guard !total.overflow else { throw BackupEngineError.invalidResourceSize }
                bytes = total.partialValue
                count += 1
            }
        }
        state.totalResources = count
        state.expectedBytes = bytes
        publish()
    }

    private func transfer(
        _ resource: MediaResource, asset: MediaAsset, sessionID: UUID, store: BackupFileStore, download: @escaping Download
    ) async throws {
        state.currentFilename = resource.filename
        state.currentResourceExpectedBytes = resource.byteCount
        state.currentResourceBytes = 0
        let evidenceKey = try BackupEvidenceKey(
            sessionID: sessionID, deviceID: asset.deviceID, assetID: asset.id, resource: resource,
            destinationIdentity: store.destinationIdentity, sourceMetadataSignature: Self.signature(asset: asset, resource: resource)
        )
        if let previous = history[evidenceKey] {
            state.phase = .verifying
            publish()
            let valid = try await detached {
                try store.verifyExisting(
                    relativePath: previous.relativePath, expectedByteCount: previous.byteCount, sha256: previous.sha256
                )
            }
            if valid {
                record(previous, evidenceKey: evidenceKey)
                return
            }
            history[evidenceKey] = nil
        }
        let staged = try await detached { try store.prepare(filename: resource.filename) }
        do {
            try Task.checkCancellation()
            let transferID = UUID()
            currentTransfer = transferID
            state.phase = .downloading
            publish()
            let request = BackupDownloadRequest(
                resource: resource, sessionID: sessionID, directory: staged.directory, filename: staged.filename
            )
            let result = try await download(request) { [weak self] progress in
                Task { await self?.receive(progress, transferID: transferID) }
            }
            // The source contract settles its physical callback before returning, even on cancellation.
            currentTransfer = nil
            try Task.checkCancellation()
            guard result.expectedByteCount == resource.byteCount, result.expectedByteCount > 0 else {
                throw BackupEngineError.sourceSizeChanged
            }
            state.transferredBytes += resource.byteCount - state.currentResourceBytes
            state.currentResourceBytes = resource.byteCount
            state.phase = .verifying
            publish()
            let finalized = try await detached {
                try store.verifyAndFinalize(
                    staged, returnedURL: result.url, expectedByteCount: resource.byteCount, createdAt: asset.createdAt
                )
            }
            let verified = VerifiedBackupResource(
                assetID: asset.id, resourceID: resource.id, deviceID: asset.deviceID, sourceSessionID: sessionID,
                filename: resource.filename, relativePath: finalized.relativePath, byteCount: finalized.byteCount,
                sha256: finalized.sha256, verifiedAt: Date(), sourceModifiedAt: resource.modifiedAt,
                destinationIdentity: store.destinationIdentity, sourceMetadataSignature: evidenceKey.sourceMetadataSignature
            )
            record(verified, evidenceKey: evidenceKey)
        } catch {
            currentTransfer = nil
            await Task.detached(priority: .utility) { store.discard(staged) }.value
            throw error
        }
    }

    private func record(_ verified: VerifiedBackupResource, evidenceKey: BackupEvidenceKey) {
        history[evidenceKey] = verified
        records.append(verified)
        state.verifiedResources += 1
        state.verifiedBytes += verified.byteCount
        publish()
    }

    private func receive(_ progress: DownloadProgress, transferID: UUID) {
        guard currentTransfer == transferID, state.phase == .downloading || state.phase == .cancelling else { return }
        let bytes = max(state.currentResourceBytes, min(state.currentResourceExpectedBytes, max(0, progress.downloadedBytes)))
        state.transferredBytes += bytes - state.currentResourceBytes
        state.currentResourceBytes = bytes
        let now = ContinuousClock.now
        if lastProgressPublication.map({ $0.duration(to: now) < .milliseconds(100) }) != true {
            lastProgressPublication = now
            publish()
        }
    }

    private func publish() { continuation.yield(state) }

    private static func signature(asset: MediaAsset, resource: MediaResource) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let value = BackupSourceSignature(asset: asset, resource: resource)
        return try SHA256.hash(data: encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    private func detached<Value: Sendable>(_ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        let task = Task.detached(priority: .utility, operation: operation)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

private struct BackupEvidenceKey: Hashable {
    let sessionID: UUID
    let deviceID: String
    let assetID: String
    let resource: MediaResource
    let destinationIdentity: String
    let sourceMetadataSignature: String
}

private struct BackupSourceSignature: Encodable {
    let asset: MediaAsset
    let resource: MediaResource
}
