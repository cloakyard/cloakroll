import BackupPersistence
import SwiftUI

struct BackupHealthView: View {
    @Environment(AppModel.self) private var model
    @State private var entries: [BackupHealthEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var revision = 0
    @State private var request: BackupSessionCheckRequest?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading backup health…")
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Backup Health Unavailable", systemImage: "exclamationmark.triangle")
                } description: { Text(errorMessage) } actions: {
                    Button("Try Again") { revision += 1 }
                }
            } else if entries.isEmpty {
                ContentUnavailableView("No Backups Yet", systemImage: "checkmark.shield",
                                       description: Text("Your iPhones and backup folders will appear here after a backup."))
            } else {
                List {
                    Section {
                        Text("Backups cover originals exposed over USB. iCloud-only or hidden items may be absent. ")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        BackupHealthRow(entry: entry, model: model) {
                            request = BackupSessionCheckRequest(session: entry.latestSession)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { revision += 1 }.disabled(isLoading)
        }
        .task(id: "\(revision)-\(model.backup.persistence?.sessionsRevision ?? 0)") { await load() }
        .sheet(item: $request, onDismiss: { revision += 1 }, content: { request in
            if let persistence = model.backup.persistence {
                BackupSessionCheckView(request: request, persistence: persistence, destination: model.backup.destination)
            }
        })
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let persistence = model.backup.persistence else { throw BackupStoreError.unavailable }
            let result = try await persistence.store().backupHealth()
            try Task.checkCancellation()
            entries = result
        } catch is CancellationError {
            return
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct BackupHealthRow: View {
    let entry: BackupHealthEntry
    let model: AppModel
    let check: () -> Void
    @State private var folder: BackupDestinationStore?
    @State private var showingContinuation = false

    var body: some View {
        Section(entry.latestSession.deviceName) {
            LabeledContent("Folder", value: folder?.selection?.lastKnownPath ?? "Choose the original folder when checking")
                .textSelection(.enabled)
            LabeledContent("Folder access") {
                DestinationReadinessLabel(readiness: folder?.readiness ?? .unchecked)
            }
            LabeledContent("Last completed backup") {
                if let date = entry.lastCompletedAt { Text(date, style: .date) } else { Text("No completed backup recorded") }
            }
            LabeledContent("Latest attempt", value: entry.latestSession.status.historyTitle)
            LabeledContent("Originals saved in that attempt",
                           value: "\(entry.latestSession.verifiedResources) of \(entry.latestSession.totalResources)")
            if let result = entry.integrityCheck {
                LabeledContent("Latest attempt checked") { Text(result.checkedAt, style: .date) }
                LabeledContent("Files matching at that check", value: "\(result.matchingFiles) of \(result.totalFiles)")
            } else {
                LabeledContent("Latest attempt checked", value: "Not checked")
            }
            Text("A completed backup is a historical result. A file check covers that attempt’s saved originals at the time shown.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if entry.latestSession.canContinue {
                    Button("Continue Backup…") { showingContinuation = true }.disabled(model.backup.isBusy)
                }
                Button("Check Saved Files…", action: check)
                    .disabled(!entry.latestSession.canCheckSavedFiles || model.backup.isBusy)
                Button("Back Up Missing Items") {
                    model.clearSelection()
                    model.captureDateRange = nil
                    model.search = ""
                    model.filter = .notBackedUp
                    model.backup.retryHistoryCheck()
                }
                .disabled(!canShowMissing)
                Button("Check Folder") { Task { await folder?.checkFolder() } }
                    .disabled(folder?.selection == nil || folder?.readiness.isChecking == true)
            }
            .buttonStyle(.bordered)
            .accessibilityElement(children: .contain)
            if !canShowMissing {
                Text("Connect this iPhone and select this backup folder to review missing items.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: entry.id) {
            let selected = model.backup.destination.selectionForHistoryCheck(destinationID: entry.latestSession.destinationID)
            folder = selected
            await selected.checkFolder()
        }
        .sheet(isPresented: $showingContinuation) { BackupContinuationView(session: entry.latestSession) }
    }

    private var canShowMissing: Bool {
        !model.isSample && model.device?.id == entry.deviceKey
            && model.backup.destination.selection?.id == entry.latestSession.destinationID
            && model.backupSourceAvailable
    }
}
