import BackupEngine
import MediaModels
import SwiftUI

struct BackupPreviewRequest: Identifiable {
    let id = UUID()
    let assets: [MediaAsset]
    let sessionID: UUID
    let destinationID: UUID
    let destinationPath: String
    let layout: BackupFolderLayout
    var continuingSessionID: UUID?

    @MainActor func matches(_ model: AppModel) -> Bool {
        model.backupSourceAvailable && model.catalogSessionID == sessionID
            && model.backup.destination.selection?.id == destinationID
            && assets.allSatisfy { model.currentAsset(id: $0.id) == $0 }
    }
}

struct BackupPreviewView: View {
    let request: BackupPreviewRequest
    var didStart: () -> Void = {}
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var preview: BackupStoragePreview?
    @State private var loading = true
    @State private var message: String?
    @State private var revision = 0

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Destination", value: request.destinationPath).textSelection(.enabled)
                LabeledContent("Selection", value: "\(request.assets.count) items")
                if loading { ProgressView("Checking saved originals and space…") }
                if let preview {
                    LabeledContent("Original files", value: preview.originalCount.formatted())
                    LabeledContent("Already saved and checked", value: preview.reusableOriginals.formatted())
                    LabeledContent("Estimated additional space", value: Format.bytes(preview.additionalBytes))
                    LabeledContent("Available space", value: preview.availableBytes.map(Format.bytes) ?? "Unknown")
                    if preview.hasKnownShortfall {
                        Text("There isn’t enough space for this selection. Free space or choose another backup folder.")
                            .foregroundStyle(.secondary)
                    }
                    if preview.unknownSizeCount > 0 {
                        Text("\(preview.unknownSizeCount) originals have no usable size. Refresh the iPhone library before backing up.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let message { Text(message).foregroundStyle(.secondary) }
                if !request.matches(model) {
                    Text("The phone, library or destination changed. Close this preview and review the backup again.")
                        .foregroundStyle(.secondary)
                }
                Text("Includes companion files. Available space is advisory; other apps and filesystem overhead can change it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .navigationTitle("Review Backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem { Button("Check Again") { revision += 1 }.disabled(loading || !request.matches(model)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Backup") {
                        guard preview?.canStart == true, request.matches(model) else { return }
                        model.startBackup(assets: request.assets, folderLayout: request.layout,
                                          continuingSessionID: request.continuingSessionID)
                        dismiss()
                        didStart()
                    }.disabled(loading || preview?.canStart != true || !request.matches(model))
                }
            }
        }
        .frame(width: 560, height: 430)
        .task(id: revision) {
            loading = true
            preview = nil
            message = nil
            defer { loading = false }
            do {
                guard request.matches(model) else { throw BackupDestinationError.selectionChanged }
                let value = try await model.backup.storagePreview(assets: request.assets, sessionID: request.sessionID,
                                                                  destinationID: request.destinationID)
                try Task.checkCancellation()
                preview = value
            } catch is CancellationError { return } catch { message = error.localizedDescription }
        }
    }
}
