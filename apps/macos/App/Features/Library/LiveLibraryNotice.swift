import SwiftUI

struct LiveLibraryNotice: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isCatalogLoading && model.deviceState == .ready {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("Reading iPhone library…")
                    Spacer()
                    if let percent = model.mediaScanPercent, percent < 100 {
                        Text("\(percent)%").monospacedDigit()
                    }
                }
            } else if model.mediaScanState == .complete {
                Text("\(model.assets.count.formatted()) items available over USB")
            }
            if model.iCloudPhotosEnabled {
                Label {
                    Text("iCloud Photos is on. Some originals may not be available over USB.")
                } icon: {
                    Image(systemName: "icloud")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.contentInset)
        .padding(.vertical, showsContent ? 10 : 0)
        .background(Design.cardFill)
    }

    private var showsContent: Bool {
        (model.isCatalogLoading && model.deviceState == .ready)
            || model.mediaScanState == .complete || model.iCloudPhotosEnabled
    }
}
