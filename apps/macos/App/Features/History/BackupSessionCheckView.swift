import BackupPersistence
import SwiftUI

struct BackupSessionCheckRequest: Identifiable {
    let session: StoredBackupSession
    let destination: BackupDestination
    var id: UUID { session.id }
}

struct BackupSessionCheckView: View {
    let request: BackupSessionCheckRequest
    let persistence: LibraryBackupPersistence
    let destination: BackupDestinationStore
    @State private var checker = BackupSessionCheckController()
    @State private var attempt = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    checkResult
                    if !checker.progress.unverifiedPaths.isEmpty { unverifiedFiles }
                    Text("Files are compared with their saved size and checksum. Your iPhone isn’t needed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(24, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Check Saved Files")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if checker.isRunning {
                        Button(checker.isStopping ? "Stopping…" : "Stop") { checker.stop() }
                            .disabled(checker.isStopping)
                            .keyboardShortcut(".", modifiers: .command)
                    } else {
                        Button("Check Again") { attempt += 1 }
                            .keyboardShortcut("r", modifiers: .command)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { checker.stop(); dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(width: 560, height: 370)
        .task(id: attempt) {
            await checker.run(session: request.session, selectedDestinationID: request.destination.id,
                              destination: destination, persistence: persistence)
        }
        .onExitCommand { checker.stop(); dismiss() }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(request.session.deviceName).font(.title2.weight(.semibold))
            Text(request.session.startedAt, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                .foregroundStyle(.secondary)
            Label(request.destination.displayName, systemImage: "folder")
                .font(.callout)
                .foregroundStyle(.secondary)
                .help(request.destination.lastKnownPath)
            if request.session.status != .completed {
                Text("This backup was unfinished. This check covers only the originals that were saved.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var checkResult: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                if checker.isRunning {
                    if checker.progress.totalFiles > 0 {
                        ProgressView(value: Double(checker.progress.checkedFiles), total: Double(checker.progress.totalFiles))
                            .accessibilityLabel("Saved files checked")
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                if let message = checker.errorMessage {
                    Text(message).foregroundStyle(.secondary)
                } else if checker.phase != .preparing {
                    countRow("Checked", value: "\(checker.progress.checkedFiles.formatted()) of \(checker.progress.totalFiles.formatted())")
                    countRow("Matching originals", value: checker.progress.matchingFiles.formatted())
                    if checker.progress.unverifiedFiles > 0 {
                        countRow("Couldn’t verify", value: checker.progress.unverifiedFiles.formatted())
                    }
                }
            }
            .font(.callout)
            .accessibilityElement(children: .contain)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func countRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch checker.phase {
        case .preparing: "Preparing Check…"
        case .checking: checker.isStopping ? "Stopping Check…" : "Checking Saved Files…"
        case .completed:
            if checker.progress.totalFiles == 0 { "No Saved Originals to Check" } else if checker.progress.unverifiedFiles > 0 {
                "Some Files Couldn’t Be Verified"
            } else { "Saved Files Match" }
        case .stopped: "Check Stopped"
        case .failed: "Couldn’t Complete Check"
        }
    }

    private var unverifiedFiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Files to Review").font(.headline)
            Text("These files may be missing, changed or unavailable. Check the backup drive, then try again.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(checker.progress.unverifiedPaths, id: \.self) { path in
                Label {
                    Text(path).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "doc.badge.ellipsis").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            if checker.progress.unverifiedFiles > checker.progress.unverifiedPaths.count {
                Text("Showing the first \(checker.progress.unverifiedPaths.count.formatted()) files.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
