import BackupPersistence
import SwiftUI

struct BackupHistoryRow: View {
    @Environment(AppModel.self) private var model
    let session: StoredBackupSession

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
                if let destination = model.backup.destination.selection, destination.id == session.destinationID {
                    LabeledContent("Folder", value: destination.displayName)
                    Button("Show in Finder") {
                        Task {
                            guard model.backup.destination.selection?.id == session.destinationID else { return }
                            await model.backup.revealDestination()
                        }
                    }
                } else {
                    LabeledContent("Folder", value: model.backup.destination.selection == nil ? "Not selected" : "Another backup folder")
                }
                Text(session.status.historyDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .padding(.vertical, 8)
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
        case .completed: "Every original in this backup was verified."
        case .failed: "The backup didn’t finish. Any verified originals have been kept."
        case .cancelled: "The backup was stopped. Any verified originals have been kept."
        case .interrupted: "The backup was interrupted. Any verified originals have been kept."
        }
    }
}
