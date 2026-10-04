import BackupEngine

/// Explicit visual fixtures use the production presentation and never start transfers.
enum BackupProgressExample: String, CaseIterable {
    case copying = "Copying"
    case verifying = "Verifying"
    case stopping = "Stopping"
    case preparing = "Preparing"
    case finishing = "Finishing"

    var presentation: BackupProgressPresentation {
        BackupProgressPresentation(snapshot: snapshot, isStopping: self == .stopping)
    }

    private var snapshot: BackupSnapshot {
        switch self {
        case .preparing:
            BackupSnapshot(phase: .preparing, totalAssets: 247)
        case .copying, .stopping:
            BackupSnapshot(
                phase: self == .copying ? .downloading : .cancelling,
                totalAssets: 247, expectedBytes: 18_400_000_000, completedAssets: 63,
                verifiedBytes: 6_000_000_000, transferredBytes: 6_200_000_000,
                currentFilename: "IMG_0247.MOV", currentResourceBytes: 200_000_000,
                currentResourceExpectedBytes: 500_000_000
            )
        case .verifying:
            BackupSnapshot(
                phase: .verifying, totalAssets: 247, expectedBytes: 18_400_000_000, completedAssets: 246,
                verifiedBytes: 17_900_000_000, transferredBytes: 18_400_000_000,
                currentFilename: "IMG_0247.MOV", currentResourceBytes: 500_000_000,
                currentResourceExpectedBytes: 500_000_000
            )
        case .finishing:
            BackupSnapshot(phase: .completed, totalAssets: 247, expectedBytes: 18_400_000_000,
                           completedAssets: 247, verifiedBytes: 18_400_000_000, transferredBytes: 18_400_000_000)
        }
    }
}
