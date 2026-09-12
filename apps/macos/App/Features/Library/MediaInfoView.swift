import MediaModels
import SwiftUI

struct MediaInfoView: View {
    let asset: MediaAsset
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle").font(.title2).foregroundStyle(Design.accent)
                    .accessibilityHidden(true)
                Text("Media Info").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MediaThumbnail(asset: asset, contentMode: .fit)
                        .frame(width: 420, height: 260)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: Design.inlineRadius))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(asset.filename).font(.title3.weight(.semibold)).textSelection(.enabled)
                        Text(asset.kind.title).foregroundStyle(.secondary)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                        detail("Captured", asset.createdAt?.formatted(date: .long, time: .shortened) ?? "Unknown")
                        detail("Size", Format.bytes(asset.byteCount))
                        if let width = asset.pixelWidth, let height = asset.pixelHeight {
                            detail("Dimensions", "\(width) × \(height)")
                        }
                        if asset.duration != nil { detail("Duration", Format.duration(asset.duration)) }
                        detail("Backup", model.status(for: asset).title + (model.isSample ? " (sample)" : ""))
                        detail("Original files", "\(asset.resources.count)")
                    }
                    if asset.resources.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Related originals").font(.headline)
                            ForEach(asset.resources, id: \.id) { resource in
                                HStack {
                                    Text(resource.filename).textSelection(.enabled)
                                    Spacer()
                                    Text(Format.bytes(resource.byteCount)).foregroundStyle(.secondary)
                                }
                                .font(.callout)
                            }
                        }
                    }
                    if model.isSample {
                        Label("Illustrated sample media. No original file is stored or transferred.", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 660)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
