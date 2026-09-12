import SwiftUI

/// A continuous native slider shared by the library and Settings.
struct ThumbnailSizeControl: View {
    @Binding var size: Double
    var focusesOnAppear = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Thumbnail size")
            Slider(value: $size, in: 84...200) {
                Text("Thumbnail size")
            } minimumValueLabel: {
                Image(systemName: "photo")
                    .font(.system(size: 12))
                    .accessibilityLabel("Smaller thumbnails")
            } maximumValueLabel: {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .accessibilityLabel("Larger thumbnails")
            }
            .labelsHidden()
            .foregroundStyle(.secondary)
            .accessibilityValue("\(Int(((size - 84) / 116 * 100).rounded())) percent")
            .focusable(interactions: .edit)
            .focused($isFocused)
            .onMoveCommand { direction in
                switch direction {
                case .left, .down: size = max(84, size - 4)
                case .right, .up: size = min(200, size + 4)
                @unknown default: break
                }
            }
            .onAppear { if focusesOnAppear { isFocused = true } }
        }
    }
}
