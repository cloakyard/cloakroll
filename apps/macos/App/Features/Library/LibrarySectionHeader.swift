import MediaModels
import SwiftUI

/// Only the compact date marker has actions; the rest of the pinned row stays transparent.
struct LibrarySectionHeader: View {
    let section: MediaSection
    let onSelection: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let target = model.dateGroupTarget(sectionID: section.id)
        surface
            .contentShape(Capsule())
            .contextMenu { DateGroupSelectionActions(model: model, target: target, didSelect: onSelection) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityActions { DateGroupSelectionActions(model: model, target: target, didSelect: onSelection) }
            .help("Right-click to select or deselect this date group.")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private var surface: some View {
        if #available(macOS 26.0, *) {
            label.glassEffect(.regular, in: .capsule)
        } else {
            label.background(.regularMaterial, in: Capsule())
        }
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text("·")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("\(section.assets.count.formatted()) \(section.assets.count == 1 ? "item" : "items")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var title: String {
        guard let date = section.date else { return "Date Unknown" }
        switch section.grouping {
        case .automatic, .day: return date.formatted(.dateTime.month(.wide).day().year())
        case .month: return date.formatted(.dateTime.month(.wide).year())
        case .year: return date.formatted(.dateTime.year())
        }
    }
}
