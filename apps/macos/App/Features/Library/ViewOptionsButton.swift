import MediaModels
import SwiftUI

struct ViewOptionsButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Menu {
            Picker("Sort by", selection: $model.sort) {
                Text("Newest First").tag(CatalogSort.newestFirst)
                Text("Oldest First").tag(CatalogSort.oldestFirst)
            }
            Picker("Group by", selection: $model.grouping) {
                Text("Automatic").tag(CatalogGrouping.automatic)
                Text("Day").tag(CatalogGrouping.day)
                Text("Month").tag(CatalogGrouping.month)
                Text("Year").tag(CatalogGrouping.year)
            }
        } label: {
            Label("View Options", systemImage: "square.grid.2x2")
        }
        .help("Sort and group photos and videos")
    }
}
