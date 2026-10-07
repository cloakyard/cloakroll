import BackupPersistence
import SwiftUI

struct BackupSessionCheckRequest: Identifiable {
    let session: StoredBackupSession
    var id: UUID { session.id }
}

struct BackupSessionCheckView: View {
    let request: BackupSessionCheckRequest
    let persistence: LibraryBackupPersistence
    @State private var destination: BackupDestinationStore
    @State private var checker = BackupSessionCheckController()
    @State private var attempt = 0
    @State private var pickerAttempt = 0
    @Environment(\.dismiss) private var dismiss

    init(request: BackupSessionCheckRequest, persistence: LibraryBackupPersistence, destination: BackupDestinationStore) {
        self.request = request
        self.persistence = persistence
        _destination = State(initialValue: destination.selectionForHistoryCheck(destinationID: request.session.destinationID))
    }

    private var hasStarted: Bool { attempt > 0 }
    private var isChecking: Bool { hasStarted && checker.isRunning }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    folderSelection
                    if hasStarted {
                        checkResult
                        if !checker.progress.unverifiedPaths.isEmpty { unverifiedFiles }
                    }
                    Text("""
                        Files are compared with their saved size and checksum. Your iPhone isn’t needed, \
                        and its backup folder stays unchanged.
                        """)
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
                    if isChecking {
                        Button(checker.isStopping ? "Stopping…" : "Stop") { checker.stop() }
                            .disabled(checker.isStopping)
                            .keyboardShortcut(".", modifiers: .command)
                    } else if hasStarted {
                        Button("Check Again") { attempt += 1 }
                            .disabled(destination.isChoosing)
                            .keyboardShortcut("r", modifiers: .command)
                    } else {
                        Button("Cancel") { dismiss() }
                            .disabled(destination.isChoosing)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if hasStarted {
                        Button("Done") { checker.stop(); dismiss() }
                            .disabled(destination.isChoosing)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Check Files") { attempt += 1 }
                            .disabled(destination.selection == nil || destination.isChoosing)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .frame(width: 560, height: hasStarted ? 350 : 250)
        .interactiveDismissDisabled(isChecking || destination.isChoosing)
        .task(id: attempt) {
            guard hasStarted, let selection = destination.selection else { return }
            await checker.run(session: request.session, selectedDestinationID: selection.id,
                              destination: destination, persistence: persistence)
        }
        .task(id: pickerAttempt) {
            guard pickerAttempt > 0 else { return }
            if await destination.chooseFolder() { attempt = 0 }
        }
        .onExitCommand {
            guard !destination.isChoosing else { return }
            checker.stop()
            dismiss()
        }
    }

    private var folderSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "folder").foregroundStyle(Color.accentColor).font(.title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(destination.selection?.displayName ?? "Original Backup Folder").fontWeight(.medium)
                    if let selected = destination.selection {
                        Text(selected.lastKnownPath)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.middle).help(selected.lastKnownPath)
                    } else {
                        Text("Choose the folder used for this backup.").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(destination.selection == nil ? "Choose Folder…" : "Change…") { pickerAttempt += 1 }
                    .disabled(isChecking || destination.isChoosing)
                    .help("Choose the folder containing this backup’s saved originals")
            }
            if let message = destination.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(request.session.deviceName).font(.title2.weight(.semibold))
            Text(request.session.startedAt, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                .foregroundStyle(.secondary)
            if request.session.verifiedResources < request.session.totalResources {
                Text("This check covers only saved originals. Missing companions still need a backup.")
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
                        ProgressView("Preparing check…").controlSize(.small)
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
