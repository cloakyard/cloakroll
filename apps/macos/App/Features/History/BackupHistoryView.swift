import BackupPersistence
import SwiftUI

struct BackupHistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var isShowingRecovery = false
    @State private var checkRequest: BackupSessionCheckRequest?

    var body: some View {
        Group {
            if let persistence = model.backup.persistence {
                history(persistence)
            } else {
                ContentUnavailableView("Backup History Unavailable", systemImage: "clock",
                                       description: Text("Backup history is not available in this session."))
            }
        }
        .sheet(item: $checkRequest) { request in
            if let persistence = model.backup.persistence {
                BackupSessionCheckView(request: request, persistence: persistence, destination: model.backup.destination)
            }
        }
        .sheet(isPresented: $isShowingRecovery) { BackupFolderRecoveryView() }
        .toolbar {
            ToolbarItem {
                Button("Rebuild History…", systemImage: "arrow.counterclockwise") { isShowingRecovery = true }
                    .disabled(model.backup.isBusy || model.backup.destination.isChoosing || model.backup.persistence == nil)
                    .help("Rebuild Backup History from an existing folder")
            }
            ToolbarItem {
                if let persistence = model.backup.persistence {
                    BackupHistoryFilters(persistence: persistence)
                }
            }
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
                    Button("Try Again") { Task { await persistence.retrySessions() } }
                }
            } else if persistence.sessionFilter != BackupHistoryFilter() {
                ContentUnavailableView {
                    Label("No Matching Backups", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text(BackupHistoryFilters(persistence: persistence).summary)
                } actions: {
                    Button("Clear Filters") { Task { await persistence.applySessionFilter(BackupHistoryFilter()) } }
                }
            } else {
                ContentUnavailableView {
                    Label("No Backups Yet", systemImage: "clock")
                } description: {
                    Text("""
                        Your completed and interrupted backups will appear here. If you already have a backup folder, you \
                        can rebuild its history.
                        """)
                } actions: {
                    Button("Rebuild Backup History…") { isShowingRecovery = true }
                        .disabled(model.backup.isBusy)
                }
            }
        } else {
            BackupHistoryList(persistence: persistence) { checkRequest = $0 }
        }
    }
}
