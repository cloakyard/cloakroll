import BackupEngine
import SwiftUI

struct BackupBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            if model.backup.isBusy {
                BackupProgressView(
                    progress: BackupProgressPresentation(
                        snapshot: model.backup.snapshot ?? BackupSnapshot(phase: .preparing),
                        isStopping: model.backup.isStopping
                    ), destinationCaption: destinationCaption
                )
                Button("Stop") { model.backup.cancel() }
                    .disabled(model.backup.isStopping)
            } else if model.sampleProgress {
                BackupProgressView(
                    progress: model.sampleProgressExample.presentation, destinationCaption: destinationCaption, isSample: true
                )
                Button("Stop") {}.disabled(true)
            } else if let snapshot = model.backup.snapshot, isTerminal(snapshot.phase) {
                terminalContent(snapshot)
            } else {
                idleSummary
                idleActions
            }
        }
        .padding(.horizontal, Design.contentInset)
        .padding(.vertical, 16)
    }

    private var idleSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.selection.selectedIDs.isEmpty {
                HStack(spacing: 5) {
                    Text("\(model.snapshot.visibleNewCount.formatted()) new \(itemWord(model.snapshot.visibleNewCount))")
                        .fontWeight(.medium)
                    Text("· \(Format.bytes(model.snapshot.visibleNewBytes))").foregroundStyle(.secondary)
                }
            } else {
                Text("\(model.selection.selectedIDs.count.formatted()) selected").fontWeight(.medium)
            }
            Text(destinationCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.backup.destination.selection?.lastKnownPath ?? destinationCaption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idleActions: some View {
        HStack(spacing: 10) {
            Button(actionTitle) { model.backUpCurrentSelection() }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canBackUp)
                .help(model.isSample ? "Transfers are unavailable in the sample library." : "Copy originals to the backup folder.")
        }
    }

    private func terminalContent(_ snapshot: BackupSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                terminalSummary(snapshot).frame(minWidth: 220)
                terminalActions(snapshot).fixedSize()
            }
            VStack(alignment: .leading, spacing: 12) {
                terminalSummary(snapshot)
                terminalActions(snapshot)
            }
        }
    }

    private func terminalSummary(_ snapshot: BackupSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(terminalTitle(snapshot.phase)).fontWeight(.medium)
            Text("""
            \(snapshot.completedAssets.formatted()) of \(snapshot.totalAssets.formatted()) \(itemWord(snapshot.totalAssets)) backed up
            """)
                .font(.caption)
            Text(verifiedSummary(snapshot))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = snapshot.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(message)
            }
            if snapshot.phase != .completed, let message = model.backupRetryState.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func terminalActions(_ snapshot: BackupSnapshot) -> some View {
        HStack(spacing: 10) {
            Button("Show in Finder") { Task { await model.backup.revealDestination() } }
                .disabled(model.backup.destination.selection == nil)
            if snapshot.phase != .completed {
                retryAction
            }
            Button("Done") { model.backup.dismissSummary() }
        }
    }

    @ViewBuilder private var retryAction: some View {
        switch model.backupRetryState {
        case .ready:
            Button("Try Again") { model.retryLastBackup() }
                .help("Retry these items. Saved originals are checked before reuse.")
        case .chooseItems:
            Button("Choose Items") {
                model.clearSelection()
                model.backup.dismissSummary()
            }
        case .showLibrary:
            Button("Show Library") { model.navigation = .library(model.filter) }
        case .connectDevice, .readingLibrary, .checkingHistory, .historyUnavailable, .choosingFolder:
            EmptyView()
        }
    }

    private var destinationCaption: String {
        if model.isSample { return "Sample library · No files will be copied" }
        guard let destination = model.backup.destination.selection else { return "Choose where to save your originals" }
        return "To \(destination.displayName)"
    }

    private var actionTitle: String {
        if model.backup.isCheckingHistory { return "Checking Backups…" }
        if !model.selection.selectedIDs.isEmpty {
            return "Back Up \(model.selection.selectedIDs.count.formatted()) Selected"
        }
        let count = model.snapshot.visibleNewCount
        return count == 0 ? "Back Up New Items" : "Back Up \(count.formatted()) New \(count == 1 ? "Item" : "Items")"
    }

    private func terminalTitle(_ phase: BackupPhase) -> String {
        if model.backup.wasInterrupted, phase == .failed { return "Backup Interrupted" }
        return switch phase {
        case .completed: "Backup Complete"
        case .cancelled: "Backup Stopped"
        default: "Backup Incomplete"
        }
    }

    private func isTerminal(_ phase: BackupPhase) -> Bool {
        phase == .completed || phase == .cancelled || phase == .failed
    }

    private func itemWord(_ count: Int) -> String { count == 1 ? "item" : "items" }

    private func verifiedSummary(_ snapshot: BackupSnapshot) -> String {
        let count = snapshot.verifiedResources
        return "\(count.formatted()) \(count == 1 ? "original" : "originals") verified · \(Format.bytes(snapshot.verifiedBytes))"
    }
}
