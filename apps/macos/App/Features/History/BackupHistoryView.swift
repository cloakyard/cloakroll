import BackupPersistence
import SwiftUI

struct BackupHistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let persistence = model.backup.persistence {
                history(persistence)
            } else {
                ContentUnavailableView("Backup History Unavailable", systemImage: "clock",
                                       description: Text("Backup history is not available in this session."))
            }
        }
        .toolbar {
            ToolbarItem {
                if let persistence = model.backup.persistence {
                    Button {
                        Task { await persistence.loadSessions() }
                    } label: {
                        Label("Refresh History", systemImage: "arrow.clockwise")
                    }
                    .disabled(persistence.isLoadingSessions)
                    .help("Refresh Backup History")
                }
            }
        }
        .task {
            if let persistence = model.backup.persistence, !persistence.hasLoadedSessions {
                await persistence.loadSessions()
            }
        }
    }

    @ViewBuilder
    private func history(_ persistence: LibraryBackupPersistence) -> some View {
        if persistence.recentSessions.isEmpty {
            if persistence.isLoadingSessions {
                ProgressView("Loading backup history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = persistence.sessionErrorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load Backup History", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await persistence.loadSessions() } }
                }
            } else {
                ContentUnavailableView("No Backups Yet", systemImage: "clock",
                                       description: Text("Your completed and interrupted backups will appear here."))
            }
        } else {
            List {
                if let message = persistence.sessionErrorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message).foregroundStyle(.secondary)
                            Button("Try Again") { Task { await persistence.loadSessions() } }
                                .disabled(persistence.isLoadingSessions)
                        }
                    }
                }
                Section {
                    ForEach(persistence.recentSessions) { session in
                        BackupHistoryRow(session: session)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                } header: {
                    HStack {
                        Text(persistence.recentSessions.count == 100 ? "Latest 100 Backups" : "Previous Backups")
                        if persistence.isLoadingSessions { ProgressView().controlSize(.small) }
                    }
                }
                Text("""
                History shows what was verified during each backup.
                Saved originals are checked again when you connect your iPhone.
                """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.inset)
        }
    }
}
