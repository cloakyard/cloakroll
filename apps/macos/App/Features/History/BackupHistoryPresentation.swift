import BackupPersistence
import Foundation

extension StoredBackupSession {
    var canCheckSavedFiles: Bool { status != .running && verifiedResources > 0 }

    var historySummary: String {
        guard verifiedResources > 0 else { return "No originals saved" }
        let count: String
        if completedAssets > 0 {
            count = "\(completedAssets.formatted()) \(completedAssets == 1 ? "item" : "items")"
        } else {
            count = "\(verifiedResources.formatted()) \(verifiedResources == 1 ? "original" : "originals") saved"
        }
        return "\(count) · \(Format.bytes(verifiedBytes))"
    }
}

extension StoredBackupSessionStatus {
    var historyTitle: String {
        switch self {
        case .recovered: "Recovered"
        case .running: "In Progress"
        case .completed: "Completed"
        case .failed: "Incomplete"
        case .cancelled: "Stopped"
        case .interrupted: "Interrupted"
        }
    }

    var historySymbol: String {
        switch self {
        case .recovered: "arrow.counterclockwise.circle"
        case .running: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        case .cancelled: "stop.circle"
        case .interrupted: "exclamationmark.arrow.circlepath"
        }
    }

    var historyDescription: String {
        switch self {
        case .recovered: "History was rebuilt by checking saved originals on this date. Missing companions remain eligible for backup."
        case .running: "This backup is still in progress."
        case .completed: "Every original was verified when this backup finished."
        case .failed: "The backup didn’t finish. Any verified originals have been kept."
        case .cancelled: "The backup was stopped. Any verified originals have been kept."
        case .interrupted: "The backup was interrupted. Any verified originals have been kept."
        }
    }
}
