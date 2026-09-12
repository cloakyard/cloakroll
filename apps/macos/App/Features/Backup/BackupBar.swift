import SwiftUI

struct BackupBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                if model.sampleProgress {
                    sampleProgress
                } else {
                    summary
                    Spacer(minLength: 12)
                    Button(actionTitle) { }
                        .buttonStyle(.bordered)
                        .disabled(true)
                        .help(model.isSample ? "Transfers are unavailable in the sample library." : "Backup is not available yet.")
                }
            }
            .padding(.horizontal, Design.contentInset)
            .padding(.vertical, 16)
        }
        .background(.bar)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.selection.selectedIDs.isEmpty {
                HStack(spacing: 5) {
                    Text("\(model.snapshot.newCount.formatted()) new items").fontWeight(.medium)
                    Text("· \(Format.bytes(model.snapshot.newBytes))").foregroundStyle(.secondary)
                }
            } else {
                Text("\(model.selection.selectedIDs.count.formatted()) selected").fontWeight(.medium)
            }
            Text(model.isSample ? "Sample backup status · No files will be copied" : "Your originals stay on your iPhone")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionTitle: String {
        if model.snapshot.newCount == 0 && model.selection.selectedIDs.isEmpty { return "Back Up New Items" }
        if !model.selection.selectedIDs.isEmpty {
            return "Back Up \(model.selection.selectedIDs.count.formatted()) Selected"
        }
        return "Back Up \(model.snapshot.newCount.formatted()) New Items"
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
