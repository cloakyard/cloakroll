import SwiftUI

struct BackupProgressView: View {
    let progress: BackupProgressPresentation
    let destinationCaption: String
    var isSample = false
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                if progress.showsActivityIndicator {
                    ProgressView().controlSize(.mini).accessibilityHidden(true)
                }
                Text(isSample ? "Sample · \(progress.title)" : progress.title)
                    .fontWeight(.medium)
                    .fixedSize()
                Button("Backup Details", systemImage: "info.circle") { showsDetails.toggle() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show the current original and transfer details.")
                    .popover(isPresented: $showsDetails, arrowEdge: .top) { details }
                Spacer(minLength: 12)
                Text(progress.itemSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let percentage = progress.percentage {
                    Text(percentage).monospacedDigit()
                        .fixedSize()
                }
            }
            meter
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backup Details").font(.headline)
            if detail != destinationCaption {
                Text(detail)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(destinationCaption).foregroundStyle(.secondary)
            if let bytes = progress.byteSummary {
                LabeledContent("Data progress", value: bytes).monospacedDigit()
            }
            if !isSample, progress.snapshot.transferredBytes > 0 {
                LabeledContent("Transferred", value: Format.bytes(progress.snapshot.transferredBytes))
                    .monospacedDigit()
            }
            if !isSample {
                Text("Your Mac stays awake while originals are copied and verified. The display can sleep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }

    private var meter: some View {
        Group {
            if let fraction = progress.fraction {
                ProgressView(value: fraction, total: 1)
            } else {
                ProgressView()
            }
        }
        .progressViewStyle(.linear)
        .transaction {
            $0.animation = nil
            $0.disablesAnimations = true
        }
        .tint(Design.accent)
        .accessibilityLabel(isSample ? "Sample data progress" : "Backup data progress")
        .accessibilityValue(
            [progress.percentage, progress.byteSummary, progress.itemSummary].compactMap { $0 }.joined(separator: ", ")
        )
        .help("""
        Progress includes received bytes and originals already verified. Verification and backup history must finish before completion.
        """)
    }

    private var detail: String {
        if isSample { return "Illustrative state. No transfer is running." }
        if progress.isStopping || progress.snapshot.phase == .cancelling { return "Waiting for the current operation to stop…" }
        if progress.snapshot.phase == .completed { return "Saving backup history…" }
        return progress.snapshot.currentFilename ?? destinationCaption
    }
}
