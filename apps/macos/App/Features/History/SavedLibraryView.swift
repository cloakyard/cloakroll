import AppKit
import BackupEngine
import BackupPersistence
import MediaModels
import SwiftUI

struct SavedLibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var sources: [BackupHealthEntry] = []
    @State private var selectedSource: UUID?
    @State private var kind: MediaKind?
    @State private var usesDates = false
    @State private var fromDate = Date()
    @State private var throughDate = Date()
    @State private var items: [SavedLibraryItem] = []
    @State private var cursors: [SavedLibraryCursor] = []
    @State private var nextCursor: SavedLibraryCursor?
    @State private var folder: BackupDestinationStore?
    @State private var folderDestinationID: UUID?
    @State private var loadGeneration = 0
    @State private var loading = false
    @State private var folderAvailable = false
    @State private var message: String?
    @State private var actionError: String?
    @State private var preview: SavedPreviewRequest?
    @State private var refresh = 0
    @State private var pageRevision = 0

    private var source: BackupHealthEntry? { sources.first { $0.id == selectedSource } }
    private var query: SavedLibraryQuery? {
        guard let source else { return nil }
        let calendar = Calendar.current
        return SavedLibraryQuery(deviceKey: source.deviceKey, destinationID: source.latestSession.destinationID, kind: kind,
                                 capturedAfter: usesDates ? calendar.startOfDay(for: fromDate) : nil,
                                 capturedBefore: usesDates ? calendar.date(byAdding: .day, value: 1,
                                                                          to: calendar.startOfDay(for: throughDate)) : nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            filters.padding()
            Divider()
            if let message { Text(message).font(.callout).foregroundStyle(.secondary).padding() }
            if loading {
                ProgressView("Loading saved originals…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView("No Saved Originals in This View", systemImage: "photo.stack",
                                       description: Text("Choose a backup and adjust the filters. Your iPhone isn’t needed."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in row(item) }
            }
            HStack {
                Text("Recorded originals · previews do not verify file integrity").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Newer") { _ = cursors.popLast(); pageRevision += 1 }.disabled(cursors.isEmpty || loading)
                Button("Older") {
                    if let nextCursor { cursors.append(nextCursor); pageRevision += 1 }
                }.disabled(nextCursor == nil || loading)
            }.padding()
        }
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { refresh += 1 }.disabled(loading) }
        .task(id: refresh) { await loadSources() }
        .task(id: query) { cursors = []; await loadPage() }
        .task(id: pageRevision) { if pageRevision > 0 { await loadPage() } }
        .sheet(item: $preview) { SavedOriginalPreview(request: $0) }
        .alert("Original Unavailable", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Backup", selection: $selectedSource) {
                    Text("Choose a backup").tag(UUID?.none)
                    ForEach(sources) { source in
                        Text(source.latestSession.deviceName + " · " + destinationName(source))
                            .tag(Optional(source.id))
                    }
                }
                Picker("Type", selection: $kind) {
                    Text("All types").tag(MediaKind?.none)
                    ForEach(MediaKind.allCases, id: \.self) { Text($0.savedLibraryTitle).tag(Optional($0)) }
                }.frame(maxWidth: 220)
            }
            HStack {
                Toggle("Capture dates", isOn: $usesDates).toggleStyle(.checkbox)
                Spacer(minLength: 0)
                if let folder {
                    Button("Locate Folder…") {
                        Task { if await folder.chooseFolder() { pageRevision += 1 } }
                    }.disabled(loading || folder.isChoosing)
                }
            }
            if usesDates {
                HStack {
                    DatePicker("From", selection: $fromDate, displayedComponents: .date).fixedSize()
                    DatePicker("Through", selection: $throughDate, displayedComponents: .date).fixedSize()
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func destinationName(_ source: BackupHealthEntry) -> String {
        model.backup.destination.selectionForHistoryCheck(destinationID: source.latestSession.destinationID)
            .selection?.displayName ?? "Backup folder"
    }

    private func row(_ item: SavedLibraryItem) -> some View {
        DisclosureGroup {
            ForEach(item.originals, id: \.relativePath) { original in
                HStack {
                    Text(original.filename).textSelection(.enabled)
                    Spacer()
                    Text(Format.bytes(original.byteCount)).foregroundStyle(.secondary)
                    Button("Preview") { Task { await open(original, previewing: true) } }
                    Button("Reveal") { Task { await open(original, previewing: false) } }
                }
                .buttonStyle(.bordered)
                .disabled(!folderAvailable)
            }
        } label: {
            HStack(spacing: 12) {
                if let original = item.originals.first, let folder, folderAvailable {
                    SavedOriginalThumbnail(record: original, folder: folder)
                } else { Image(systemName: "photo").frame(width: 80, height: 70).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.originals.first?.filename ?? "Saved item").fontWeight(.medium)
                    if let date = item.capturedAt {
                        Text(date, style: .date).foregroundStyle(.secondary)
                    } else {
                        Text("Capture date unavailable").foregroundStyle(.secondary)
                    }
                    Text("\(item.originals.count) of \(item.expectedOriginals) originals recorded")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadSources() async {
        do {
            guard let persistence = model.backup.persistence else { throw BackupStoreError.unavailable }
            let result = try await persistence.store().backupHealth()
            try Task.checkCancellation()
            sources = result
            if !sources.contains(where: { $0.id == selectedSource }) { selectedSource = sources.first?.id } else { pageRevision += 1 }
        } catch is CancellationError { return } catch { message = error.localizedDescription }
    }

    private func loadPage() async {
        guard let query, let persistence = model.backup.persistence else {
            items = []; nextCursor = nil; folderAvailable = false
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        loading = true
        items = []
        message = nil
        folderAvailable = false
        var loadedRecords = false
        defer { if loadGeneration == generation { loading = false } }
        do {
            let page = try await persistence.store().savedLibrary(query: query, after: cursors.last)
            try Task.checkCancellation()
            guard self.query == query, loadGeneration == generation else { return }
            items = page.items
            loadedRecords = true
            nextCursor = page.nextCursor
            if folderDestinationID != query.destinationID {
                folderDestinationID = query.destinationID
                folder = model.backup.destination.selectionForHistoryCheck(destinationID: query.destinationID)
            }
            guard let folder else { throw BackupDestinationError.noSelection }
            let lease = try await folder.acquireLease(readOnly: true)
            defer { lease.release() }
            try Task.checkCancellation()
            guard self.query == query, loadGeneration == generation else { return }
            folderAvailable = true
        } catch is CancellationError { return } catch {
            guard loadGeneration == generation else { return }
            message = loadedRecords
                ? "The backup folder couldn’t be opened. Reconnect its drive or locate the original folder. "
                    + "Recorded items remain visible; this does not mean their files are missing."
                : "Saved history couldn’t be read. Refresh to try again. Your original files have not been changed."
        }
    }

    private func open(_ record: VerifiedBackupResource, previewing: Bool) async {
        guard let folder else { return }
        do {
            let lease = try await folder.acquireLease(readOnly: true)
            let url = try await SavedOriginalAccess.url(destination: lease.url, record: record)
            try Task.checkCancellation()
            if previewing {
                preview = SavedPreviewRequest(url: url, lease: lease)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url]); lease.release()
            }
        } catch {
            actionError = "This original is missing, changed or inaccessible. "
                + "Check the folder and run Check Saved Files for integrity."
        }
    }
}

private extension MediaKind {
    var savedLibraryTitle: String {
        switch self {
        case .photo: "Photos"
        case .video: "Videos"
        case .livePhoto: "Live Photos"
        case .raw: "RAW"
        case .other: "Other"
        }
    }
}
