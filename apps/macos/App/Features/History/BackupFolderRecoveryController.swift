import BackupEngine
import BackupPersistence
import Foundation
import Observation

@MainActor @Observable
final class BackupFolderRecoveryController {
    enum Mode: String, CaseIterable, Identifiable {
        case indexed, usb
        var id: Self { self }
    }
    enum Phase { case idle, preparing, checking, verifying, saving, completed, stopped, failed }
    private(set) var phase = Phase.idle
    private(set) var checked = 0
    private(set) var total = 0
    private(set) var recovered = 0
    private(set) var unavailable = 0
    private(set) var verified = 0
    private(set) var errorMessage: String?
    private(set) var isStopping = false
    @ObservationIgnored private var operation: Task<Int, Error>?

    var isRunning: Bool { [.preparing, .checking, .verifying, .saving].contains(phase) }

    func run(mode: Mode, selectedDestinationID: UUID, destination: BackupDestinationStore,
             persistence: LibraryBackupPersistence, context: PreparedBackupContext?, download: BackupEngine.Download?) async {
        guard operation == nil else { return }
        phase = .preparing
        checked = 0
        total = 0
        recovered = 0
        unavailable = 0
        verified = 0
        errorMessage = nil
        isStopping = false
        let task = Task {
            guard destination.selection?.id == selectedDestinationID else { throw BackupDestinationError.selectionChanged }
            let lease = try await destination.acquireLease()
            defer { lease.release() }
            guard lease.destinationID == selectedDestinationID else { throw BackupDestinationError.selectionChanged }
            try Task.checkCancellation()
            let store = try await persistence.store()
            let root = try await detached { try BackupRecoveryIndex.destinationIdentity(lease.url) }
            let old = try await store.recoveryEntries(destinationIdentity: root)
            _ = try await detached { try BackupRecoveryIndex.prepare(entries: old, destination: lease.url) }
            phase = .checking
            let update: @Sendable (Int, Int) -> Void = { [weak controller = self] checked, total in
                if checked == 1 || checked == total || checked.isMultiple(of: 16) {
                    Task { @MainActor in controller?.update(checked: checked, total: total) }
                }
            }
            var scan = try await detached { try BackupRecoveryIndex.scan(destination: lease.url, progress: update) }
            if mode == .usb {
                guard let context, let download else { throw BackupRecoveryError.libraryChanged }
                phase = .verifying
                checked = 0
                total = 0
                let previous = scan
                _ = try await detached {
                    try await BackupLegacyRecovery.run(assets: context.assets, device: context.device, identity: context.identity,
                                                       destination: lease.url, existing: previous, progress: update, download: download)
                }
                phase = .checking
                checked = 0
                total = 0
                scan = try await detached { try BackupRecoveryIndex.scan(destination: lease.url, progress: update) }
            }
            try Task.checkCancellation()
            verified = scan.entries.count
            unavailable = scan.unavailable + scan.invalid + scan.ambiguous
            phase = .saving
            // No cancellation check after commit: a successful import must never be reported as
            // rolled back just because Stop or sheet dismissal raced with the transaction's return.
            return try await store.importRecovery(scan, destinationID: lease.destinationID)
        }
        operation = task
        defer { operation = nil; isStopping = false }
        do {
            recovered = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            phase = .completed
        } catch is CancellationError { phase = .stopped } catch {
            phase = .failed
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "History couldn’t be rebuilt. Your originals have been preserved."
        }
        try? await persistence.refreshSessions()
    }

    func stop() {
        guard isRunning, phase != .saving else { return }
        isStopping = true
        operation?.cancel()
    }

    func waitUntilStopped() async { _ = try? await operation?.value }

    func reset() {
        guard !isRunning else { return }
        phase = .idle
        errorMessage = nil
    }

    private func update(checked: Int, total: Int) {
        guard isRunning, !isStopping, phase != .saving else { return }
        self.checked = checked
        self.total = total
    }

    private func detached<Value: Sendable>(_ work: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let task = Task.detached(priority: .utility, operation: work)
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
