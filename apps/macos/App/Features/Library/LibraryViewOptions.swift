import MediaModels
import SwiftUI

/// The toolbar and menu bar expose the same native choices and current checkmarks.
struct LibraryViewOptions: View {
    @Bindable var model: AppModel

    var body: some View {
        ThumbnailSizePicker(selection: $model.thumbnailSize)
        Divider()
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
    }
}
