import Foundation
import MediaModels
import MediaCatalog
import DeviceCapture
import Observation

typealias DeviceViewState = DeviceConnectionState

/// Presentation state and intents only. Catalog transformations belong to the headless projector.
@MainActor @Observable
final class AppModel {
    var filter: LibraryFilter = .all { didSet { scheduleProjection() } }
    var search = "" { didSet { scheduleProjection() } }
    var sort: CatalogSort = .newestFirst { didSet { scheduleProjection() } }
    var grouping: CatalogGrouping = .automatic { didSet { scheduleProjection() } }
    var thumbnailSize = ThumbnailSize.medium
    var cellSize: Double { thumbnailSize.minimumCellWidth }
    var snapshot = CatalogSnapshot.empty
    var selection = MediaSelection()
    private(set) var activeID: String?
    var device: ConnectedDevice?
    var deviceState: DeviceViewState = .disconnected
    var isSample = false
    var deviceMessage: String?
    var isProjecting = false
    var infoAsset: MediaAsset?
    var settingsTab = SettingsTab.general
    var sampleProgress = false
    private(set) var catalogSessionID: UUID?
    private(set) var mediaScanState: MediaScanState?
    private(set) var mediaScanPercent: Int?
    private(set) var iCloudPhotosEnabled = false
    private(set) var isCatalogPreparing = false
    private(set) var scrollReset = 0
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
    @ObservationIgnored private let makeBrowser: @MainActor () -> any DeviceBrowsing
    @ObservationIgnored private var browser: (any DeviceBrowsing)?
    @ObservationIgnored private var deviceTask: Task<Void, Never>?
    @ObservationIgnored private var catalogLoader: LiveCatalogLoader?
    @ObservationIgnored private var lastProjectedQuery: CatalogQuery?

    init(makeBrowser: (@MainActor () -> any DeviceBrowsing)? = nil) {
        if let makeBrowser {
            self.makeBrowser = makeBrowser
        } else {
            let context = DeviceCaptureContext()
            self.makeBrowser = { DeviceBrowserService(context: context) }
        }
    }

    func bootstrap() async {
        guard !started else { return }
        started = true
        #if DEBUG
        if ProcessInfo.processInfo.environment["CLOAKROLL_TESTING"] == "1" { return }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--empty") {
            await loadSample(count: 0, state: .disconnected)
            return
        } else if arguments.contains("--locked") {
            await loadSample(count: 0, state: .restricted)
            return
        } else if arguments.contains("--sample") || arguments.contains("--sample-100k") {
            await loadSample(count: arguments.contains("--sample-100k") ? 100_000 : 1_200)
            return
        }
        #endif
        startLive()
    }

    func loadSample(count: Int, state: DeviceViewState = .ready) async {
        stopDeviceBrowsing()
        resetCatalogState()
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
        deviceMessage = nil
        device = state == .disconnected ? nil : fixture.device
        deviceState = state
        assets = fixture.assets
        statuses = fixture.statuses
        backupDates = fixture.backupDates
        lookup = assetLookup
        clearSelection()
        infoAsset = nil
        sampleProgress = false
        scrollReset += 1
        generation += 1
        await project(generation: generation)
    }

    func startLive() {
        started = true
        stopDeviceBrowsing()
        resetCatalogState()
        sourceGeneration += 1
        generation += 1
        projectionTask?.cancel()
        isLoadingSource = false
        isProjecting = false
        isSample = false
        sampleProgress = false
        assets = []
        statuses = [:]
        backupDates = [:]
        lookup = [:]
        snapshot = .empty
        scrollReset += 1
        clearSelection()
        infoAsset = nil
        device = nil
        deviceState = .disconnected
        deviceMessage = nil
        let service = makeBrowser()
        browser = service
        if let source = service as? any DeviceMediaSource {
            catalogLoader = LiveCatalogLoader(
                source: source,
                onReceive: { [weak self] in self?.receiveCatalog($0) },
                onPrepared: { [weak self] in self?.applyCatalog($0) }
            )
        }
        let events = service.events
        deviceTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.apply(event)
            }
        }
        service.start()
    }

    func retryDeviceConnection() { browser?.retry() }

    func thumbnailData(for asset: MediaAsset, maximumPixelSize: Int) async throws -> Data {
        guard !isSample, deviceState == .ready,
              let sessionID = catalogSessionID, let resourceID = asset.primaryResourceID,
              let provider = browser as? any ThumbnailProviding else { throw MediaSourceError.unavailable }
        try Task.checkCancellation()
        let data = try await provider.thumbnailData(for: resourceID, sessionID: sessionID, maximumPixelSize: maximumPixelSize)
        try Task.checkCancellation()
        guard catalogSessionID == sessionID, deviceState == .ready else { throw MediaSourceError.staleSession }
        return data
    }

    func shutdown() {
        sourceGeneration += 1
        generation += 1
        projectionTask?.cancel()
        stopDeviceBrowsing()
    }

    private func stopDeviceBrowsing() {
        catalogLoader?.stop()
        catalogLoader = nil
        browser?.stop()
        deviceTask?.cancel()
        deviceTask = nil
        browser = nil
    }

    var isCatalogLoading: Bool { mediaScanState == .scanning || isCatalogPreparing }

    private func resetCatalogState() {
        catalogSessionID = nil
        mediaScanState = nil
        mediaScanPercent = nil
        iCloudPhotosEnabled = false
        isCatalogPreparing = false
    }

    private func receiveCatalog(_ source: DeviceMediaSnapshot) {
        guard !isSample else { return }
        catalogSessionID = source.sessionID
        mediaScanState = source.state
        mediaScanPercent = source.percentComplete
        iCloudPhotosEnabled = source.iCloudPhotosEnabled == true
        isCatalogPreparing = true
    }

    private func applyCatalog(_ prepared: PreparedDeviceCatalog) {
        guard !isSample, prepared.source.sessionID == catalogSessionID else { return }
        isCatalogPreparing = false
        // Keep the previous device's catalog useful while the same phone reconnects. A complete
        // empty catalog or a different phone always replaces it rather than claiming stale media.
        if prepared.assets.isEmpty, prepared.source.state != .complete,
           assets.first?.deviceID == prepared.source.deviceID { return }
        if let previousDevice = assets.first?.deviceID, previousDevice != prepared.source.deviceID {
            scrollReset += 1
        }
        assets = prepared.assets
        lookup = prepared.lookup
        if let infoAsset { self.infoAsset = lookup[infoAsset.id] }
        scheduleProjection()
    }

    private func apply(_ event: DeviceEvent) {
        guard !isSample else { return }
        switch event {
        case .stateChanged(let connection):
            device = connection.device
            deviceState = connection.state
            deviceMessage = connection.message
        }
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
        let result: CatalogSnapshot
        do {
            result = try await projector.project(assets: assets, statuses: statuses, backupDates: backupDates, query: query)
        } catch {
            // Superseded projections stop promptly and never publish an empty replacement.
            return
        }
        guard !Task.isCancelled, generation == requestedGeneration else { return }
        snapshot = result
        if query != lastProjectedQuery {
            lastProjectedQuery = query
            scrollReset += 1
        }
        selection.reconcile(with: result.orderedIDs)
        if let activeID, !result.orderedIDs.contains(activeID) {
            self.activeID = nil
        }
        isProjecting = false
    }
}
