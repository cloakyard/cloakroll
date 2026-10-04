import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Connected iPhone selection", .timeLimit(.minutes(1)))
@MainActor
struct AppModelDeviceSelectionTests {
    @Test func switchingClearsSelectionAndRejectsRetiredCatalogAndConnectionEnvelopes() async throws {
        let source = SelectableLibrarySource()
        let model = AppModel(makeBrowser: { source })
        model.startLive()
        defer { model.shutdown() }
        let old = source.snapshot(filename: "old.HEIC")
        let oldConnection = source.selectedConnection
        source.send(old)
        try await waitUntil { model.assets.count == 1 && !model.isProjecting }
        let asset = try #require(model.assets.first)
        model.select(asset, extendingRange: false, toggling: false)
        model.infoAsset = asset

        #expect(model.selectDevice(id: source.secondID))
        #expect(model.assets.isEmpty)
        #expect(model.snapshot.orderedIDs.isEmpty)
        #expect(model.selection.selectedIDs.isEmpty)
        #expect(model.infoAsset == nil)
        #expect(model.catalogSessionID == nil)
        #expect(model.device == source.selectedConnection.device)
        source.send(old)
        source.sendRaw(.stateChanged(oldConnection))
        let current = source.snapshot(filename: "new.HEIC")
        source.send(current)
        try await waitUntil { model.assets.first?.filename == "new.HEIC" && !model.isProjecting }
        #expect(model.catalogSessionID == current.sessionID)
        #expect(model.assets.allSatisfy { $0.deviceID == source.selectedConnection.device?.id })
        #expect(model.device == source.selectedConnection.device)
        #expect(model.statuses.values.allSatisfy { $0 == .notBackedUp })
    }

    @Test func catalogBeforeInventoryEventUsesAuthoritativeSelectionAndDeviceIdentity() async throws {
        let source = SelectableLibrarySource()
        let model = AppModel(makeBrowser: { source })
        model.startLive()
        defer { model.shutdown() }
        source.send(source.snapshot(filename: "old.HEIC"))
        try await waitUntil { model.assets.count == 1 && !model.isProjecting }
        model.presentation = .help(.gettingStarted)
        let oldInventory = source.inventory
        let oldConnection = source.selectedConnection
        // The catalog stream may be consumed before events, even when core publishes events first.
        source.switchWithoutEvents(to: source.secondID)
        source.send(source.snapshot(filename: "new.HEIC"))
        try await waitUntil { model.assets.first?.filename == "new.HEIC" && !model.isProjecting }
        source.sendRaw(.inventoryChanged(oldInventory))
        source.sendRaw(.stateChanged(oldConnection))
        source.send(source.snapshot(filename: "newest.HEIC", revision: 2))
        try await waitUntil { model.assets.first?.filename == "newest.HEIC" && !model.isProjecting }
        #expect(model.deviceInventory.selectedID == source.secondID)
        #expect(model.device == source.selectedConnection.device)
        #expect(model.presentation?.id == LibraryPresentation.help(.gettingStarted).id)
    }

    @Test func rejectedAndUnchangedSelectionPreserveTheCurrentLibrary() async throws {
        let source = SelectableLibrarySource()
        let model = AppModel(makeBrowser: { source })
        model.startLive()
        defer { model.shutdown() }
        source.send(source.snapshot(filename: "kept.HEIC"))
        try await waitUntil { model.assets.count == 1 && !model.isProjecting }
        let asset = try #require(model.assets.first)
        model.select(asset, extendingRange: false, toggling: false)
        let session = model.catalogSessionID
        let reset = model.scrollReset
        #expect(model.selectDevice(id: source.firstID))
        source.allowsSelection = false
        #expect(!model.selectDevice(id: source.secondID))
        #expect(!model.selectDevice(id: UUID()))
        #expect(model.assets == [asset])
        #expect(model.selection.selectedIDs == [asset.id])
        #expect(model.catalogSessionID == session)
        #expect(model.scrollReset == reset)
    }

    @Test func activeAndStoppingBackupsRejectSwitchBeforeCallingTheCaptureSource() async throws {
        let fixture = try BackupControllerFixture()
        let source = SelectableLibrarySource()
        let model = AppModel(makeBrowser: { source }, backup: fixture.controller)
        model.startLive()
        defer { model.shutdown() }
        fixture.start([BackupLibraryFixture.asset()], session: UUID())
        #expect(!model.canSelectDevice)
        #expect(!model.selectDevice(id: source.secondID))
        await fixture.source.waitForStart("still")
        fixture.controller.cancel()
        #expect(!model.selectDevice(id: source.secondID))
        #expect(source.selectCalls == 0)
        await fixture.source.waitForCancellation("still")
        try await fixture.source.finish("still", bytes: Data([1, 2, 3]))
        await fixture.controller.waitUntilStopped()
        #expect(model.canSelectDevice)
        #expect(model.selectDevice(id: source.secondID))
        #expect(source.selectCalls == 1)
    }

    @Test func sameNamedPhonesHaveDistinctStableMenuChoicesWithoutExposingIdentity() {
        let first = DeviceSelectionItem(id: UUID(), displayName: "iPhone")
        let second = DeviceSelectionItem(id: UUID(), displayName: "iPhone")
        let third = DeviceSelectionItem(id: UUID(), displayName: "Work iPhone")
        let options = DevicePickerOption.make(from: [first, second, third])
        #expect(options.map(\.title) == ["iPhone (1)", "iPhone (2)", "Work iPhone"])
        #expect(options.map(\.id) == [first.id, second.id, third.id])
        #expect(DevicePickerOption.make(from: [first, second, third]) == options)
    }

    @Test func leavingLiveModeClearsInventoryAndIgnoresOldDeviceEvents() async throws {
        let source = SelectableLibrarySource()
        let model = AppModel(makeBrowser: { source })
        model.startLive()
        defer { model.shutdown() }
        try await waitUntil { model.deviceInventory.devices.count == 2 }
        await model.loadSample(count: 1)
        source.sendRaw(.inventoryChanged(source.inventory))
        source.send(source.snapshot(filename: "late.HEIC"))
        await Task.yield()
        #expect(model.deviceInventory.devices.isEmpty)
        #expect(!model.canSelectDevice)
        #expect(!model.selectDevice(id: source.secondID))
        #expect(model.assets.first?.id.hasPrefix("fixture-") == true)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !condition() && clock.now < deadline { await Task.yield() }
        try #require(condition(), "The selected iPhone did not reach the expected library state")
    }
}

@MainActor
private final class SelectableLibrarySource: DeviceMediaSource, DeviceSelectionBrowsing {
    let events: AsyncStream<DeviceEvent>
    let catalogs: AsyncStream<DeviceMediaSnapshot>
    let firstID = UUID()
    let secondID = UUID()
    private(set) var inventory = DeviceInventory()
    private(set) var selectedSessionID: UUID?
    private(set) var selectedConnection = DeviceConnection(state: .disconnected)
    private(set) var selectCalls = 0
    var allowsSelection = true
    private let eventContinuation: AsyncStream<DeviceEvent>.Continuation
    private let catalogContinuation: AsyncStream<DeviceMediaSnapshot>.Continuation

    init() {
        let events = AsyncStream<DeviceEvent>.makeStream()
        self.events = events.stream
        eventContinuation = events.continuation
        let catalogs = AsyncStream<DeviceMediaSnapshot>.makeStream()
        self.catalogs = catalogs.stream
        catalogContinuation = catalogs.continuation
        inventory = DeviceInventory(devices: [
            DeviceSelectionItem(id: firstID, displayName: "iPhone"),
            DeviceSelectionItem(id: secondID, displayName: "iPhone")
        ])
        switchWithoutEvents(to: firstID)
    }

    func start() {
        sendRaw(.inventoryChanged(inventory))
        sendRaw(.stateChanged(selectedConnection))
    }

    func stop() {}
    func retry() {}

    func selectDevice(id: UUID) -> Bool {
        selectCalls += 1
        guard inventory.devices.contains(where: { $0.id == id }), allowsSelection else { return false }
        guard inventory.selectedID != id else { return true }
        switchWithoutEvents(to: id)
        start()
        return true
    }

    func switchWithoutEvents(to id: UUID) {
        inventory = DeviceInventory(devices: inventory.devices, selectedID: id)
        selectedSessionID = UUID()
        let identity = DeviceIdentity(kind: .persistent, value: id == firstID ? "first-phone" : "second-phone")
        selectedConnection = DeviceConnection(device: ConnectedDevice(identity: identity, name: "iPhone"), state: .ready)
    }

    func snapshot(filename: String, revision: UInt64 = 1) -> DeviceMediaSnapshot {
        let deviceID = selectedConnection.device!.id
        let record = SourceMediaRecord(id: "shared-runtime-id", deviceID: deviceID, filename: filename, uti: "public.heic", byteCount: 3)
        return DeviceMediaSnapshot(
            sessionID: selectedSessionID!, deviceID: deviceID, revision: revision, records: [record], state: .complete
        )
    }

    func send(_ snapshot: DeviceMediaSnapshot) { catalogContinuation.yield(snapshot) }
    func sendRaw(_ event: DeviceEvent) { eventContinuation.yield(event) }
}
