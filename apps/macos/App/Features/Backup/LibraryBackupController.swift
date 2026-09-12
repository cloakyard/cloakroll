import AppKit
import BackupEngine
import MediaModels
import Observation

@MainActor @Observable
final class LibraryBackupController {
    struct Attempt {
        let assets: [MediaAsset]
        let sessionID: UUID
    }

    let destination: BackupDestinationStore
    private(set) var snapshot: BackupSnapshot?
    private(set) var isBusy = false
    private(set) var isStopping = false
    private(set) var lastAttempt: Attempt?
    var errorMessage: String?
    @ObservationIgnored var onStatusesChanged: (() -> Void)?
    @ObservationIgnored private var history = LibraryBackupHistory()
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var engine: BackupEngine?

    init(destination: BackupDestinationStore = BackupDestinationStore()) {
        self.destination = destination
    }

    func chooseDestination() async {
        guard !isBusy, !destination.isChoosing else { return }
        let previous = destination.selection?.id
        await destination.chooseFolder()
        if destination.selection?.id != previous {
            snapshot = nil
            lastAttempt = nil
            onStatusesChanged?()
        }
        takeDestinationError()
    }

    func start(assets: [MediaAsset], sessionID: UUID, download: @escaping BackupEngine.Download) {
        guard !isBusy, !destination.isChoosing, !assets.isEmpty else { return }
        isBusy = true
        isStopping = false
        errorMessage = nil
        lastAttempt = Attempt(assets: assets, sessionID: sessionID)
        snapshot = BackupSnapshot(phase: .preparing, totalAssets: assets.count)
        runTask = Task { await perform(assets: assets, sessionID: sessionID, download: download) }
    }

    func cancel() {
        guard isBusy else { return }
        isStopping = true
        runTask?.cancel()
        if let engine { Task { await engine.cancel() } }
    }

    /// The destination lease stays owned until the source's physical callback has settled.
    func waitUntilStopped() async { await runTask?.value }

    func dismissSummary() {
        guard !isBusy else { return }
        snapshot = nil
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

    private func perform(assets: [MediaAsset], sessionID: UUID, download: @escaping BackupEngine.Download) async {
        defer {
            engine = nil
            isBusy = false
            isStopping = false
            runTask = nil
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
            let engine = BackupEngine(previousRecords: history.records(in: scope))
            self.engine = engine
            let monitor = Task { [weak self] in
                for await value in engine.snapshots {
                    guard !Task.isCancelled else { return }
                    if value.phase != .idle { self?.snapshot = value }
                }
            }
            defer { monitor.cancel() }
            let result = try await engine.run(assets: assets, sessionID: sessionID, destination: lease.url, download: download)
            snapshot = result.snapshot
            history.apply(result, assets: assets, scope: scope)
            onStatusesChanged?()
        } catch is CancellationError {
            snapshot = BackupSnapshot(phase: .cancelled, totalAssets: assets.count)
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
        }
    }

    private func takeDestinationError() {
        if let message = destination.errorMessage { errorMessage = message }
        destination.clearError()
    }
}
