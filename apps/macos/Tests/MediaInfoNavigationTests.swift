import DeviceCapture
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Media Info browsing", .timeLimit(.minutes(1)))
@MainActor
struct MediaInfoNavigationTests {
    @Test func boundariesDoNotWrapAndBrowsingKeepsOneSheet() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let ordered = model.snapshot.sections.flatMap(\.assets)
        let first = try #require(ordered.first)
        model.infoAsset = first
        let sheetID = model.presentation?.id
        #expect(model.infoPosition(for: first)?.index == 0)
        #expect(model.infoPosition(for: first)?.previousID == nil)
        model.moveInfo(.previous, from: first)
        #expect(model.infoAsset == first)
        for (index, asset) in ordered.enumerated().dropLast() {
            model.moveInfo(.next, from: asset)
            #expect(model.infoAsset == ordered[index + 1])
            #expect(model.presentation?.id == sheetID)
            #expect(model.infoPosition(for: ordered[index + 1])?.index == index + 1)
        }
        let last = try #require(ordered.last)
        #expect(model.infoPosition(for: last)?.nextID == nil)
        model.moveInfo(.next, from: last)
        #expect(model.infoAsset == last)
        model.moveInfo(.previous, from: last)
        #expect(model.infoAsset == ordered[ordered.count - 2])
    }

    @Test func browsingDoesNotChangeBackupSelectionOrRangeAnchor() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let ordered = model.snapshot.sections.flatMap(\.assets)
        model.select(ordered[0], extendingRange: false, toggling: false)
        model.select(ordered[2], extendingRange: true, toggling: false)
        let selection = model.selection
        let active = model.activeID
        let candidates = model.backupCandidates(context: nil)
        model.infoAsset = ordered[5] // A context-menu Info outside the selected batch.
        model.moveInfo(.next, from: ordered[5])
        #expect(model.infoAsset == ordered[6])
        #expect(model.selection == selection && model.activeID == active)
        #expect(model.backupCandidates(context: nil) == candidates)
        model.infoAsset = nil
        model.showSelectedInfo()
        #expect(model.infoAsset == ordered[2])
    }

    @Test func filterSearchAndSortDefineTheBrowsingOrder() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 80)
        model.filter = .videos
        try await waitForPersistentState { !model.isProjecting }
        let first = try #require(model.snapshot.sections.flatMap(\.assets).first)
        let count = model.snapshot.filteredCount
        try #require(count > 1 && count < model.assets.count)
        model.infoAsset = first
        #expect(model.infoPosition(for: first)?.count == count)
        model.sort = .oldestFirst
        #expect(model.infoPosition(for: first) == nil)
        model.moveInfo(.next, from: first)
        #expect(model.infoAsset == first)
        try await waitForPersistentState { !model.isProjecting }
        let position = try #require(model.infoPosition(for: first))
        #expect(position.index == count - 1 && position.nextID == nil)
        model.moveInfo(.previous, from: first)
        let previous = try #require(model.infoAsset)
        #expect(previous.kind == .video && previous.id == model.snapshot.orderedIDs[count - 2])
        model.search = previous.filename
        try await waitForPersistentState { !model.isProjecting }
        let result = try #require(model.infoPosition(for: previous))
        #expect(result.count == 1 && result.previousID == nil && result.nextID == nil)
        model.search = "no filename will match this"
        try await waitForPersistentState { !model.isProjecting }
        #expect(model.infoPosition(for: previous) == nil)
        model.moveInfo(.next, from: previous)
        #expect(model.infoAsset == previous)
    }

    @Test func staleActionsCannotReplaceANewerItemOrAnotherPresentation() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let ordered = model.snapshot.sections.flatMap(\.assets)
        let first = ordered[0]
        model.infoAsset = first
        model.moveInfo(.next, from: first)
        model.moveInfo(.next, from: first) // Queued activation from the old item.
        #expect(model.infoAsset == ordered[1])
        model.presentation = .help(.gettingStarted)
        model.moveInfo(.previous, from: ordered[1])
        #expect(model.infoAsset == nil && model.presentation?.id == "help:gettingStarted")
        model.presentation = nil
        model.moveInfo(.next, from: first)
        #expect(model.presentation == nil)
    }

    @Test func unavailableDeviceOrLibraryContextDisablesNavigation() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let asset = try #require(model.snapshot.sections.flatMap(\.assets).first)
        model.infoAsset = asset
        for state in [DeviceConnectionState.disconnected, .opening, .restricted, .unavailable] {
            model.deviceState = state
            #expect(model.infoPosition(for: asset) == nil)
            model.moveInfo(.next, from: asset)
            #expect(model.infoAsset == asset)
        }
        model.deviceState = .ready
        model.navigation = .backupHistory
        #expect(model.infoPosition(for: asset) == nil)
        model.navigation = .library(.all)
        model.isSample = false
        model.device = ConnectedDevice(id: "another-phone", displayName: "Another iPhone")
        #expect(model.infoPosition(for: asset) == nil)
        model.moveInfo(.next, from: asset)
        #expect(model.infoAsset == asset)
    }

    @Test func changedOrRemovedAssetsCannotNavigateThroughAnOldSnapshot() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let original = try #require(model.assets.first)
        let changed = MediaAsset(id: original.id, deviceID: original.deviceID, resources: [], kind: .photo, createdAt: nil)
        model.infoAsset = changed
        #expect(model.infoPosition(for: changed) == nil)
        model.moveInfo(.next, from: changed)
        #expect(model.infoAsset == changed)
        await model.loadSample(count: 0)
        model.moveInfo(.next, from: original)
        #expect(model.infoAsset == nil)
    }
}
