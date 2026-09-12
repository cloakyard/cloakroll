import MediaModels
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 300)
        } detail: {
            LibraryView()
                .navigationTitle(model.filter.title)
                .searchable(text: $model.search, placement: .toolbar, prompt: "Search photos and videos")
                .toolbar { LibraryToolbar() }
                .safeAreaInset(edge: .bottom, spacing: 0) { BackupBar() }
        }
        .sheet(item: $model.infoAsset) { asset in
            MediaInfoView(asset: asset)
                .environment(model)
        }
    }
}

struct LibraryToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        @Bindable var model = model
        ToolbarItem(placement: .automatic) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Slider(value: $model.cellSize, in: 84...200, step: 4)
                    .frame(width: 80)
                    .accessibilityLabel("Thumbnail size")
                    .help("Thumbnail size")
            }
        }
        ToolbarItem(placement: .automatic) {
            Menu {
                Picker("Sort", selection: $model.sort) {
                    Text("Newest First").tag(CatalogSort.newestFirst)
                    Text("Oldest First").tag(CatalogSort.oldestFirst)
                }
                Divider()
                Picker("Group by", selection: $model.grouping) {
                    Text("Automatic").tag(CatalogGrouping.automatic)
                    Text("Day").tag(CatalogGrouping.day)
                    Text("Month").tag(CatalogGrouping.month)
                    Text("Year").tag(CatalogGrouping.year)
                }
            } label: {
                Label("View Options", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort and group the library")
        }
        ToolbarItem(placement: .automatic) {
            Button { model.showSelectedInfo() } label: {
                Label("Show Info", systemImage: "info.circle")
            }
            .help("Show Info (⌘I)")
            .disabled(model.selection.selectedIDs.isEmpty)
        }
    }
}
