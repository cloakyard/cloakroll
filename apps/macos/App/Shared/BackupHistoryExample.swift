#if DEBUG
import BackupEngine
import BackupPersistence
import MediaCatalog
import MediaModels
import SwiftUI

/// Isolated, temporary history for native paging review. Never writes to app history,
/// accesses a destination, or starts a transfer. The database is removed after closing.
struct BackupHistoryExample: View {
    @State private var persistence: LibraryBackupPersistence?
    @State private var failure: String?
    @State private var directory: URL?

    var body: some View {
        Group {
            if let persistence {
                BackupHistoryList(persistence: persistence) { _ in }
                    .toolbar {
                        BackupHistoryFilters(persistence: persistence)
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await persistence.loadSessions() } }
                            .disabled(persistence.isLoadingSessions)
                    }
            } else if let failure {
                Text(failure).padding()
            } else {
                ProgressView("Preparing sample history…")
            }
        }
        .frame(minWidth: 580, minHeight: 360)
        .task { await prepare() }
        .onDisappear {
            persistence = nil
            if let directory { try? FileManager.default.removeItem(at: directory) }
            directory = nil
        }
    }

    private func prepare() async {
        guard persistence == nil else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CloakRollHistoryPreview-" + UUID().uuidString)
        directory = root
        do {
            let history = LibraryBackupPersistence(databaseURL: root.appendingPathComponent("Preview.sqlite"))
            let store = try await history.store()
            let sample = MockLibrary.make(count: 1)
            let source = DeviceMediaSnapshot(sessionID: UUID(), deviceID: sample.device.id, revision: 1, records: [], state: .complete)
            let context = try await LibraryBackupPersistence.prepare(source: source, assets: sample.assets, device: sample.device)
            let destination = UUID()
            for index in 1...205 {
                try Task.checkCancellation()
                let device = ConnectedDevice(id: sample.device.id, displayName: "Sample iPhone · Backup \(index)")
                let id = try await store.beginSession(device: device, destinationID: destination, sourceSessionID: source.sessionID,
                                                     assets: sample.assets, identity: context.identity)
                try await store.finishSession(id: id, result: BackupSnapshot(phase: .cancelled))
            }
            try await history.refreshSessions()
            try Task.checkCancellation()
            persistence = history
        } catch {
            if !(error is CancellationError) { failure = error.localizedDescription }
            try? FileManager.default.removeItem(at: root)
        }
    }
}
#endif
