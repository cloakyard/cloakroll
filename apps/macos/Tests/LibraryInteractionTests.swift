import DeviceCapture
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Native library interactions and preferences")
@MainActor
struct LibraryInteractionTests {
    @Test func browsingChoicesAndSettingsPaneSurviveModelRelaunch() throws {
        let suite = "CloakRollPreferencesTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LibraryPreferences(defaults: defaults)
        let first = AppModel(makeBrowser: { MockDeviceBrowserService() }, preferences: preferences)
        #expect(first.thumbnailSize == .medium)
        first.thumbnailSize = .large
        first.sort = .oldestFirst
        first.grouping = .month
        first.settingsTab = .backup
        let reopened = AppModel(makeBrowser: { MockDeviceBrowserService() }, preferences: preferences)
        #expect(reopened.thumbnailSize == .large)
        #expect(reopened.sort == .oldestFirst)
        #expect(reopened.grouping == .month)
        #expect(reopened.settingsTab == .backup)
    }

    @Test func invalidSavedChoiceDoesNotEraseOtherValidPreferences() throws {
        let suite = "CloakRollPreferencesTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("future-size", forKey: "browsing.thumbnailSize")
        defaults.set("oldestFirst", forKey: "browsing.sort")
        defaults.set(100, forKey: "browsing.grouping")
        defaults.set("missing-pane", forKey: "settings.selectedTab")
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() }, preferences: LibraryPreferences(defaults: defaults))
        #expect(model.thumbnailSize == .medium)
        #expect(model.sort == .oldestFirst)
        #expect(model.grouping == .automatic)
        #expect(model.settingsTab == .general)
    }

    @Test func contextBackupTargetsTheClickedItemOrItsSelectedBatchWithoutChangingSelection() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let ordered = model.snapshot.sections.flatMap(\.assets)
        let first = try #require(ordered.first)
        let second = ordered[1]
        let outside = ordered[2]
        model.select(first, extendingRange: false, toggling: false)
        model.select(second, extendingRange: false, toggling: true)
        let selection = model.selection.selectedIDs
        #expect(model.backupCandidates(context: first) == [first, second])
        #expect(model.backupCandidates(context: outside) == [outside])
        #expect(model.selection.selectedIDs == selection)
        #expect(model.selectedFilenames == [first.filename, second.filename])
        #expect(!model.canBackUp(asset: first)) // Sample context actions cannot transfer.
        model.navigation = .backupHistory
        #expect(!model.canBackUp)
        #expect(!model.canRetryBackup)
        model.filter = .photos
        #expect(model.navigation == .library(.photos))
    }
}
