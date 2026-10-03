import SwiftUI

struct DestinationReadinessLabel: View {
    let readiness: BackupDestinationReadiness

    var body: some View {
        Group {
            switch readiness {
            case .unchecked:
                Text("Not Checked")
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Checking Folder…")
                }
            case .available:
                Label("Last Check Passed", systemImage: "checkmark.circle")
            case .unavailable:
                Label("Folder Unavailable", systemImage: "exclamationmark.circle")
            }
        }
        .foregroundStyle(.secondary)
        .help(readiness.message ?? "Folder access is checked again before each backup.")
    }
}
