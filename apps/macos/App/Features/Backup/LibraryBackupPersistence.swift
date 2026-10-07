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
    typealias SessionReader = @Sendable (BackupHistoryFilter, BackupHistoryCursor?) async throws -> BackupHistoryPage

    private(set) var sessionFilter = BackupHistoryFilter()
    private(set) var historyDevices: [BackupHistoryDevice] = []
    private(set) var recentSessions: [StoredBackupSession] = []
    private(set) var isLoadingSessions = false
    private(set) var sessionErrorMessage: String?
    private(set) var hasLoadedSessions = false
    private(set) var sessionsRevision = 0
    var sessionPageIndex: Int { sessionCursors.count }
    var hasOlderSessions: Bool { nextSessionCursor != nil }
    private var sessionCursors: [BackupHistoryCursor] = []
    private var nextSessionCursor: BackupHistoryCursor?
    @ObservationIgnored private var failedSessionRequest: [BackupHistoryCursor]?
    @ObservationIgnored private let databaseURL: URL
    @ObservationIgnored private let readSessions: SessionReader?
    @ObservationIgnored private var opening: Task<BackupStore, Error>?
    @ObservationIgnored private var refreshGeneration = 0

    init(databaseURL: URL, readSessions: SessionReader? = nil) {
        self.databaseURL = databaseURL
        self.readSessions = readSessions
    }

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

    /// Explicit refresh and completed backup updates return to the latest matching page.
    func refreshSessions() async throws {
        try await loadSessionPage(cursors: [])
    }

    private func loadSessionPage(cursors: [BackupHistoryCursor]) async throws {
        refreshGeneration += 1
        let generation = refreshGeneration
        let filter = sessionFilter
        isLoadingSessions = true
        sessionErrorMessage = nil
        failedSessionRequest = nil
        defer { if refreshGeneration == generation { isLoadingSessions = false } }
        do {
            let page: BackupHistoryPage
            let devices: [BackupHistoryDevice]
            if let readSessions {
                page = try await readSessions(filter, cursors.last)
                devices = historyDevices
            } else {
                let store = try await store()
                page = try await store.sessionPage(filter: filter, after: cursors.last)
                devices = try await store.historyDevices()
            }
            try Task.checkCancellation()
            guard refreshGeneration == generation else { return }
            // A running session can leave an outcome filter between requests. Avoid an
            // empty, stranded older page; reload the latest matching results instead.
            if page.sessions.isEmpty, !cursors.isEmpty {
                try await refreshSessions()
                return
            }
            recentSessions = page.sessions
            sessionCursors = cursors
            nextSessionCursor = page.nextCursor
            historyDevices = devices
            hasLoadedSessions = true
            sessionsRevision += 1
        } catch {
            if refreshGeneration == generation, !(error is CancellationError) {
                failedSessionRequest = cursors
                sessionErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Backup history couldn’t be loaded. Try again."
            }
            throw error
        }
    }

    func applySessionFilter(_ filter: BackupHistoryFilter) async {
        guard filter != sessionFilter else { return }
        sessionFilter = filter
        // Old rows must not be displayed under a newly selected filter, including after a failure.
        recentSessions = []
        sessionCursors = []
        nextSessionCursor = nil
        hasLoadedSessions = false
        do { try await refreshSessions() } catch { /* Keep the current filter and expose retry. */ }
    }

    /// Opens history independently of iPhone discovery. Concurrent initial loads share the
    /// latest refresh; a failed request retains the last successfully loaded sessions.
    func loadSessions() async {
        guard !isLoadingSessions else { return }
        do { try await refreshSessions() } catch { /* The observable error keeps retry available. */ }
    }

    func loadOlderSessions() async {
        guard !isLoadingSessions, let nextSessionCursor else { return }
        await navigateSessions(cursors: sessionCursors + [nextSessionCursor])
    }

    func loadNewerSessions() async {
        guard !isLoadingSessions, !sessionCursors.isEmpty else { return }
        await navigateSessions(cursors: Array(sessionCursors.dropLast()))
    }

    func retrySessions() async {
        guard !isLoadingSessions else { return }
        await navigateSessions(cursors: failedSessionRequest ?? [])
    }

    private func navigateSessions(cursors: [BackupHistoryCursor]) async {
        do { try await loadSessionPage(cursors: cursors) } catch { /* Retain the last good page and retry target. */ }
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
                try await BackupPortableEvidence.save(store: store, sessionID: entry.sessionID, record: record, destination: lease.url)
                try await store.reconcilePublication(sessionID: entry.sessionID, intent: intent, record: record)
            }.value
        }
    }
}
