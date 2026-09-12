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
                .modifier(BackupBarPlacement(isVisible: !model.assets.isEmpty))
        }
        .sheet(item: $model.infoAsset) { asset in
            MediaInfoView(asset: asset)
                .environment(model)
        }
    }
}

private struct BackupBarPlacement: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) {
                if isVisible { BackupBar() }
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if isVisible {
                    VStack(spacing: 0) {
                        Divider()
                        BackupBar()
                    }
                    .background(.bar)
                }
            }
        }
    }
}

struct LibraryToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        @Bindable var model = model
        ToolbarItem(placement: .automatic) {
            ThumbnailSizeSlider(size: $model.cellSize)
                .frame(width: 200)
                .help("Thumbnail size")
        }
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
