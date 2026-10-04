import SwiftUI

struct BackupProgressView: View {
    let progress: BackupProgressPresentation
    let destinationCaption: String
    var isSample = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if progress.waitsForOperation, progress.fraction != nil {
                    ProgressView().controlSize(.mini).accessibilityHidden(true)
                }
                Text(isSample ? "Sample · \(progress.title)" : progress.title)
                    .fontWeight(.medium)
                Spacer(minLength: 12)
                if let percentage = progress.percentage {
                    Text(percentage).monospacedDigit()
                }
            }
            meter
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(progress.itemSummary).fixedSize()
                    Spacer(minLength: 12)
                    if let bytes = progress.byteSummary { Text(bytes).fixedSize() }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(progress.itemSummary)
                    if let bytes = progress.byteSummary { Text(bytes) }
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(detail)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(detail)
                Spacer(minLength: 0)
                if !isSample, progress.snapshot.transferredBytes > 0 {
                    Text("\(Format.bytes(progress.snapshot.transferredBytes)) transferred")
                        .monospacedDigit()
                        .fixedSize()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
