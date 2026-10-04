import MediaModels
import SwiftUI

struct MediaInfoView: View {
    let asset: MediaAsset
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 24) {
                preview
                    .frame(width: 304)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heading
                        metadata
                        backupStatus
                        MediaInfoOriginalsView(resources: asset.resources)
                        if model.isSample {
                            Text("Illustrated sample media. No original file is stored or transferred.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(24)
            .navigationTitle("Media Info")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 760, height: 500)
        .onExitCommand { dismiss() }
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
                detail(asset.resources.count > 1 ? "Total size" : "Size", Format.bytes(asset.byteCount))
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
                    Text("In \(destination.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
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
