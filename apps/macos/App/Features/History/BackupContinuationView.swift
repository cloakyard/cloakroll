import BackupPersistence
import MediaModels
import SwiftUI

struct BackupContinuationView: View {
    let session: StoredBackupSession
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var plan: BackupContinuationPlan?
    @State private var reviewedIdentity: BackupCatalogIdentity?
    @State private var message: String?
    @State private var loading = false
    @State private var revision = 0

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("iPhone", value: session.deviceName)
                LabeledContent("Original selection", value: "\(session.totalAssets) items")
                Text("Completed originals will be checked before reuse. Unfinished files restart from the beginning.")
                    .foregroundStyle(.secondary)
                if loading { ProgressView("Matching the original selection…") }
                if let message { Text(message).foregroundStyle(.secondary) }
                if let plan {
                    LabeledContent("Matched items", value: "\(plan.assetIDs.count) of \(session.totalAssets)")
                    if plan.unavailableAssets > 0 {
                        Text("\(plan.unavailableAssets) items are unavailable, changed or ambiguous. "
                             + "Reconnect the original iPhone and retry.")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("The original folder organization is retained. Continuing never deletes or replaces unrelated files.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .navigationTitle("Continue Backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem {
                    Button("Review Again") { revision += 1 }.disabled(loading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue Backup") { continueBackup() }
                        .disabled(!canContinue)
                }
            }
        }
        .frame(width: 540, height: 360)
        .task(id: reviewKey) { await review() }
    }

    private var reviewKey: String {
        "\(revision)-\(model.catalogSessionID?.uuidString ?? "")-\(model.backup.destination.selection?.id.uuidString ?? "")"
            + "-\(model.backupSourceAvailable)"
    }

    private var canContinue: Bool {
        guard !loading, let plan, plan.unavailableAssets == 0, !plan.assetIDs.isEmpty,
              model.backupSourceAvailable, model.backup.destination.selection?.id == session.destinationID,
              reviewedIdentity == model.backup.recoveryContext?.identity else { return false }
        return true
    }

    private func review() async {
        plan = nil
        reviewedIdentity = nil
        message = nil
        guard model.backupSourceAvailable, let context = model.backup.recoveryContext,
              model.backup.destination.selection?.id == session.destinationID else {
            message = "Connect and unlock the original iPhone, select its original backup folder, and wait for the library check."
            return
        }
        loading = true
        defer { loading = false }
        do {
            guard let persistence = model.backup.persistence else { throw BackupStoreError.unavailable }
            let result = try await persistence.store().continuation(
                sessionID: session.id, destinationID: session.destinationID, identity: context.identity
            )
            try Task.checkCancellation()
            guard model.backup.recoveryContext?.identity == context.identity else { return }
            reviewedIdentity = context.identity
            plan = result
        } catch is CancellationError {
            return
        } catch { message = "This attempt cannot be continued with the current phone and folder. Open the library to choose items again." }
    }

    private func continueBackup() {
        guard canContinue, let plan else { return }
        let assets = plan.assetIDs.compactMap(model.currentAsset(id:))
        guard assets.count == plan.assetIDs.count else { return }
        model.startBackup(assets: assets, folderLayout: plan.folderLayout, continuingSessionID: session.id)
        dismiss()
    }
}
