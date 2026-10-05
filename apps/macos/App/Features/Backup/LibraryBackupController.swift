import AppKit
import BackupEngine
import BackupPersistence
import MediaModels
import Observation

@MainActor @Observable
final class LibraryBackupController {
    enum StopReason: Equatable { case user, sourceUnavailable }

    struct Attempt {
        let assets: [MediaAsset]
        let sessionID: UUID

        func matches(sessionID: UUID?, currentAsset: (String) -> MediaAsset?) -> Bool {
            self.sessionID == sessionID && assets.allSatisfy { currentAsset($0.id) == $0 }
        }
    }

    let destination: BackupDestinationStore
    let persistence: LibraryBackupPersistence?
    private(set) var snapshot: BackupSnapshot?
    let recovery = BackupFolderRecoveryController()
    private(set) var isBackingUp = false
    var isBusy: Bool { isBackingUp || recovery.isRunning }
    var recoveryContext: PreparedBackupContext? {
        guard !isBusy, !isCheckingHistory, pendingCatalog?.source.state == .complete,
              context?.identity.sessionID == pendingCatalog?.source.sessionID else { return nil }
        return context
    }
    private(set) var isStopping = false
    private(set) var stopReason: StopReason?
    private(set) var wasInterrupted = false
    private(set) var lastAttempt: Attempt?
    private(set) var isCheckingHistory = false
    private(set) var historyErrorMessage: String?
    var errorMessage: String?
    @ObservationIgnored var onStatusesChanged: (() -> Void)?
    @ObservationIgnored private var history = LibraryBackupHistory()
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var engine: BackupEngine?
    @ObservationIgnored private var historyTask: Task<Void, Never>?
    @ObservationIgnored private var historyGeneration = 0
    @ObservationIgnored private var context: PreparedBackupContext?
    @ObservationIgnored private var pendingCatalog: PendingBackupCatalog?
    @ObservationIgnored private var needsHistoryCheck = false

    init(destination: BackupDestinationStore = BackupDestinationStore(), persistence: LibraryBackupPersistence? = nil) {
        self.destination = destination
        self.persistence = persistence
    }

    func chooseDestination() async {
        guard !isBusy, !destination.isChoosing else { return }
        let previous = destination.selection?.id
        let didChoose = await destination.chooseFolder()
        if destination.selection?.id != previous {
            snapshot = nil
            lastAttempt = nil
            stopReason = nil
            wasInterrupted = false
            history = LibraryBackupHistory()
            onStatusesChanged?()
        }
        takeDestinationError()
        if didChoose { retryHistoryCheck() }
    }

    func start(
        assets: [MediaAsset], sessionID: UUID, folderLayout: BackupFolderLayout = .byDevice,
        download: @escaping BackupEngine.Download
    ) {
        guard !isBusy, !isCheckingHistory, historyErrorMessage == nil,
              !destination.isChoosing, !assets.isEmpty else { return }
        if persistence != nil {
            guard pendingCatalog?.source.state == .complete, context?.identity.sessionID == sessionID,
                  !needsHistoryCheck else { return }
        }
        isBackingUp = true
        isStopping = false
        stopReason = nil
        wasInterrupted = false
        errorMessage = nil
        lastAttempt = Attempt(assets: assets, sessionID: sessionID)
        snapshot = BackupSnapshot(phase: .preparing, totalAssets: assets.count)
        // Capture the organization before any folder picker or lease awaits. One run uses one layout.
        runTask = Task { await perform(assets: assets, sessionID: sessionID, folderLayout: folderLayout, download: download) }
    }

    func cancel() {
        requestStop(reason: .user)
    }

    func sourceBecameUnavailable() {
        requestStop(reason: .sourceUnavailable)
    }

    private func requestStop(reason: StopReason) {
        if recovery.isRunning { recovery.stop(); return }
        guard isBackingUp, !isStopping else { return }
        stopReason = reason
        isStopping = true
        runTask?.cancel()
        if let engine { Task { await engine.cancel() } }
    }

    /// The destination lease stays owned until the source's physical callback has settled.
    func waitUntilStopped() async {
        await runTask?.value
        await recovery.waitUntilStopped()
    }

    func dismissSummary() {
        guard !isBusy else { return }
        snapshot = nil
        stopReason = nil
        wasInterrupted = false
    }

    func revealDestination() async {
        do {
            let lease = try await destination.acquireLease()
            defer { lease.release() }
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: lease.url.path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func projection(assets: [MediaAsset], sessionID: UUID?) -> (statuses: [String: BackupStatus], dates: [String: Date]) {
        guard let sessionID, let destinationID = destination.selection?.id else { return ([:], [:]) }
        return history.projection(assets: assets, scope: .init(sessionID: sessionID, destinationID: destinationID))
    }

    private func perform(
        assets: [MediaAsset], sessionID: UUID, folderLayout: BackupFolderLayout, download: @escaping BackupEngine.Download
    ) async {
        defer {
            engine = nil
            isBackingUp = false
            isStopping = false
            runTask = nil
            if needsHistoryCheck { retryHistoryCheck() }
        }
        do {
            if destination.selection == nil {
                guard await destination.chooseFolder() else {
                    snapshot = nil
                    takeDestinationError()
                    return
                }
                onStatusesChanged?()
            }
            try Task.checkCancellation()
            let lease = try await destination.acquireLease()
            defer { lease.release() }
            try Task.checkCancellation()
            let scope = LibraryBackupHistory.Scope(sessionID: sessionID, destinationID: lease.destinationID)
            let journal = try await beginJournal(assets: assets, sessionID: sessionID, destinationID: lease.destinationID)
            let engine = BackupEngine(previousRecords: history.records(in: scope))
            self.engine = engine
            let monitor = Task { [weak self] in
                for await value in engine.snapshots {
                    guard !Task.isCancelled else { return }
                    if value.phase != .idle { self?.snapshot = value }
                }
            }
            defer { monitor.cancel() }
            var result = try await engine.run(
                assets: assets, sessionID: sessionID, destination: lease.url, folderLayout: folderLayout,
                onStaged: { intent in
                    if let journal { try await journal.store.recordStaging(sessionID: journal.id, intent: intent) }
                },
                onPublication: { intent in
                    if let journal {
                        try await BackupPortableEvidence.save(store: journal.store, sessionID: journal.id,
                                                              record: intent.verifiedRecord, destination: lease.url)
                        try await journal.store.recordPublication(sessionID: journal.id, intent: intent)
                    }
                },
                onVerified: { record in
                    if let journal {
                        try await BackupPortableEvidence.save(store: journal.store, sessionID: journal.id,
                                                              record: record, destination: lease.url)
                        try await journal.store.recordVerified(sessionID: journal.id, record: record)
                    }
                }, download: download
            )
            monitor.cancel()
            result = BackupResult(snapshot: terminalSnapshot(result.snapshot), records: result.records)
            if let journal {
                do {
                    let terminal = result.snapshot
                    try await Task { try await journal.store.finishSession(id: journal.id, result: terminal) }.value
                } catch {
                    wasInterrupted = false
                    var terminal = result.snapshot
                    terminal.phase = .failed
                    terminal.message = "Backup history couldn’t be finalized. Try again to check saved originals and finish the backup."
                    result = BackupResult(snapshot: terminal, records: result.records)
                }
            }
            snapshot = result.snapshot
            history.apply(result, assets: assets, scope: scope)
            onStatusesChanged?()
            if let persistence { try? await Task { try await persistence.refreshSessions() }.value }
        } catch is CancellationError {
            snapshot = terminalSnapshot(BackupSnapshot(phase: .cancelled, totalAssets: assets.count))
        } catch {
            snapshot = BackupSnapshot(phase: .failed, totalAssets: assets.count, message: error.localizedDescription)
        }
    }

    private func terminalSnapshot(_ value: BackupSnapshot) -> BackupSnapshot {
        guard value.phase == .cancelled, stopReason == .sourceUnavailable else { return value }
        wasInterrupted = true
        var result = value
        result.phase = .failed
        result.message = "The iPhone became unavailable during the backup."
        return result
    }

    private func takeDestinationError() {
        if let message = destination.errorMessage { errorMessage = message }
        destination.clearError()
    }

    private func beginJournal(assets: [MediaAsset], sessionID: UUID, destinationID: UUID) async throws -> BackupJournalSession? {
        guard let persistence else { return nil }
        guard let context, context.identity.sessionID == sessionID else { throw LibraryHistoryError.libraryChanged }
        let validation = Task.detached(priority: .utility) {
            for asset in assets {
                try Task.checkCancellation()
                guard context.lookup[asset.id] == asset else { throw LibraryHistoryError.libraryChanged }
            }
        }
        try await withTaskCancellationHandler {
            try await validation.value
        } onCancel: { validation.cancel() }
        let store = try await persistence.store()
        let id = try await store.beginSession(
            device: context.device, destinationID: destinationID, sourceSessionID: sessionID,
            assets: assets, identity: context.identity
        )
        return BackupJournalSession(id: id, store: store)
    }

    func acceptCatalog(source: DeviceMediaSnapshot, assets: [MediaAsset], device: ConnectedDevice?) {
        guard persistence != nil else { return }
        if pendingCatalog?.source.sessionID != source.sessionID { history = LibraryBackupHistory() }
        pendingCatalog = device.map { PendingBackupCatalog(source: source, assets: assets, device: $0) }
        needsHistoryCheck = true
        guard !isBusy else { return }
        retryHistoryCheck()
    }

    func suspendHistory(resetSource: Bool = false) {
        historyGeneration += 1
        historyTask?.cancel()
        historyTask = nil
        isCheckingHistory = false
        if resetSource {
            pendingCatalog = nil
            context = nil
            historyErrorMessage = nil
            needsHistoryCheck = false
        }
    }

    func retryHistoryCheck() {
        guard let persistence, !isBusy else { return }
        suspendHistory()
        guard let pending = pendingCatalog, pending.source.state == .complete else { return }
        let generation = historyGeneration
        isCheckingHistory = true
        historyErrorMessage = nil
        needsHistoryCheck = false
        historyTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if historyGeneration == generation {
                    isCheckingHistory = false
                    historyTask = nil
                }
            }
            do {
                try await restorePreviousDestination(for: pending.device)
                let prepared = try await LibraryBackupPersistence.prepare(
                    source: pending.source, assets: pending.assets, device: pending.device,
                    previousIdentity: context?.identity
                )
                try Task.checkCancellation()
                guard historyGeneration == generation else { return }
                if let destinationID = destination.selection?.id {
                    history.retainAssets(prepared.retainedAssetIDs, in: .init(
                        sessionID: pending.source.sessionID, destinationID: destinationID
                    ))
                }
                context = prepared
                onStatusesChanged?()
                if destination.selection != nil {
                    let lease = try await destination.acquireLease()
                    defer { lease.release() }
                    let result = try await persistence.verifyHistory(context: prepared, lease: lease)
                    try Task.checkCancellation()
                    guard historyGeneration == generation else { return }
                    history.apply(result, assets: pending.assets, scope: .init(
                        sessionID: pending.source.sessionID, destinationID: lease.destinationID
                    ))
                }
                onStatusesChanged?()
                try await persistence.refreshSessions()
            } catch is CancellationError {
                // An obsolete catalog or destination may never replace the current projection.
            } catch {
                if historyGeneration == generation {
                    historyErrorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "Backup history couldn’t be checked. Try again or choose the folder again."
                }
            }
        }
    }
}

private struct PendingBackupCatalog {
    let source: DeviceMediaSnapshot
    let assets: [MediaAsset]
    let device: ConnectedDevice
}

private struct BackupJournalSession: Sendable {
    let id: UUID
    let store: BackupStore
}

private enum LibraryHistoryError: LocalizedError {
    case libraryChanged
    var errorDescription: String? { "The iPhone library changed. Wait for it to finish loading, then try again." }
}
