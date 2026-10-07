import BackupPersistence
import SwiftUI

struct BackupHistoryRow: View {
    @Environment(AppModel.self) private var model
    let session: StoredBackupSession
    let checkSavedFiles: () -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 16) {
                details
                Text(session.status.historyDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions
            }
            .font(.callout)
            .padding(.vertical, 12)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.startedAt, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                        .fontWeight(.medium)
                    Text(session.deviceName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(session.deviceName)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Label(session.status.historyTitle, systemImage: session.status.historySymbol)
                    Text(session.historySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.vertical, 4)
        }
        .contextMenu {
            if session.canCheckSavedFiles {
                Button("Check Saved Files…", action: checkSavedFiles).disabled(!canCheck)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if canCheck { Button("Check Saved Files", action: checkSavedFiles) }
        }
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            detail("Items saved", value: "\(session.completedAssets.formatted()) of \(session.totalAssets.formatted())")
            detail("Original files verified", value: "\(session.verifiedResources.formatted()) of \(session.totalResources.formatted())")
            detail("Verified size", value: Format.bytes(session.verifiedBytes))
            detail("Transferred", value: session.transferredBytes == 0 ? "0 bytes" : Format.bytes(session.transferredBytes))
            if let finishedAt = session.finishedAt {
                GridRow {
                    Text(session.status == .recovered ? "Recovered" : "Finished").foregroundStyle(.secondary)
                    Text(finishedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func detail(_ label: String, value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if model.backup.destination.selection?.id == session.destinationID {
                Button("Show in Finder") {
                    Task {
                        guard model.backup.destination.selection?.id == session.destinationID else { return }
                        await model.backup.revealDestination()
                    }
                }
            }
            if session.canCheckSavedFiles {
                Button("Check Saved Files…", action: checkSavedFiles)
                    .disabled(!canCheck)
                    .help("Choose a folder and check this backup’s saved originals")
            }
        }
        .buttonStyle(.bordered)
    }

    private var canCheck: Bool {
        session.canCheckSavedFiles && !model.backup.isBusy && !model.backup.destination.isChoosing
    }
}
