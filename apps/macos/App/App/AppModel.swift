import BackupEngine
import Foundation
import MediaModels
import MediaCatalog
import DeviceCapture
import Observation
import ThumbnailPipeline

typealias DeviceViewState = DeviceConnectionState

/// Presentation state and intents only. Catalog transformations belong to the headless projector.
@MainActor @Observable
final class AppModel {
    var navigation = SidebarDestination.library(.all)
    var isViewingLibrary: Bool { navigation != .backupHistory }
    var filter: LibraryFilter = .all { didSet { navigation = .library(filter); scheduleProjection() } }
    var search = "" { didSet { scheduleProjection() } }
    var searchPresented = false
    var captureDateRange: CaptureDateRange? { didSet { scheduleProjection() } }
    var dateFilterPresented = false
    var sort: CatalogSort = .newestFirst { didSet { preferences.save(sort); scheduleProjection() } }
    var grouping: CatalogGrouping = .automatic { didSet { preferences.save(grouping); scheduleProjection() } }
    var thumbnailSize = ThumbnailSize.medium { didSet { preferences.save(thumbnailSize) } }
    var cellSize: Double { thumbnailSize.minimumCellWidth }
    var snapshot = CatalogSnapshot.empty { didSet { snapshotRevision &+= 1 } }
    private(set) var snapshotRevision = 0
    var selection = MediaSelection()
    private(set) var activeID: String?
    var device: ConnectedDevice?
    var deviceState: DeviceViewState = .disconnected
    var isSample = false
    var deviceMessage: String?
    private(set) var deviceInventory = DeviceInventory()
    var isProjecting = false
    var presentation: LibraryPresentation?
    var settingsTab = SettingsTab.general { didSet { preferences.save(settingsTab) } }
    var backupOrganization = BackupOrganization.byDate { didSet { preferences.save(backupOrganization) } }
    var sampleProgress = false
    var sampleProgressExample = BackupProgressExample.copying
    private(set) var catalogSessionID: UUID?
    private(set) var mediaScanState: MediaScanState?
    private(set) var mediaScanPercent: Int?
    private(set) var iCloudPhotosEnabled = false
    private(set) var isCatalogPreparing = false
    private(set) var scrollReset = 0
    private(set) var assets: [MediaAsset] = []
    private(set) var statuses: [String: BackupStatus] = [:]
    private(set) var thumbnailReuseIDs: [String: String] = [:]

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
    @ObservationIgnored private var lastSelectedDeviceID: UUID?
    @ObservationIgnored private var deviceTask: Task<Void, Never>?
    @ObservationIgnored private var catalogLoader: LiveCatalogLoader?
    @ObservationIgnored private var lastProjectedQuery: CatalogQuery?
    @ObservationIgnored private let preferences: LibraryPreferences
    @ObservationIgnored let thumbnails = LibraryThumbnailController()
    @ObservationIgnored let backup: LibraryBackupController

    init(
        makeBrowser: (@MainActor () -> any DeviceBrowsing)? = nil, preferences: LibraryPreferences = .standard,
        backup: LibraryBackupController = LibraryBackupController(persistence: LibraryBackupPersistence.appDefault())
    ) {
        self.backup = backup
        self.preferences = preferences
        thumbnailSize = preferences.thumbnailSize
        sort = preferences.sort
        grouping = preferences.grouping
        settingsTab = preferences.settingsTab
        backupOrganization = preferences.backupOrganization
        if let makeBrowser {
            self.makeBrowser = makeBrowser
        } else {
            let context = DeviceCaptureContext()
            self.makeBrowser = { DeviceBrowserService(context: context) }
        }
        backup.onStatusesChanged = { [weak self] in self?.refreshBackupStatuses() }
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
        await backup.persistence?.loadSessions()
    }

    func loadSample(count: Int, state: DeviceViewState = .ready) async {
        guard !backup.isBusy else { return }
        backup.dismissSummary()
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
        guard !backup.isBusy else { return }
        backup.dismissSummary()
        started = true
        stopDeviceBrowsing()
        clearDeviceLibrary()
        sourceGeneration += 1
        isLoadingSource = false
        isSample = false
        sampleProgress = false
        device = nil
        deviceState = .disconnected
        deviceMessage = nil
        let service = makeBrowser()
        browser = service
        if let source = service as? any DeviceMediaSource {
            catalogLoader = LiveCatalogLoader(
                source: source,
                shouldReceive: { [weak self] in self?.shouldReceiveCatalog($0) == true },
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

    func retryDeviceConnection() {
        guard !backup.isBusy else { return }
        browser?.retry()
    }

    var canSelectDevice: Bool {
        !isSample && !backup.isBusy && !backup.destination.isChoosing && browser is any DeviceSelectionBrowsing
    }

    @discardableResult
    func selectDevice(id: UUID) -> Bool {
        guard canSelectDevice, let source = browser as? any DeviceSelectionBrowsing,
              source.selectDevice(id: id) else { return false }
        applyInventory(source.inventory)
        applyConnection(source.selectedConnection)
        return true
    }

    var backupSourceAvailable: Bool {
        !isSample && deviceState == .ready && mediaScanState == .complete
            && !isCatalogPreparing && !isProjecting && !backup.isBusy && !backup.destination.isChoosing
            && !backup.isCheckingHistory && backup.historyErrorMessage == nil
            && catalogSessionID != nil && browser is any OriginalMediaDownloading
    }

    func currentAsset(id: String) -> MediaAsset? { lookup[id] }

    func startBackup(assets: [MediaAsset]) {
        guard let sessionID = catalogSessionID, let download = originalDownload else { return }
        backup.start(assets: assets, sessionID: sessionID, folderLayout: backupOrganization.folderLayout, download: download)
    }

    var originalDownload: BackupEngine.Download? {
        guard backupSourceAvailable, let provider = browser as? any OriginalMediaDownloading else { return nil }
        return { request, progress in
            try await provider.downloadOriginal(resourceID: request.resource.id, sessionID: request.sessionID,
                                                to: request.directory, filename: request.filename, progress: progress)
        }
    }

    private func refreshBackupStatuses() {
        guard !isSample else { return }
        let projection = backup.projection(assets: assets, sessionID: catalogSessionID)
        statuses = projection.statuses
        backupDates = projection.dates
        scheduleProjection()
    }

    func thumbnailData(for key: ThumbnailKey) async throws -> Data {
        guard !isSample, deviceState == .ready,
              key.sessionID == catalogSessionID,
              let provider = browser as? any ThumbnailProviding else { throw MediaSourceError.unavailable }
        try Task.checkCancellation()
        let data = try await provider.thumbnailData(
            for: key.resourceID, sessionID: key.sessionID, maximumPixelSize: key.maximumPixelSize
        )
        try Task.checkCancellation()
        guard catalogSessionID == key.sessionID, deviceState == .ready else { throw MediaSourceError.staleSession }
        return data
    }

    func shutdown() {
        backup.cancel()
        sourceGeneration += 1
        generation += 1
        projectionTask?.cancel()
        stopDeviceBrowsing()
    }

    func photoMetadata(for asset: MediaAsset, sessionID: UUID) async throws -> PhotoCameraMetadata {
        guard !isSample, deviceState == .ready, !backup.isBusy, catalogSessionID == sessionID,
              currentAsset(id: asset.id) == asset, let resourceID = asset.primaryResource?.id,
              let provider = browser as? any PhotoMetadataProviding else { throw MediaSourceError.unavailable }
        try Task.checkCancellation()
        let metadata = try await provider.photoMetadata(for: resourceID, sessionID: sessionID)
        try Task.checkCancellation()
        guard !isSample, catalogSessionID == sessionID, deviceState == .ready,
              currentAsset(id: asset.id) == asset else { throw MediaSourceError.staleSession }
        return metadata
    }

    private func stopDeviceBrowsing() {
        backup.suspendHistory(resetSource: true)
        backup.useDevice(nil)
        thumbnails.setSession(nil)
        catalogLoader?.stop()
        catalogLoader = nil
        browser?.stop()
        deviceTask?.cancel()
        deviceTask = nil
        browser = nil
        deviceInventory = DeviceInventory()
        lastSelectedDeviceID = nil
    }

    var isCatalogLoading: Bool { mediaScanState == .scanning || isCatalogPreparing }

    private func resetCatalogState() {
        thumbnailReuseIDs = [:]
        catalogSessionID = nil
        mediaScanState = nil
        mediaScanPercent = nil
        iCloudPhotosEnabled = false
        isCatalogPreparing = false
    }

    private func clearDeviceLibrary() {
        backup.suspendHistory(resetSource: true)
        thumbnails.setSession(nil)
        catalogLoader?.retireCurrentSession()
        resetCatalogState()
        generation += 1
        projectionTask?.cancel()
        isProjecting = false
        assets = []
        statuses = [:]
        backupDates = [:]
        lookup = [:]
        snapshot = .empty
        scrollReset += 1
        clearSelection()
        infoAsset = nil
    }

    private func applyInventory(_ value: DeviceInventory) {
        deviceInventory = value
        guard let selectedID = value.selectedID else { return }
        if let previous = lastSelectedDeviceID, previous != selectedID {
            backup.sourceBecameUnavailable()
            if !backup.isBusy { backup.dismissSummary() }
            clearDeviceLibrary()
            device = nil
            deviceState = .opening
            deviceMessage = nil
        }
        lastSelectedDeviceID = selectedID
    }

    private func shouldReceiveCatalog(_ source: DeviceMediaSnapshot) -> Bool {
        guard !isSample else { return false }
        guard let selector = browser as? any DeviceSelectionBrowsing else { return true }
        // Streams are independent: read the current selection before accepting either envelope.
        applyInventory(selector.inventory)
        applyConnection(selector.selectedConnection)
        return selector.selectedSessionID == source.sessionID
            || (selector.selectedSessionID == nil && source.state == .interrupted && catalogSessionID == source.sessionID)
    }

    private func receiveCatalog(_ source: DeviceMediaSnapshot) {
        guard !isSample else { return }
        catalogSessionID = source.sessionID
        thumbnails.setSession(source.state == .interrupted ? nil : source.sessionID)
        mediaScanState = source.state
        mediaScanPercent = source.percentComplete
        iCloudPhotosEnabled = source.iCloudPhotosEnabled == true
        isCatalogPreparing = true
    }

    private func applyCatalog(_ prepared: PreparedDeviceCatalog) {
        guard shouldReceiveCatalog(prepared.source), prepared.source.sessionID == catalogSessionID else { return }
        isCatalogPreparing = false
        // Keep the previous device's catalog useful while the same phone reconnects. A complete
        // empty catalog or a different phone always replaces it rather than claiming stale media.
        if prepared.assets.isEmpty, prepared.source.state != .complete,
           assets.first?.deviceID == prepared.source.deviceID { return }
        if let previousDevice = assets.first?.deviceID, previousDevice != prepared.source.deviceID {
            scrollReset += 1
        }
        assets = prepared.assets
        thumbnailReuseIDs = prepared.thumbnailReuseIDs
        lookup = prepared.lookup
        if let infoAsset { self.infoAsset = lookup[infoAsset.id] }
        backup.acceptCatalog(source: prepared.source, assets: prepared.assets, device: device)
        refreshBackupStatuses()
    }

    private func apply(_ event: DeviceEvent) {
        guard !isSample else { return }
        if let selector = browser as? any DeviceSelectionBrowsing {
            applyInventory(selector.inventory)
            applyConnection(selector.selectedConnection)
            return
        }
        switch event {
        case .inventoryChanged(let inventory):
            applyInventory(inventory)
        case .stateChanged(let connection):
            applyConnection(connection)
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

    func setDateGroupSelected(_ selected: Bool, target: DateGroupSelectionTarget) {
        guard let section = currentDateGroup(for: target) else { return }
        selection.setSelected(selected, ids: section.assets.map(\.id), orderedIDs: snapshot.orderedIDs)
        if selected || activeID.map({ !selection.selectedIDs.contains($0) }) != false {
            activeID = selection.anchorID
        }
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
        let query = CatalogQuery(
            filter: filter, search: search, sort: sort, grouping: grouping, captureDateRange: captureDateRange
        )
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
