import BackupEngine
import BackupPersistence
import Foundation
import Observation

@MainActor @Observable
final class BackupSessionCheckController {
    enum Phase { case preparing, checking, completed, stopped, failed }
    private(set) var phase = Phase.preparing
    private(set) var progress = SavedBackupCheckProgress(totalFiles: 0)
    private(set) var errorMessage: String?
    private(set) var isStopping = false
    @ObservationIgnored private var operation: Task<SavedBackupCheckProgress, Error>?
    @ObservationIgnored private let activity: BackupActivity

    init(activity: BackupActivity = .system) { self.activity = activity }

    var isRunning: Bool { phase == .preparing || phase == .checking }

    func run(
        session: StoredBackupSession, selectedDestinationID: UUID,
        destination: BackupDestinationStore, persistence: LibraryBackupPersistence
    ) async {
        guard operation == nil else { return }
        phase = .preparing
        progress = SavedBackupCheckProgress(totalFiles: 0)
        errorMessage = nil
        isStopping = false
        let task = Task { try await activity.perform(reason: "Checking saved iPhone originals") {
            guard destination.selection?.id == selectedDestinationID else { throw BackupDestinationError.selectionChanged }
            let lease = try await destination.acquireLease(readOnly: true)
            defer { lease.release() }
            guard lease.destinationID == selectedDestinationID else { throw BackupDestinationError.selectionChanged }
            try Task.checkCancellation()
            let records = try await persistence.store().savedFiles(sessionID: session.id, destinationID: session.destinationID)
            try Task.checkCancellation()
            phase = .checking
            return try await SavedBackupCheck.run(destination: lease.url, records: records) { [weak controller = self] update in
                await controller?.updateProgress(update)
            }
        } }
        operation = task
        defer { operation = nil; isStopping = false }
        do {
            let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            progress = result
            phase = .completed
        } catch is CancellationError {
            phase = .stopped
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The saved files couldn’t be checked. Try again."
            phase = .failed
        }
    }

    func stop() {
        guard let operation else { return }
        isStopping = true
        operation.cancel()
    }

    private func updateProgress(_ update: SavedBackupCheckProgress) {
        guard !isStopping else { return }
        progress = update
    }
}
