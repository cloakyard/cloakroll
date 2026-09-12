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
                .modifier(BackupBarPlacement(isVisible: !model.assets.isEmpty || model.backup.snapshot != nil))
        }
        .sheet(item: $model.infoAsset) { asset in
            MediaInfoView(asset: asset)
                .environment(model)
        }
        .alert("Backup Unavailable", isPresented: Binding(
            get: { model.backup.errorMessage != nil },
            set: { if !$0 { model.backup.errorMessage = nil } }
        )) {
            Button("OK") { model.backup.errorMessage = nil }
        } message: {
            Text(model.backup.errorMessage ?? "")
        }
    }
}

private struct BackupBarPlacement: ViewModifier {
    @Environment(AppModel.self) private var model
    let isVisible: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) {
                if isVisible { BackupBar(model: model) }
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if isVisible {
                    VStack(spacing: 0) {
                        Divider()
                        BackupBar(model: model)
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
