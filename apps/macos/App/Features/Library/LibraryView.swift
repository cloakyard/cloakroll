import AppKit
import MediaModels
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var keyboard = GridKeyboardController()
    @State private var columns = 5

    var body: some View {
        VStack(spacing: 0) {
            if model.isSample { sampleNotice }
            if model.deviceState == .unavailable { disconnectNotice }
            if model.assets.isEmpty && model.isProjecting {
                ProgressView("Preparing library…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.assets.isEmpty {
                DeviceEmptyView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.snapshot.filteredCount == 0 {
                ContentUnavailableView {
                    Label("No Matching Items", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text(model.search.isEmpty ? "There are no items in this collection." : "Try another filename.")
                } actions: {
                    if !model.search.isEmpty {
                        Button("Clear Search") { model.search = "" }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mediaGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.contentBackground)
    }

    private var sampleNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(Design.accent)
            Text("Sample Library").fontWeight(.medium)
            Text("Explore with illustrated sample media. No files are transferred.")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, Design.contentInset)
        .padding(.vertical, 10)
        .background(Design.cardFill)
    }

    private var disconnectNotice: some View {
        Label("iPhone disconnected. Reconnect and unlock it to continue.", systemImage: "cable.connector")
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.08))
    }

    private var mediaGrid: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: model.cellSize), spacing: Design.gridSpacing)],
                        spacing: Design.gridSpacing,
                        pinnedViews: [.sectionHeaders]
                    ) {
                        ForEach(model.snapshot.sections) { section in
                            Section {
                                ForEach(section.assets) { asset in
                                    MediaCell(asset: asset) {
                                        keyboard.focus()
                                        let flags = NSEvent.modifierFlags
                                        model.select(asset, extendingRange: flags.contains(.shift), toggling: flags.contains(.command))
                                    }
                                    .id(asset.id)
                                }
                            } header: {
                                sectionHeader(section)
                            }
                        }
                    }
                    .padding(.horizontal, Design.contentInset)
                    .padding(.bottom, 24)
                }
                .background {
                    GridKeyboardBridge(
                        controller: keyboard, columns: columns,
                        onMove: { offset, extending in
                            model.moveSelection(by: offset, extending: extending)
                            if let id = model.activeID { scroll.scrollTo(id) }
                        },
                        onSelectAll: model.selectAll,
                        onPreview: model.showSelectedInfo,
                        onClear: model.clearSelection
                    )
                    .frame(width: 1, height: 1)
                }
                .onChange(of: model.snapshot.orderedIDs.first) {
                    if let id = model.snapshot.orderedIDs.first { scroll.scrollTo(id, anchor: .top) }
                }
            }
            .onChange(of: geometry.size.width, initial: true) { updateColumnCount(width: geometry.size.width) }
            .onChange(of: model.cellSize) { updateColumnCount(width: geometry.size.width) }
        }
    }

    private func updateColumnCount(width: Double) {
        columns = max(1, Int((width - Design.contentInset * 2 + Design.gridSpacing) / (model.cellSize + Design.gridSpacing)))
    }

    private func sectionHeader(_ section: MediaSection) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(sectionTitle(section)).font(.title3.weight(.semibold))
            Spacer()
            Text("\(section.assets.count.formatted()) \(section.assets.count == 1 ? "item" : "items")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 22)
        .padding(.bottom, 10)
        .background(Design.contentBackground)
        .accessibilityAddTraits(.isHeader)
    }

    private func sectionTitle(_ section: MediaSection) -> String {
        guard let date = section.date else { return "Date Unknown" }
        switch section.grouping {
        case .automatic, .day: return date.formatted(.dateTime.month(.wide).day().year())
        case .month: return date.formatted(.dateTime.month(.wide).year())
        case .year: return date.formatted(.dateTime.year())
        }
    }
}

struct DeviceEmptyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: model.deviceState == .restricted ? "lock.iphone" : "iphone.gen3")
        } description: {
            Text(message).frame(maxWidth: 380)
        }
    }

    private var title: String {
        switch model.deviceState {
        case .disconnected: "Connect your iPhone"
        case .restricted: "Unlock your iPhone"
        case .opening: "Connecting to your iPhone"
        case .unavailable: "Reconnect your iPhone"
        case .ready: "No Media Available"
        }
    }

    private var message: String {
        switch model.deviceState {
        case .disconnected: "Use a USB cable to browse and back up your photos and videos. Your originals stay on your iPhone."
        case .restricted: "Unlock your iPhone and, if asked, tap Trust to allow this Mac to access its photos and videos."
        case .opening: "Keep your iPhone connected and unlocked."
        case .unavailable: "Connect and unlock your iPhone to continue."
        case .ready: "There are no photos or videos available from this device."
        }
    }
}
