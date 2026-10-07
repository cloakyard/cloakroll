import MediaModels
import SwiftUI

/// Read the current item from the model while retaining the sheet's presentation identity.
struct MediaInfoSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let asset = model.infoAsset { MediaInfoView(asset: asset) }
    }
}

struct MediaInfoView: View {
    let asset: MediaAsset
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 24) {
                preview
                    .frame(width: 304)
                    .padding(.leading, 24)
                    .padding(.vertical, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heading
                        metadata
                        backupStatus
                        if asset.kind.isStillImage, !model.isSample, asset.primaryResource != nil {
                            MediaInfoCameraView(asset: asset)
                        }
                        MediaInfoOriginalsView(resources: asset.resources)
                        if model.isSample {
                            Text("Illustrated sample media. No original file is stored or transferred.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .contentMargins(.trailing, 24, for: .scrollContent)
                .contentMargins(.vertical, 24, for: .scrollContent)
                .scrollBounceBehavior(.basedOnSize)
            }
            // Reset preview, camera state and scroll position before showing another item.
            // Toolbar controls keep their identity and keyboard focus while browsing.
            .id(ContentIdentity(asset: asset, sessionID: model.catalogSessionID))
            .navigationTitle("Media Info")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    MediaInfoNavigation(asset: asset)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 760, height: 500)
        .onExitCommand { dismiss() }
    }

    private struct ContentIdentity: Hashable {
        let asset: MediaAsset
        let sessionID: UUID?
    }

    private var preview: some View {
        MediaThumbnail(asset: asset, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(Design.cardFill, in: RoundedRectangle(cornerRadius: Design.cardRadius))
            .clipShape(RoundedRectangle(cornerRadius: Design.cardRadius))
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(asset.filename)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Label(asset.kind.title, systemImage: mediaSymbol)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var metadata: some View {
        GroupBox {
            VStack(spacing: 12) {
                detail("Captured", asset.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
                detail(asset.resources.count > 1 ? "Total size" : "Size",
                       asset.resources.isEmpty ? "Unknown" : Format.bytes(asset.byteCount))
                if let width = asset.pixelWidth, let height = asset.pixelHeight, width > 0, height > 0 {
                    detail("Dimensions", "\(width) × \(height)")
                }
                if let duration = asset.duration, duration.isFinite, duration >= 0 {
                    detail("Duration", Format.duration(duration))
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
        }
    }

    private var backupStatus: some View {
        let status = model.status(for: asset)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusSymbol(status))
                .foregroundStyle(status == .backedUp ? Design.accent : Color.secondary)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(status.title + (model.isSample ? " (sample)" : ""))
                    .font(.callout.weight(.medium))
                    .accessibilityLabel("Backup: \(status.title)\(model.isSample ? " (sample)" : "")")
                if !model.isSample, let destination = model.backup.destination.selection {
                    Text("Backup folder: \(destination.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        MediaInfoDetailRow(label: label, value: value)
    }

    private var mediaSymbol: String {
        switch asset.kind {
        case .photo: "photo"
        case .video: "video"
        case .livePhoto: "livephoto"
        case .raw: "camera.aperture"
        case .other: "doc"
        }
    }

    private func statusSymbol(_ status: BackupStatus) -> String {
        switch status {
        case .notBackedUp: "circle.dashed"
        case .backedUp: "checkmark.circle.fill"
        case .uncertain: "questionmark.circle"
        case .failed: "exclamationmark.circle"
        }
    }
}
