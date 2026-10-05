import BackupPersistence
import Foundation
import Observation
import SwiftUI

/// Separate from the history screen's filters and bounded recent-session list.
@MainActor @Observable
final class DeviceBackupHistory {
    enum State: Equatable {
        case loading
        case loaded(StoredBackupSession?)
        case unavailable
    }

    private(set) var deviceKey: String?
    private(set) var state = State.loading
    @ObservationIgnored private var generation = 0

    func load(deviceKey: String, read: () async throws -> StoredBackupSession?) async {
        generation += 1
        let request = generation
        if self.deviceKey != deviceKey { state = .loading }
        self.deviceKey = deviceKey
        do {
            let session = try await read()
            try Task.checkCancellation()
            guard generation == request else { return }
            state = .loaded(session)
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            state = .unavailable
        }
    }

    func state(for deviceKey: String) -> State {
        self.deviceKey == deviceKey ? state : .loading
    }
}

struct DeviceBackupSummary: View {
    let deviceKey: String
    let persistence: LibraryBackupPersistence
    @State private var history = DeviceBackupHistory()

    private struct Request: Hashable {
        let deviceKey: String
        let revision: Int
    }

    var body: some View {
        Group {
            switch history.state(for: deviceKey) {
            case .loading:
                Text("Loading backup history…")
            case .unavailable:
                Text("Backup history unavailable")
                    .help("Open Backup History to try again.")
            case .loaded(nil):
                Text("No completed backups")
            case .loaded(let session?):
                completedBackup(session)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: Request(deviceKey: deviceKey, revision: persistence.sessionsRevision)) {
            await history.load(deviceKey: deviceKey) {
                try await persistence.store().lastCompletedSession(deviceKey: deviceKey)
            }
        }
    }

    private func completedBackup(_ session: StoredBackupSession) -> some View {
        let date = session.finishedAt ?? session.startedAt
        let count = session.completedAssets
        let items = "\(count.formatted()) \(count == 1 ? "item" : "items")"
        let size = Format.bytes(session.verifiedBytes)
        return VStack(alignment: .leading, spacing: 2) {
            Text("Last backup: \(date.formatted(.dateTime.day().month(.abbreviated).year()))")
            Text("\(items) · \(size)")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last completed backup \(date.formatted(date: .abbreviated, time: .shortened)), \(items), \(size).")
        .help("Last completed backup for this iPhone, across all folders: \(date.formatted(date: .abbreviated, time: .shortened)). "
              + "This records that backup session; it does not check whether the saved files are still available.")
    }
}
