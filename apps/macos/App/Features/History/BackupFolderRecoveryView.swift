import SwiftUI

struct BackupFolderRecoveryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode = BackupFolderRecoveryController.Mode.indexed

    private var recovery: BackupFolderRecoveryController { model.backup.recovery }
    private var canStart: Bool {
        !model.backup.isBusy && !model.backup.isCheckingHistory && !model.backup.destination.isChoosing
            && model.backup.destination.selection != nil
            && (mode == .indexed || model.backupSourceAvailable)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("""
                        Restore backup history from originals already on your Mac or an external drive. Verified files stay \
                        in place; your next backup copies only what’s missing.
                        """)
                        .foregroundStyle(.secondary)
                    destination
                    if recovery.phase == .idle {
                        options
                    } else {
                        status
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(24, for: .scrollContent)
            .navigationTitle("Rebuild Backup History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if recovery.isRunning {
                        Button(recovery.isStopping ? "Stopping…" : "Stop") { recovery.stop() }
                            .keyboardShortcut(".", modifiers: .command)
                            .disabled(recovery.isStopping || recovery.phase == .saving)
                    } else {
                        Button("Close") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !recovery.isRunning {
                        if recovery.phase == .idle {
                            Button("Rebuild History") { Task { await model.rebuildBackupHistory(mode: mode) } }
                                .keyboardShortcut(.defaultAction)
                                .disabled(!canStart)
                        } else {
                            Button("Start Again") { recovery.reset() }
                                .keyboardShortcut("r", modifiers: .command)
                        }
                    }
                }
            }
        }
        .frame(width: 560, height: 340)
        .interactiveDismissDisabled(recovery.isRunning)
        .task { recovery.reset() }
    }

    private var destination: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder").font(.title2).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.backup.destination.selection?.displayName ?? "Choose a Backup Folder")
                    .fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                Text("Select the folder originally chosen as the backup destination.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Choose…") { Task { await model.backup.chooseDestination() } }
                .disabled(recovery.phase != .idle || model.backup.isBusy || model.backup.destination.isChoosing)
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Recovery Method", selection: $mode) {
                Text("Use saved recovery records").tag(BackupFolderRecoveryController.Mode.indexed)
                Text("Verify older files with iPhone over USB").tag(BackupFolderRecoveryController.Mode.usb)
            }
            .pickerStyle(.radioGroup)
            if mode == .indexed {
                Text("""
                    Checks saved originals against the folder’s recovery records. Existing app history is also used to \
                    prepare older CloakRoll backups for future recovery.
                    """)
                    .foregroundStyle(.secondary)
            } else {
                Text("""
                    For folders without recovery records. CloakRoll reads matching originals from your iPhone once to \
                    compare their contents. This can take as long as a backup and needs temporary space for one \
                    original.
                    """)
                    .foregroundStyle(.secondary)
                if !model.backupSourceAvailable {
                    Label("Connect and unlock your iPhone, then wait for its library to load.", systemImage: "iphone")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }

    @ViewBuilder private var status: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if recovery.isRunning {
                if recovery.total > 0 {
                    ProgressView(value: Double(recovery.checked), total: Double(recovery.total))
                    Text("\(recovery.checked.formatted()) of \(recovery.total.formatted()) originals checked")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                } else { ProgressView().controlSize(.small) }
            } else if recovery.phase == .completed {
                countRow("Verified originals", value: recovery.verified)
                countRow("New history records", value: recovery.recovered)
                if recovery.unavailable > 0 {
                    Text("""
                        \(recovery.unavailable.formatted()) recovery records could not be verified. Those originals remain \
                        eligible for backup.
                        """)
                        .foregroundStyle(.secondary)
                }
                Text(recovery.verified == 0
                     ? """
                         No originals could be recovered with this method. For an older folder without recovery records, try \
                         verification over USB.
                         """
                     : """
                         History is ready. Return to your library to back up missing items. Missing Live Photo companions \
                         will be copied separately.
                         """)
                    .foregroundStyle(.secondary)
            } else {
                Text(recovery.errorMessage ?? """
                    Recovery stopped. Any completed recovery records were preserved in the folder. Start again to \
                    continue checking them.
                    """)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private func countRow(_ label: String, value: Int) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value.formatted()).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if recovery.isStopping { return "Stopping…" }
        switch recovery.phase {
        case .idle: return "Ready"
        case .preparing: return "Preparing Recovery…"
        case .checking: return "Checking Saved Originals…"
        case .verifying: return "Comparing with iPhone…"
        case .saving: return "Saving Recovered History…"
        case .completed:
            if recovery.verified == 0 { return "No Verified Originals" }
            return recovery.recovered == 0 ? "History Is Up to Date" : "History Rebuilt"
        case .stopped: return "Recovery Stopped"
        case .failed: return "Couldn’t Rebuild History"
        }
    }
}
