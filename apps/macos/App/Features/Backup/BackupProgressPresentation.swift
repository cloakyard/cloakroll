import BackupEngine
import Foundation

/// Data progress counts verified originals plus received bytes awaiting verification.
/// It measures bytes, not elapsed work: 100% data progress is not a completed backup.
struct BackupProgressPresentation {
    let snapshot: BackupSnapshot
    var isStopping = false

    var processedBytes: Int64 {
        let total = max(0, snapshot.expectedBytes)
        let verified = min(total, max(0, snapshot.verifiedBytes))
        let received = min(max(0, snapshot.currentResourceBytes), max(0, snapshot.currentResourceExpectedBytes))
        return verified + min(total - verified, received)
    }

    var fraction: Double? {
        guard snapshot.expectedBytes > 0 else { return nil }
        return Double(processedBytes) / Double(snapshot.expectedBytes)
    }

    var percentage: String? {
        guard let fraction else { return nil }
        // Whole percentages round down. Floating-point precision must not turn remaining bytes into 100%.
        let percent = processedBytes == snapshot.expectedBytes ? 100 : min(99, Int((fraction * 100).rounded(.down)))
        return "\(percent.formatted())%"
    }

    var title: String {
        if isStopping || snapshot.phase == .cancelling { return "Stopping Backup…" }
        switch snapshot.phase {
        case .idle, .preparing: return "Preparing Backup…"
        case .downloading: return "Backing Up…"
        case .verifying: return "Verifying Originals…"
        case .completed, .failed, .cancelled: return "Finishing Backup…"
        case .cancelling: return "Stopping Backup…"
        }
    }

    var itemSummary: String {
        let total = max(0, snapshot.totalAssets)
        guard total > 0 else { return "Preparing items…" }
        let completed = min(total, max(0, snapshot.completedAssets))
        return "\(completed.formatted()) of \(total.formatted()) \(total == 1 ? "item" : "items") backed up"
    }

    var byteSummary: String? {
        guard snapshot.expectedBytes > 0 else { return nil }
        return "\(Format.bytes(processedBytes)) of \(Format.bytes(snapshot.expectedBytes))"
    }

    var waitsForOperation: Bool {
        isStopping || snapshot.phase != .downloading
    }
}
