import BackupEngine
import SwiftUI

struct BackupBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            if model.sampleProgress {
                sampleProgress
            } else if model.backup.isBusy {
                activeProgress(model.backup.snapshot ?? BackupSnapshot(phase: .preparing))
                Button("Stop") { model.backup.cancel() }
                    .disabled(model.backup.isStopping)
            } else if let snapshot = model.backup.snapshot, isTerminal(snapshot.phase) {
                terminalSummary(snapshot)
                terminalActions(snapshot)
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

    private func activeProgress(_ snapshot: BackupSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(activeTitle(snapshot)).fontWeight(.medium)
                Spacer(minLength: 12)
                Text(transferCaption(snapshot))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }
            if isIndeterminate(snapshot) {
                ProgressView().progressViewStyle(.linear)
                    .accessibilityLabel(activeTitle(snapshot))
            } else {
                ProgressView(value: progressBytes(snapshot), total: Double(snapshot.expectedBytes))
                    .accessibilityLabel("Backup progress")
            }
            Text(snapshot.currentFilename ?? destinationCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(snapshot.currentFilename ?? destinationCaption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func terminalActions(_ snapshot: BackupSnapshot) -> some View {
        HStack(spacing: 10) {
            Button("Show in Finder") { Task { await model.backup.revealDestination() } }
                .disabled(model.backup.destination.selection == nil)
            if snapshot.phase != .completed {
                Button("Try Again") { model.retryLastBackup() }
                    .disabled(!model.canRetryBackup)
                    .help("Retry the items from this backup.")
            }
            Button("Done") { model.backup.dismissSummary() }
        }
    }

    private var destinationCaption: String {
        if model.isSample { return "Sample library · No files will be copied" }
        guard let destination = model.backup.destination.selection else { return "Choose where to save your originals" }
        return "To \(destination.displayName)"
    }

    private var actionTitle: String {
        if !model.selection.selectedIDs.isEmpty {
            return "Back Up \(model.selection.selectedIDs.count.formatted()) Selected"
        }
        let count = model.snapshot.visibleNewCount
        return count == 0 ? "Back Up New Items" : "Back Up \(count.formatted()) New \(count == 1 ? "Item" : "Items")"
    }

    private func activeTitle(_ snapshot: BackupSnapshot) -> String {
        if model.backup.isStopping || snapshot.phase == .cancelling { return "Stopping Backup…" }
        switch snapshot.phase {
        case .preparing, .idle: return "Preparing Backup…"
        case .verifying: return "Verifying Originals…"
        case .downloading:
            let counts = "\(snapshot.completedAssets.formatted()) of \(snapshot.totalAssets.formatted())"
            return "Backing Up \(counts) \(snapshot.totalAssets == 1 ? "Item" : "Items")"
        case .completed, .failed, .cancelled: return "Finishing Backup…"
        case .cancelling: return "Stopping Backup…"
        }
    }

    private func progressBytes(_ snapshot: BackupSnapshot) -> Double {
        let current = snapshot.phase == .downloading ? max(0, snapshot.currentResourceBytes) : 0
        return min(Double(snapshot.expectedBytes), Double(max(0, snapshot.verifiedBytes)) + Double(current))
    }

    private func isIndeterminate(_ snapshot: BackupSnapshot) -> Bool {
        model.backup.isStopping || snapshot.phase == .preparing || snapshot.phase == .verifying
            || snapshot.expectedBytes <= 0 || snapshot.currentResourceBytes == 0
    }

    private func transferCaption(_ snapshot: BackupSnapshot) -> String {
        if snapshot.transferredBytes > 0 { return "\(Format.bytes(snapshot.transferredBytes)) transferred" }
        return snapshot.phase == .downloading ? "Copying original…" : ""
    }

    private func terminalTitle(_ phase: BackupPhase) -> String {
        switch phase {
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

    private var sampleProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sample progress · 63 of 247 items")
                Spacer()
                Text("6.2 GB of 18.4 GB").foregroundStyle(.secondary)
            }
            .font(.callout.monospacedDigit())
            ProgressView(value: 6.2, total: 18.4)
                .accessibilityLabel("Sample backup progress")
            Text("Illustrative state. No transfer is running.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
