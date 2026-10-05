import AppKit
import MediaModels
import SwiftUI
import ThumbnailPipeline

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var keyboard = GridKeyboardController()
    @State private var columns = 5
    @State private var prefetcher = GridThumbnailPrefetcher()

    var body: some View {
        VStack(spacing: 0) {
            if model.isSample { sampleNotice } else { LiveLibraryNotice() }
            if model.deviceState != .ready && !model.assets.isEmpty { disconnectNotice }
            if model.assets.isEmpty && (model.isProjecting || (model.isCatalogLoading && model.deviceState == .ready)) {
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
        Label("iPhone unavailable. Reconnect and unlock it to continue.", systemImage: "cable.connector")
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.08))
    }

    private var mediaGrid: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).id(LibraryScrollAnchor.top)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: model.cellSize), spacing: Design.gridSpacing)],
                            spacing: Design.gridSpacing,
                            pinnedViews: [.sectionHeaders]
                        ) {
                            ForEach(model.snapshot.sections) { section in
                                Section {
                                    ForEach(section.assets) { asset in
                                        MediaCell(asset: asset, viewportSize: geometry.size, onVisibilityChange: { visible in
                                            prefetcher.setVisible(visible, assetID: asset.id)
                                        }, onSelect: {
                                            keyboard.focus()
                                            let flags = NSEvent.modifierFlags
                                            model.select(
                                                asset, extendingRange: flags.contains(.shift), toggling: flags.contains(.command)
                                            )
                                        })
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
                }
                // Native pane integration lets scrolled photos continue beneath the toolbar
                // and lets macOS supply its own background and scroll-edge treatment.
                .scrollContentBackground(.visible)
                .coordinateSpace(name: ThumbnailViewport.coordinateSpace)
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
                .onChange(of: model.scrollReset) {
                    scroll.scrollTo(LibraryScrollAnchor.top, anchor: .top)
                }
            }
            .onChange(of: geometry.size.width, initial: true) { updateColumnCount(width: geometry.size.width) }
            .onChange(of: model.cellSize) { updateColumnCount(width: geometry.size.width) }
            .task(id: prefetchContext) { await preparePrefetch() }
            .onDisappear { prefetcher.stop() }
        }
    }

    private var prefetchContext: GridPrefetchContext {
        GridPrefetchContext(
            revision: model.snapshotRevision, columns: columns, sessionID: model.catalogSessionID,
            available: !model.isSample && model.deviceState == .ready
        )
    }

    private func preparePrefetch() async {
        guard prefetchContext.available, let sessionID = model.catalogSessionID else { prefetcher.pause(); return }
        let reusableIDs = model.device?.identity?.isPersistent == true ? model.thumbnailReuseIDs : [:]
        await prefetcher.prepare(sections: model.snapshot.sections, columns: columns) { asset in
            let reusableID = asset.primaryResourceID.flatMap { reusableIDs[$0] }
            guard let key = ThumbnailKey(asset: asset, sessionID: sessionID, reusableIdentity: reusableID) else { return }
            try await model.thumbnails.prefetch(for: key) { [model] in try await model.thumbnailData(for: key) }
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

private enum LibraryScrollAnchor { case top }

private struct GridPrefetchContext: Equatable {
    let revision: Int
    let columns: Int
    let sessionID: UUID?
    let available: Bool
}

struct DeviceEmptyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: model.deviceState == .restricted ? "lock.iphone" : "iphone.gen3")
        } description: {
            Text(message).frame(maxWidth: 380)
        } actions: {
            if !model.isSample && (model.deviceState == .restricted || model.deviceState == .unavailable) {
                Button("Try Again") { model.retryDeviceConnection() }
            }
            if !model.isSample {
                Button(model.deviceState == .ready ? "About USB Availability…" : "Connection Help…") {
                    model.presentation = .help(model.deviceState == .ready ? .usbAvailability : .gettingStarted)
                }
            }
        }
    }

    private var title: String {
        switch model.deviceState {
        case .disconnected: "Connect your iPhone"
        case .restricted: "Unlock your iPhone"
        case .opening: "Connecting to your iPhone"
        case .unavailable: "iPhone unavailable"
        case .ready: model.mediaScanState == .complete || model.isSample ? "No Media Available" : "Your iPhone is connected"
        }
    }

    private var message: String {
        if let message = model.deviceMessage { return message }
        return switch model.deviceState {
        case .disconnected: "Use a USB cable to browse and back up your photos and videos. Your originals stay on your iPhone."
        case .restricted: "Unlock your iPhone and, if asked, tap Trust to allow this Mac to access its photos and videos."
        case .opening: "Keep your iPhone connected and unlocked."
        case .unavailable: "Connect and unlock your iPhone to continue."
        case .ready:
            if model.isSample {
                "There are no items in this sample library."
            } else if model.mediaScanState == .complete {
                "No photos or videos are currently available over USB."
            } else {
                "Connected over USB. Your originals stay on your iPhone."
            }
        }
    }
}
