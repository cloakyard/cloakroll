import MediaModels
import SwiftUI

struct MediaInfoNavigation: View {
    let asset: MediaAsset
    @Environment(AppModel.self) private var model

    var body: some View {
        let position = model.infoPosition(for: asset)
        HStack(spacing: 12) {
            ControlGroup {
                Button("Previous Item", systemImage: "chevron.left") { model.moveInfo(.previous, from: asset) }
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Previous item (⌘[)")
                    .disabled(position?.previousID == nil)
                Button("Next Item", systemImage: "chevron.right") { model.moveInfo(.next, from: asset) }
                    .keyboardShortcut("]", modifiers: .command)
                    .help("Next item (⌘])")
                    .disabled(position?.nextID == nil)
            }
            .labelStyle(.iconOnly)
            if let position {
                Text("\((position.index + 1).formatted()) of \(position.count.formatted())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Item \((position.index + 1).formatted()) of \(position.count.formatted())")
            }
        }
    }
}
