import DeviceCapture
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@MainActor
struct AppModelTests {
    @Test func deviceEventsReachThePresentationModel() async throws {
        let browser = MockDeviceBrowserService()
        let model = AppModel(makeBrowser: { browser })
        model.startLive()
        let device = ConnectedDevice(id: "test-phone", displayName: "Test iPhone")
        browser.send(DeviceConnection(device: device, state: .restricted))
        try await waitUntil { model.deviceState == .restricted }
        #expect(model.device == device)
        #expect(!model.isSample)
        browser.send(DeviceConnection(device: device, state: .ready))
        try await waitUntil { model.deviceState == .ready }
        browser.send(DeviceConnection(state: .disconnected))
        try await waitUntil { model.deviceState == .disconnected }
        #expect(model.device == nil)
        await model.loadSample(count: 0)
    }

    @Test func leavingLiveModeRejectsLaterDeviceEvents() async throws {
        let browser = MockDeviceBrowserService()
        let model = AppModel(makeBrowser: { browser })
        model.startLive()
        await model.loadSample(count: 20)
        browser.send(DeviceConnection(state: .unavailable, message: "Old device event"))
        await Task.yield()
        #expect(model.isSample)
        #expect(model.deviceState == .ready)
        #expect(model.assets.count == 20)
        #expect(model.deviceMessage == nil)
    }

    @Test func rangeNavigationTracksItsActiveEndpoint() async {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        model.moveSelection(.right, columns: 4, extending: false)
        #expect(model.activeID == model.snapshot.orderedIDs[0])
        model.moveSelection(.right, columns: 4, extending: true)
        model.moveSelection(.right, columns: 4, extending: true)
        #expect(model.selection.selectedIDs.count == 3)
        model.moveSelection(.left, columns: 4, extending: true)
        #expect(model.selection.selectedIDs.count == 2)
        model.showSelectedInfo()
        #expect(model.infoAsset?.id == model.activeID)
        model.clearSelection()
        #expect(model.activeID == nil)
    }

    @Test func queryChangesDuringLoadingUseTheNewestSource() async {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let load = Task { await model.loadSample(count: 10_000) }
        await Task.yield()
        model.filter = .videos
        model.search = "IMG_"
        await load.value
        #expect(model.assets.count == 10_000)
        #expect(model.snapshot.sections.flatMap(\.assets).allSatisfy { $0.kind == .video })
        #expect(!model.isProjecting)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !condition() && clock.now < deadline { await Task.yield() }
        try #require(condition(), "The expected device event did not reach AppModel")
    }
}
