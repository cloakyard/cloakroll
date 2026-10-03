import DeviceCapture
import Testing
@testable import CloakRoll

@Suite("Contextual backup help")
@MainActor
struct LibraryHelpTests {
    @Test func helpAndInfoShareOnePresentationWithoutChangingTheLibraryContext() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let asset = try #require(model.assets.first)
        model.select(asset, extendingRange: false, toggling: false)
        let selected = model.selection.selectedIDs
        model.navigation = .backupHistory
        model.presentation = .help(.usbAvailability)
        #expect(model.infoAsset == nil)
        #expect(model.presentation?.id == "help:usbAvailability")
        #expect(model.selection.selectedIDs == selected)
        #expect(model.navigation == .backupHistory)

        model.infoAsset = asset
        #expect(model.presentation?.id == "media:\(asset.id)")
        #expect(model.infoAsset == asset)
        model.presentation = .help(.gettingStarted)
        #expect(model.infoAsset == nil)
        #expect(model.selection.selectedIDs == selected)
        model.presentation = nil
        #expect(model.infoAsset == nil)
    }

    @Test func restartingConnectionKeepsGuidanceOpenButClearsStaleMediaInfo() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let asset = try #require(model.assets.first)
        model.presentation = .help(.gettingStarted)
        model.startLive()
        #expect(model.presentation?.id == "help:gettingStarted")
        #expect(!model.isSample)

        model.infoAsset = asset
        await model.loadSample(count: 0)
        #expect(model.presentation == nil)
        #expect(model.infoAsset == nil)
    }
}
