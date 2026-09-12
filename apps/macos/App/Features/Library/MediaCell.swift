import AppKit
import MediaModels
import SwiftUI

struct MediaCell: View {
    let asset: MediaAsset
    let onSelect: () -> Void
    @Environment(AppModel.self) private var model

    private var selected: Bool { model.selection.selectedIDs.contains(asset.id) }

    var body: some View {
        Button(action: onSelect) {
            GeometryReader { geometry in
                MediaThumbnail(asset: asset)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay(alignment: .bottomLeading) { mediaBadge.padding(7) }
                    .overlay(alignment: .bottomTrailing) { backupBadge.padding(7) }
                    .overlay(alignment: .topLeading) {
                        if asset.kind == .video {
                            Image(systemName: "video.fill")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                                .padding(7)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Design.contentBackground, Design.accent)
                                .font(.system(size: 20))
                                .padding(7)
                        }
                    }
                    .overlay { Rectangle().strokeBorder(selected ? Design.accent : .clear, lineWidth: 3) }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelect() }
        .accessibilityLabel("\(asset.filename), \(asset.kind.title), \(model.status(for: asset).title)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help("\(asset.filename) · \(Format.bytes(asset.byteCount))")
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.infoAsset = asset })
        .contextMenu {
            Button("Show Info") { model.infoAsset = asset }
            Button("Copy Filename") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(asset.filename, forType: .string)
            }
        }
    }

    @ViewBuilder private var mediaBadge: some View {
        switch asset.kind {
        case .video:
            Text(Format.duration(asset.duration))
                .font(.caption2.weight(.medium).monospacedDigit())
                .badgeSurface()
        case .livePhoto:
            Image(systemName: "livephoto").font(.caption).badgeSurface()
        case .raw:
            Text("RAW").font(.system(size: 9, weight: .bold)).badgeSurface()
        case .photo, .other:
            EmptyView()
        }
    }

    @ViewBuilder private var backupBadge: some View {
        if model.status(for: asset) == .backedUp {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.65))
        }
    }
}

private extension View {
    func badgeSurface() -> some View {
        self.foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct SampleThumbnail: View {
    let asset: MediaAsset

    var body: some View {
        if asset.id.hasPrefix("fixture-"), let index = Int(asset.id.dropFirst("fixture-".count)) {
            Image("Sample\(index % 12)")
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            Rectangle().fill(Design.cardFill)
                .overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
                .accessibilityHidden(true)
        }
    }
}
