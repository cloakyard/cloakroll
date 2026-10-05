import BackupPersistence
import SwiftUI

struct BackupHistoryRow: View {
    @Environment(AppModel.self) private var model
    let session: StoredBackupSession
    let checkSavedFiles: (BackupDestination) -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Items saved", value: "\(session.completedAssets.formatted()) of \(session.totalAssets.formatted())")
                LabeledContent("Original files verified",
                               value: "\(session.verifiedResources.formatted()) of \(session.totalResources.formatted())")
                LabeledContent("Verified size", value: Format.bytes(session.verifiedBytes))
                LabeledContent("Transferred", value: Format.bytes(session.transferredBytes))
                if let finishedAt = session.finishedAt {
                    LabeledContent("Finished") { Text(finishedAt, format: .dateTime.month(.abbreviated).day().hour().minute()) }
                }
                if let destination = model.backup.destination.selection {
                    destinationActions(destination)
                } else {
                    Text("Choose the original backup folder in the sidebar to check its saved files.")
                        .foregroundStyle(.secondary)
                }
                Text(session.status.historyDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.startedAt, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                        .fontWeight(.medium)
                    Text(session.deviceName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Label(session.status.historyTitle, systemImage: session.status.historySymbol)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityActions {
            if let destination = model.backup.destination.selection,
               !model.backup.isBusy, !model.backup.destination.isChoosing, session.status != .running {
                Button("Check Saved Files") { checkSavedFiles(destination) }
            }
        }
    }

    private func destinationActions(_ destination: BackupDestination) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(destination.id == session.destinationID ? "Folder" : "Check folder", value: destination.displayName)
            HStack {
                if destination.id == session.destinationID {
                    Button("Show in Finder") {
                        Task {
                            guard model.backup.destination.selection?.id == session.destinationID else { return }
                            await model.backup.revealDestination()
                        }
                    }
                }
                Button("Check Saved Files…") { checkSavedFiles(destination) }
                    .disabled(model.backup.isBusy || model.backup.destination.isChoosing || session.status == .running)
                    .help("Check this backup in \(destination.displayName). Select its original folder in the sidebar first.")
            }
            if destination.id != session.destinationID {
                Text("Select this backup’s original folder in the sidebar before checking.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summary: String {
        let itemCount = "\(session.completedAssets.formatted()) \(session.completedAssets == 1 ? "item" : "items")"
        return "\(itemCount) · \(Format.bytes(session.verifiedBytes))"
    }
}

extension StoredBackupSessionStatus {
    var historyTitle: String {
        switch self {
        case .running: "In Progress"
        case .completed: "Completed"
        case .failed: "Incomplete"
        case .cancelled: "Stopped"
        case .interrupted: "Interrupted"
        }
    }

    var historySymbol: String {
        switch self {
        case .running: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        case .cancelled: "stop.circle"
        case .interrupted: "exclamationmark.arrow.circlepath"
        }
    }

    var historyDescription: String {
        switch self {
        case .running: "This backup is still in progress."
        case .completed: "Every original was verified when this backup finished."
        case .failed: "The backup didn’t finish. Any verified originals have been kept."
        case .cancelled: "The backup was stopped. Any verified originals have been kept."
        case .interrupted: "The backup was interrupted. Any verified originals have been kept."
        }
    }
}
