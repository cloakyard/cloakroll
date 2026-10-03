import BackupEngine
import BackupPersistence
import Foundation
import MediaCatalog
import MediaModels
import Observation

struct PreparedBackupContext: Sendable {
    let device: ConnectedDevice
    let assets: [MediaAsset]
    let identity: BackupCatalogIdentity
    let lookup: [String: MediaAsset]
    let retainedAssetIDs: Set<String>
}

/// Coordinates persistent evidence, while the package owns SQL and safe local file verification.
@MainActor @Observable
final class LibraryBackupPersistence {
    private(set) var recentSessions: [StoredBackupSession] = []
    @ObservationIgnored private let databaseURL: URL
    @ObservationIgnored private var opening: Task<BackupStore, Error>?
    @ObservationIgnored private var refreshGeneration = 0

    init(databaseURL: URL) { self.databaseURL = databaseURL }

    static func appDefault() -> LibraryBackupPersistence? {
        if ProcessInfo.processInfo.environment["CLOAKROLL_TESTING"] == "1" { return nil }
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return LibraryBackupPersistence(databaseURL: support
            .appendingPathComponent("CloakRoll", isDirectory: true).appendingPathComponent("Backups.sqlite"))
    }

    func store() async throws -> BackupStore {
        if let opening { return try await opening.value }
        let url = databaseURL
        let task = Task { try await BackupStore(databaseURL: url) }
        opening = task
        do { return try await task.value } catch {
            opening = nil
            throw error
        }
    }

    func refreshSessions() async throws {
        refreshGeneration += 1
        let generation = refreshGeneration
        let store = try await store()
        let sessions = try await store.recentSessions(limit: 10)
        try Task.checkCancellation()
        if refreshGeneration == generation { recentSessions = sessions }
    }

    nonisolated static func prepare(
        source: DeviceMediaSnapshot, assets: [MediaAsset], device: ConnectedDevice,
        previousIdentity: BackupCatalogIdentity? = nil
    ) async throws -> PreparedBackupContext {
        let task = Task.detached(priority: .userInitiated) {
            let identity = try BackupIdentityIndex.make(source: source, assets: assets, deviceIdentity: device.identity)
            var retained: Set<String> = []
            if let previousIdentity, previousIdentity.sessionID == identity.sessionID,
               previousIdentity.deviceKey == identity.deviceKey {
                for (id, asset) in identity.assets {
                    try Task.checkCancellation()
                    if previousIdentity.assets[id] == asset { retained.insert(id) }
                }
            }
            return PreparedBackupContext(
                device: device, assets: assets, identity: identity,
                lookup: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) }), retainedAssetIDs: retained
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    func verifyHistory(context: PreparedBackupContext, lease: DestinationLease) async throws -> BackupResult {
        let store = try await store()
        try await recoverPublishedOriginals(store: store, lease: lease)
        let candidates = try await store.candidates(
            deviceKey: context.identity.deviceKey, destinationID: lease.destinationID, identity: context.identity
        )
        let assets = context.assets
        let sessionID = context.identity.sessionID
        let rebaseTask = Task.detached(priority: .utility) {
            let lookup = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
            return try candidates.compactMap { candidate -> VerifiedBackupResource? in
                try Task.checkCancellation()
                guard let asset = lookup[candidate.assetID],
                      let resource = asset.resources.first(where: { $0.id == candidate.resourceID }) else { return nil }
                return try BackupEngine.rebase(candidate.record, asset: asset, resource: resource, sessionID: sessionID)
            }
        }
        let rebased = try await withTaskCancellationHandler {
            try await rebaseTask.value
        } onCancel: { rebaseTask.cancel() }
        try Task.checkCancellation()
        return try await BackupVerification.validateExisting(
            assets: assets, sessionID: sessionID, destination: lease.url, records: rebased
        )
    }

    private func recoverPublishedOriginals(store: BackupStore, lease: DestinationLease) async throws {
        let entries = try await store.pendingJournal(destinationID: lease.destinationID)
        for entry in entries {
            try Task.checkCancellation()
            guard let intent = entry.publication else { continue }
            let recovery = try await BackupRecovery.inspect(destination: lease.url, intent: intent)
            guard case .published(let record) = recovery else { continue }
            try Task.checkCancellation()
            // A proved published original owns this transaction through completion. The caller's
            // destination lease remains open even if its catalog check is cancelled meanwhile.
            try await Task {
                try await store.reconcilePublication(sessionID: entry.sessionID, intent: intent, record: record)
            }.value
        }
    }
}
