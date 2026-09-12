import MediaModels
import SwiftUI

struct ViewOptionsButton: View {
    @Environment(AppModel.self) private var model
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("View Options", systemImage: "square.grid.2x2")
        }
        .help("Thumbnail size, sorting and grouping")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            options
        }
    }

    private var options: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 18) {
            Text("View Options")
                .font(.headline)
            ThumbnailSizeControl(size: $model.cellSize, focusesOnAppear: true)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("Sort by")
                    Picker("Sort by", selection: $model.sort) {
                        Text("Newest First").tag(CatalogSort.newestFirst)
                        Text("Oldest First").tag(CatalogSort.oldestFirst)
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Group by")
                    Picker("Group by", selection: $model.grouping) {
                        Text("Automatic").tag(CatalogGrouping.automatic)
                        Text("Day").tag(CatalogGrouping.day)
                        Text("Month").tag(CatalogGrouping.month)
                        Text("Year").tag(CatalogGrouping.year)
                    }
                    .labelsHidden()
                }
            }
        }
        .padding(20)
        .frame(width: 280)
        .onExitCommand { isPresented = false }
    }
}
