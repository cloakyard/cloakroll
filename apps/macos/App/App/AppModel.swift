import Foundation
import MediaModels
import MediaCatalog
import Observation

enum DeviceViewState: String {
    case disconnected, opening, restricted, ready, unavailable
}

/// Presentation state and intents only. Catalog transformations belong to the headless projector.
@MainActor @Observable
final class AppModel {
    var filter: LibraryFilter = .all { didSet { scheduleProjection() } }
    var search = "" { didSet { scheduleProjection() } }
    var sort: CatalogSort = .newestFirst { didSet { scheduleProjection() } }
    var grouping: CatalogGrouping = .automatic { didSet { scheduleProjection() } }
    var cellSize = 132.0
    var snapshot = CatalogSnapshot.empty
    var selection = MediaSelection()
    private(set) var activeID: String?
    var device: ConnectedDevice?
    var deviceState: DeviceViewState = .disconnected
    var isSample = true
    var isProjecting = false
    var infoAsset: MediaAsset?
    var settingsTab = SettingsTab.general
    var sampleProgress = false
    private(set) var assets: [MediaAsset] = []
    private(set) var statuses: [String: BackupStatus] = [:]

    @ObservationIgnored private var backupDates: [String: Date] = [:]
    @ObservationIgnored private let projector = CatalogProjector()
    @ObservationIgnored private var projectionTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var sourceGeneration = 0
    @ObservationIgnored private var isLoadingSource = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lookup: [String: MediaAsset] = [:]

    func bootstrap() async {
        guard !started else { return }
        started = true
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--empty") {
            await loadSample(count: 0, state: .disconnected)
        } else if arguments.contains("--locked") {
            await loadSample(count: 0, state: .restricted)
        } else {
            await loadSample(count: arguments.contains("--sample-100k") ? 100_000 : 1_200)
        }
    }

    func loadSample(count: Int, state: DeviceViewState = .ready) async {
        sourceGeneration += 1
        let requestedSource = sourceGeneration
        generation += 1
        projectionTask?.cancel()
        isLoadingSource = true
        isProjecting = true
        let (fixture, assetLookup) = await Task.detached(priority: .userInitiated) {
            let fixture = MockLibrary.make(count: count)
            let lookup = Dictionary(uniqueKeysWithValues: fixture.assets.map { ($0.id, $0) })
            return (fixture, lookup)
        }.value
        guard sourceGeneration == requestedSource else { return }
        isLoadingSource = false
        isSample = true
        device = state == .disconnected ? nil : fixture.device
        deviceState = state
        assets = fixture.assets
        statuses = fixture.statuses
        backupDates = fixture.backupDates
        lookup = assetLookup
        clearSelection()
        infoAsset = nil
        sampleProgress = false
        generation += 1
        await project(generation: generation)
    }

    func status(for asset: MediaAsset) -> BackupStatus { statuses[asset.id] ?? .notBackedUp }

    func select(_ asset: MediaAsset, extendingRange: Bool, toggling: Bool) {
        guard snapshot.orderedIDs.contains(asset.id) else { return }
        selection.select(id: asset.id, orderedIDs: snapshot.orderedIDs, extendingRange: extendingRange, toggling: toggling)
        activeID = asset.id
    }

    func selectAll() {
        selection.selectAll(snapshot.orderedIDs)
        if activeID == nil { activeID = snapshot.orderedIDs.first }
    }

    func clearSelection() {
        selection.clear()
        activeID = nil
    }

    func showSelectedInfo() {
        if let activeID, selection.selectedIDs.contains(activeID) {
            infoAsset = lookup[activeID]
            return
        }
        guard let id = snapshot.orderedIDs.first(where: selection.selectedIDs.contains) else { return }
        infoAsset = lookup[id]
    }

    func moveSelection(by offset: Int, extending: Bool) {
        let ids = snapshot.orderedIDs
        guard !ids.isEmpty else { return }
        let hasSelection = !selection.selectedIDs.isEmpty
        let current = activeID.flatMap { ids.firstIndex(of: $0) }
            ?? ids.firstIndex { selection.selectedIDs.contains($0) }
        let index = hasSelection && current != nil
            ? min(ids.count - 1, max(0, (current ?? 0) + offset))
            : 0
        let target = ids[index]
        selection.select(id: target, orderedIDs: ids, extendingRange: extending && hasSelection, toggling: false)
        activeID = target
    }

    private func scheduleProjection() {
        guard started || !assets.isEmpty else { return }
        generation += 1
        let requestedGeneration = generation
        projectionTask?.cancel()
        isProjecting = true
        // Query edits during source loading apply when that source is ready.
        guard !isLoadingSource else { return }
        projectionTask = Task {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            await project(generation: requestedGeneration)
        }
    }

    private func project(generation requestedGeneration: Int) async {
        let query = CatalogQuery(filter: filter, search: search, sort: sort, grouping: grouping)
        let result = await projector.project(assets: assets, statuses: statuses, backupDates: backupDates, query: query)
        guard !Task.isCancelled, generation == requestedGeneration else { return }
        snapshot = result
        selection.reconcile(with: result.orderedIDs)
        if let activeID, !result.orderedIDs.contains(activeID) {
            self.activeID = nil
        }
        isProjecting = false
    }
}
