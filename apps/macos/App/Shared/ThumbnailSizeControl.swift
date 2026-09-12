import SwiftUI

struct ThumbnailSizeControl: View {
    @Binding var size: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Thumbnail size")
            ThumbnailSizeSlider(size: $size)
        }
    }
}

/// The system owns pointer tracking, keyboard editing, focus and the current OS appearance.
struct ThumbnailSizeSlider: View {
    @Binding var size: Double

    var body: some View {
        Slider(value: $size, in: 84...200) {
            Text("Thumbnail size")
        } minimumValueLabel: {
            Image(systemName: "photo")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Smaller thumbnails")
        } maximumValueLabel: {
            Image(systemName: "photo")
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Larger thumbnails")
        }
        .labelsHidden()
    }
}
