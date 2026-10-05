import Foundation
import Testing
@testable import CloakRoll

@Suite("Remembered backup destinations", .timeLimit(.minutes(1)))
@MainActor
struct BackupDestinationRecallTests {
    @Test func returningAfterSwitchAndRelaunchPreservesDestinationIdentity() async throws {
        let fixture = try DestinationRecallFixture()
        var chosen = fixture.first
        let store = fixture.store { chosen }
        #expect(await store.chooseFolder())
        let first = try #require(store.selection)
        chosen = fixture.second
        #expect(await store.chooseFolder())
        let second = try #require(store.selection)
        #expect(second.id != first.id)

        let reopened = fixture.store { chosen }
        #expect(reopened.selection == second)
        chosen = fixture.first
        #expect(await reopened.chooseFolder())
        #expect(reopened.selection?.id == first.id)
        chosen = fixture.second
        #expect(await reopened.chooseFolder())
        #expect(reopened.selection?.id == second.id)
    }

    @Test func renamedFolderKeepsIdentityAndReplacementAtOldPathDoesNot() async throws {
        let fixture = try DestinationRecallFixture()
        var chosen = fixture.first
        let store = fixture.store { chosen }
        #expect(await store.chooseFolder())
        let original = try #require(store.selection)
        chosen = fixture.second
        #expect(await store.chooseFolder())
        let moved = fixture.root.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.moveItem(at: fixture.first, to: moved)
        try FileManager.default.createDirectory(at: fixture.first, withIntermediateDirectories: true)
        chosen = moved
        #expect(await store.chooseFolder())
        #expect(store.selection?.id == original.id)
        chosen = fixture.first
        #expect(await store.chooseFolder())
        #expect(store.selection?.id != original.id)
    }

    @Test func legacySelectionSurvivesUpgradeAndReturnAfterSwitch() async throws {
        let fixture = try DestinationRecallFixture()
        let record = BackupDestination(id: UUID(), displayName: "Backup", lastKnownPath: fixture.first.path,
                                       bookmarkData: try DestinationRecallFixture.operations.makeBookmark(fixture.first))
        fixture.defaults.set(try JSONEncoder().encode(record), forKey: BackupDestinationStore.storageKey)
        let store = fixture.store { fixture.second }
        #expect(store.selection == record)
        #expect(await store.chooseFolder())
        let reopened = fixture.store { fixture.first }
        #expect(await reopened.chooseFolder())
        #expect(reopened.selection?.id == record.id)
    }

    @Test func unresolvableRememberedBookmarkDoesNotPreventChoosingAnotherFolder() async throws {
        let fixture = try DestinationRecallFixture()
        let first = fixture.store { fixture.first }
        #expect(await first.chooseFolder())
        let originalID = first.selection?.id
        var operations = DestinationRecallFixture.operations
        operations.resolveBookmark = { _ in throw BackupDestinationError.unavailable }
        let store = BackupDestinationStore(defaults: fixture.defaults, operations: operations, selectFolder: { fixture.second })
        #expect(await store.chooseFolder())
        #expect(store.selection?.id != originalID)
        #expect(store.readiness.message != nil)
    }
}

/// Real folders, bookmarks and filesystem identity; no external-volume or iPhone claim.
@MainActor
final class DestinationRecallFixture {
    let root: URL
    let first: URL
    let second: URL
    let defaults: UserDefaults
    private let domain = "CloakRollDestinationRecall-" + UUID().uuidString

    init() throws {
        defaults = try #require(UserDefaults(suiteName: domain))
        root = FileManager.default.temporaryDirectory.appendingPathComponent(domain, isDirectory: true)
        first = root.appendingPathComponent("First/Backup", isDirectory: true)
        second = root.appendingPathComponent("Second/Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
    }

    func store(select: @escaping @MainActor () async -> URL?) -> BackupDestinationStore {
        BackupDestinationStore(defaults: defaults, operations: Self.operations, selectFolder: select)
    }

    static var operations: BackupDestinationOperations {
        var operations = BackupDestinationOperations.live
        // Test-owned temporary folders need no security grant. Keep the real bookmark
        // resolver and filesystem comparator, independent of test-host entitlements.
        operations.makeBookmark = { try $0.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
        operations.resolveBookmark = { data in
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            return ResolvedBackupBookmark(url: url, isStale: stale)
        }
        operations.startAccess = { _ in false }
        operations.requiresSecurityScope = { _ in false }
        return operations
    }

    deinit {
        UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: root)
    }
}
