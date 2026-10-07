import BackupPersistence
import SwiftUI

/// Keeps navigation outside the scrolling rows, including after an older page fails.
struct BackupHistoryList: View {
    let persistence: LibraryBackupPersistence
    let onCheck: (BackupSessionCheckRequest) -> Void

    var body: some View {
        List {
            if let message = persistence.sessionErrorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).foregroundStyle(.secondary)
                        Button("Try Again") { Task { await persistence.retrySessions() } }
                            .disabled(persistence.isLoadingSessions)
                    }
                }
            }
            Section {
                ForEach(persistence.recentSessions) { session in
                    BackupHistoryRow(session: session) { destination in
                        onCheck(BackupSessionCheckRequest(session: session, destination: destination))
                    }
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
            } header: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(persistence.sessionPageIndex == 0 ? "Latest Backups" : "Earlier Backups")
                        if persistence.sessionFilter != BackupHistoryFilter() {
                            Text(BackupHistoryFilters(persistence: persistence).summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                    if persistence.isLoadingSessions { ProgressView().controlSize(.small) }
                }
            }
            Text("""
            History shows what was verified during each backup.
            Expand a backup to check its saved originals at any time.
            """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .listRowSeparator(.hidden)
        }
        .listStyle(.inset)
        .id(persistence.sessionPageIndex)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if persistence.sessionPageIndex > 0 || persistence.hasOlderSessions {
                pagination
            }
        }
    }

    private var pagination: some View {
        HStack {
            Text("Page \(persistence.sessionPageIndex + 1)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            ControlGroup {
                Button {
                    Task { await persistence.loadNewerSessions() }
                } label: {
                    Label("Newer", systemImage: "chevron.left")
                }
                .disabled(persistence.sessionPageIndex == 0)
                .accessibilityLabel("Newer Backups")
                .help("Show newer backups")
                Button {
                    Task { await persistence.loadOlderSessions() }
                } label: {
                    Label("Older", systemImage: "chevron.right")
                }
                .disabled(!persistence.hasOlderSessions)
                .accessibilityLabel("Older Backups")
                .help("Show older backups")
            }
            .fixedSize()
            .disabled(persistence.isLoadingSessions)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
