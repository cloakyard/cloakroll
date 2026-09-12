import SwiftUI

enum ThumbnailSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: Self { self }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var minimumCellWidth: Double {
        switch self {
        case .small: 96
        case .medium: 144
        case .large: 200
        }
    }
}

struct ThumbnailSizePicker: View {
    @Binding var selection: ThumbnailSize

    var body: some View {
        Picker("Thumbnail size", selection: $selection) {
            ForEach(ThumbnailSize.allCases) { size in
                Text(size.title).tag(size)
            }
        }
    }
}
