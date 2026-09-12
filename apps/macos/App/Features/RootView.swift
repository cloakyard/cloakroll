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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !model.assets.isEmpty { BackupBar() }
                }
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
        ToolbarItem(placement: .automatic) {
            ViewOptionsButton()
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
