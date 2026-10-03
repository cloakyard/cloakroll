import SwiftUI

struct ViewOptionsButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Menu {
            LibraryViewOptions(model: model)
        } label: {
            Label("View Options", systemImage: "square.grid.2x2")
        }
        .help("Thumbnail size, sorting and grouping")
    }
}
