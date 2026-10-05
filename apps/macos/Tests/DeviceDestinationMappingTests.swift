import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Per-iPhone backup folders", .timeLimit(.minutes(1)))
@MainActor
struct DeviceDestinationMappingTests {
    private let first = ConnectedDevice(identity: .init(kind: .persistent, value: "phone-one"), name: "iPhone")
    private let second = ConnectedDevice(identity: .init(kind: .persistent, value: "phone-two"), name: "iPhone")

    @Test func sameNamePhonesRestoreSeparateFoldersAfterSwitchAndRelaunch() async throws {
        let fixture = try DestinationRecallFixture()
        var chosen = fixture.first
        let store = fixture.store { chosen }
        store.selectDevice(first)
        #expect(store.selection == nil)
        #expect(await store.chooseFolder())
        let firstID = try #require(store.selection?.id)
        store.selectDevice(second)
        #expect(store.selection == nil)
        chosen = fixture.second
        #expect(await store.chooseFolder())
        let secondID = try #require(store.selection?.id)
        #expect(firstID != secondID)
        let reopened = fixture.store { nil }
        reopened.selectDevice(first)
        #expect(reopened.selection?.id == firstID)
        await reopened.checkFolder()
        #expect(reopened.readiness == .available)
        reopened.selectDevice(nil)
        #expect(reopened.selection?.id == firstID) // Offline history remains usable.
        reopened.selectDevice(second)
        #expect(reopened.selection?.id == secondID)
        await reopened.checkFolder()
        #expect(reopened.readiness == .available)
    }

    @Test func renamedPhoneKeepsMappingButSessionOnlyPhoneDoesNotPersistIt() async throws {
        let fixture = try DestinationRecallFixture()
        let store = fixture.store { fixture.first }
        store.selectDevice(first)
        #expect(await store.chooseFolder())
        let original = store.selection?.id
        store.selectDevice(ConnectedDevice(identity: first.identity!, name: "Renamed"))
        #expect(store.selection?.id == original)
        let temporary = ConnectedDevice(identity: .init(kind: .sessionOnly, value: "temporary"), name: "iPhone")
        store.selectDevice(temporary)
        #expect(store.selection == nil)
        #expect(await store.chooseFolder())
        let reopened = fixture.store { nil }
        reopened.selectDevice(temporary)
        #expect(reopened.selection == nil)
        reopened.selectDevice(first)
        #expect(reopened.selection?.id == original)
    }

    @Test func unavailableFolderKeepsMappingUntilUserChoosesReplacement() async throws {
        let fixture = try DestinationRecallFixture()
        var chosen = fixture.first
        let store = fixture.store { chosen }
        store.selectDevice(first)
        #expect(await store.chooseFolder())
        let original = try #require(store.selection)
        store.selectDevice(second)
        #expect(await store.chooseFolder()) // Sharing a root is also supported.
        try FileManager.default.removeItem(at: fixture.first)
        store.selectDevice(first)
        #expect(store.selection?.id == original.id)
        await store.checkFolder()
        #expect(store.readiness.message != nil)
        await #expect(throws: BackupDestinationError.unavailable) { _ = try await store.acquireLease() }
        chosen = fixture.second
        #expect(await store.chooseFolder())
        #expect(store.selection?.id != original.id)
        store.selectDevice(second)
        #expect(store.selection?.id == original.id)
    }

    @Test func switchingPhonesWhilePickerIsOpenCannotAssignTheResultToEitherPhone() async throws {
        let fixture = try DestinationRecallFixture()
        var finish: CheckedContinuation<URL?, Never>?
        let store = fixture.store { await withCheckedContinuation { finish = $0 } }
        store.selectDevice(first)
        let choosing = Task { await store.chooseFolder() }
        try await waitForPersistentState { finish != nil }
        store.selectDevice(second)
        finish?.resume(returning: fixture.first)
        #expect(await choosing.value == false)
        #expect(store.selection == nil && store.errorMessage == nil)
        store.selectDevice(first)
        #expect(store.selection == nil)
    }

    @Test func failedSaveDoesNotChangeRememberedPhoneMapping() async throws {
        let fixture = try DestinationRecallFixture()
        let initial = fixture.store { fixture.first }
        initial.selectDevice(first)
        #expect(await initial.chooseFolder())
        let original = try #require(initial.selection)
        let failing = BackupDestinationStore(defaults: fixture.defaults, operations: DestinationRecallFixture.operations,
                                              selectFolder: { fixture.second }, saveRecord: { _ in throw BackupDestinationError.persistenceFailed })
        failing.selectDevice(first)
        #expect(await failing.chooseFolder() == false)
        #expect(failing.selection == original)
        let reopened = fixture.store { nil }
        reopened.selectDevice(first)
        #expect(reopened.selection == original)
    }

    @Test func historicalMigrationRequiresMatchingCurrentDeviceAndKnownBookmark() async throws {
        let fixture = try DestinationRecallFixture()
        let store = fixture.store { fixture.first }
        #expect(await store.chooseFolder())
        let originalID = try #require(store.selection?.id)
        store.selectDevice(first)
        #expect(store.selection == nil)
        try store.restoreHistoricalDestination(originalID, device: second)
        #expect(store.selection == nil)
        try store.restoreHistoricalDestination(UUID(), device: first)
        #expect(store.selection == nil)
        try store.restoreHistoricalDestination(originalID, device: first)
        #expect(store.selection?.id == originalID)
        let reopened = fixture.store { nil }
        reopened.selectDevice(first)
        #expect(reopened.selection?.id == originalID)
    }

    @Test func replacedFolderCannotBeLeasedEvenWhenBookmarkResolvesToItsOldPath() async throws {
        let fixture = try DestinationRecallFixture()
        let store = fixture.store { fixture.first }
        store.selectDevice(first)
        #expect(await store.chooseFolder())
        let identifier = try #require(store.selection?.id)
        try FileManager.default.moveItem(at: fixture.first, to: fixture.root.appendingPathComponent("Original"))
        try FileManager.default.createDirectory(at: fixture.first, withIntermediateDirectories: true)
        var operations = DestinationRecallFixture.operations
        let replacement = fixture.first
        operations.resolveBookmark = { _ in ResolvedBackupBookmark(url: replacement, isStale: false) }
        let reopened = BackupDestinationStore(defaults: fixture.defaults, operations: operations, selectFolder: { nil })
        reopened.selectDevice(first)
        #expect(reopened.selection?.id == identifier)
        await reopened.checkFolder()
        #expect(reopened.readiness.message != nil)
        await #expect(throws: BackupDestinationError.unavailable) { _ = try await reopened.acquireLease() }
    }

    @Test(arguments: ["future-version", "missing-folder", "duplicate-id"])
    func invalidArchivesNeverRestorePartialDeviceMappings(_ corruption: String) async throws {
        let fixture = try DestinationRecallFixture()
        let store = fixture.store { fixture.first }
        store.selectDevice(first)
        #expect(await store.chooseFolder())
        let data = try #require(fixture.defaults.data(forKey: BackupDestinationStore.storageKey))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        switch corruption {
        case "future-version": object["version"] = 99
        case "missing-folder": object["deviceFolders"] = [first.id: UUID().uuidString]
        default:
            let records = try #require(object["destinations"] as? [[String: Any]])
            object["destinations"] = records + records
        }
        fixture.defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: BackupDestinationStore.storageKey)
        let reopened = fixture.store { nil }
        #expect(reopened.selection == nil && reopened.errorMessage != nil)
        reopened.selectDevice(first)
        #expect(reopened.selection == nil)
    }
}
