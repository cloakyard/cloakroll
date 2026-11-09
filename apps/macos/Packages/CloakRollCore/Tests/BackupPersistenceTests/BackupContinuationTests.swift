import BackupEngine
import BackupPersistence
import Foundation
import Testing

@Suite("Persistent backup continuation")
struct BackupContinuationTests {
    @Test(arguments: [true, false])
    func sameConnectionRetriesSessionOnlyEvidenceWithoutAllowingReconnect(persistent: Bool) async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let first = HistoryFixture(persistent: persistent)
        let id = try await first.begin(store, reusable: false, layout: .byDevice)
        try await store.finishSession(id: id, result: .init(phase: .failed))
        let plan = try await store.continuation(sessionID: id, destinationID: first.destinationID,
                                                 identity: first.identity(reusable: false))
        #expect(plan.assetIDs == first.assets.map(\.id))
        #expect(plan.unavailableAssets == 0)

        let reconnected = HistoryFixture(destinationID: first.destinationID, persistent: persistent)
        await #expect(throws: BackupStoreError.invalidIdentity) {
            try await reconnected.begin(store, reusable: false, layout: .byDevice, continuing: id)
        }
        let changed = HistoryFixture(sessionID: first.sourceSessionID, destinationID: first.destinationID,
                                     prefix: "changed", persistent: persistent)
        await #expect(throws: BackupStoreError.invalidIdentity) {
            try await changed.begin(store, reusable: false, layout: .byDevice, continuing: id)
        }
        let child = try await first.begin(store, reusable: false, layout: .byDevice, continuing: id)
        #expect(try await store.recentSessions().contains { $0.id == child })
    }

    @Test func relaunchMapsChangedRuntimeIDsAndKeepsOriginalLayout() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let first = HistoryFixture()
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let id = try await first.begin(store, layout: .byDeviceFlat)
        try await store.recordVerified(sessionID: id, record: first.record())
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        let current = HistoryFixture(destinationID: first.destinationID, prefix: "new")
        let plan = try await reopened.continuation(sessionID: id, destinationID: first.destinationID, identity: current.identity())
        #expect(plan.assetIDs == ["new-asset"])
        #expect(plan.unavailableAssets == 0)
        #expect(plan.folderLayout == .byDeviceFlat)
        #expect(try await current.candidates(reopened).count == 1)
        let continued = try await current.begin(reopened, layout: .byDeviceFlat, continuing: id)
        let sessions = try await reopened.recentSessions()
        #expect(sessions.first { $0.id == id }?.canContinue == false)
        #expect(sessions.first { $0.id == continued }?.folderLayout == .byDeviceFlat)
        await #expect(throws: BackupStoreError.invalidIdentity) {
            try await current.begin(reopened, layout: .byDeviceFlat, continuing: id)
        }
    }

    @Test func mismatchedPhoneFolderOrOrganizationCannotContinue() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let first = HistoryFixture()
        let id = try await first.begin(store, layout: .byDevice)
        try await store.finishSession(id: id, result: .init(phase: .cancelled))
        await #expect(throws: BackupStoreError.invalidIdentity) {
            try await store.continuation(sessionID: id, destinationID: UUID(), identity: first.identity())
        }
        let another = HistoryFixture(deviceValue: "other", destinationID: first.destinationID)
        await #expect(throws: BackupStoreError.invalidIdentity) {
            try await store.continuation(sessionID: id, destinationID: first.destinationID, identity: another.identity())
        }
        await #expect(throws: BackupStoreError.invalidIdentity) {
            try await first.begin(store, layout: .byDeviceFlat, continuing: id)
        }
        #expect(try await store.recentSessions().count == 1)
    }

    @Test func changedCompanionAndNonreusableIdentityStayUnmatched() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let first = HistoryFixture()
        let id = try await first.begin(store, layout: .byDevice)
        try await store.finishSession(id: id, result: .init(phase: .failed))
        let changed = HistoryFixture(destinationID: first.destinationID, motionBytes: 9)
        let plan = try await store.continuation(sessionID: id, destinationID: first.destinationID, identity: changed.identity())
        #expect(plan.assetIDs.isEmpty)
        #expect(plan.unavailableAssets == 1)
        await #expect(throws: BackupStoreError.invalidIdentity) {
            try await changed.begin(store, layout: .byDevice, continuing: id)
        }
        let ambiguous = try await store.continuation(sessionID: id, destinationID: first.destinationID,
                                                     identity: first.identity(reusable: false))
        #expect(ambiguous.unavailableAssets == 1)
    }

    @Test func legacyAttemptHasNoInventedOrganization() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let first = HistoryFixture()
        let id = try await first.begin(store)
        try await store.finishSession(id: id, result: .init(phase: .failed))
        #expect(try await store.recentSessions().first?.canContinue == false)
    }
}
