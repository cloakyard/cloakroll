import SwiftUI

struct DestinationReadinessLabel: View {
    let readiness: BackupDestinationReadiness

    var body: some View {
        Group {
            switch readiness {
            case .unchecked:
                Text("Not checked yet")
            case .checking:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityHidden(true)
                    Text("Checking access…")
                }
            case .available:
                Text("Access checked")
            case .unavailable:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Needs attention")
                }
            }
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityValue(readiness.message ?? "")
        .help(readiness.message ?? "Folder access is checked again before each backup.")
    }
}
