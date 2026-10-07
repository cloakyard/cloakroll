import BackupPersistence
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("History check folder isolation", .timeLimit(.minutes(1)))
@MainActor
struct BackupHistoryRefinementTests {
    @Test func recalledHistoryFolderAndChangesNeverReassignEitherPhone() async throws {
        let fixture = try DestinationRecallFixture()
        let first = ConnectedDevice(identity: .init(kind: .persistent, value: "history-phone-one"), name: "iPhone")
        let second = ConnectedDevice(identity: .init(kind: .persistent, value: "history-phone-two"), name: "iPhone")
        var selected = fixture.first
        let source = fixture.store { selected }
        source.selectDevice(first)
        #expect(await source.chooseFolder())
        let original = try #require(source.selection)
        selected = fixture.second
        source.selectDevice(second)
        #expect(await source.chooseFolder())
        let current = try #require(source.selection)
        let preferences = fixture.defaults.data(forKey: BackupDestinationStore.storageKey)
        let check = source.selectionForHistoryCheck(destinationID: original.id, selectFolder: { fixture.second })
        #expect(check.selection == original)
        #expect(await check.chooseFolder())
        #expect(check.selection?.lastKnownPath == fixture.second.path)
        #expect(source.selection == current)
        #expect(fixture.defaults.data(forKey: BackupDestinationStore.storageKey) == preferences)
        let reopened = fixture.store { nil }
        reopened.selectDevice(first)
        #expect(reopened.selection == original)
        reopened.selectDevice(second)
        #expect(reopened.selection == current)
    }

    @Test func forgottenFolderNeverFallsBackToTheCurrentPhonesFolder() async throws {
        let fixture = try DestinationRecallFixture()
        let source = fixture.store { fixture.first }
        #expect(await source.chooseFolder())
        let check = source.selectionForHistoryCheck(destinationID: UUID(), selectFolder: { nil })
        #expect(check.selection == nil)
        #expect(await check.chooseFolder() == false)
        #expect(check.selection == nil && check.errorMessage == nil && !check.isChoosing)
        await #expect(throws: BackupDestinationError.noSelection) { try await check.acquireLease(readOnly: true) }
        #expect(source.selection != nil)
    }

    @Test func checkFolderSelectionRequiresReadAccessOnlyAndDoesNotPersist() async throws {
        let fixture = try BackupControllerFixture()
        let original = try #require(fixture.controller.destination.selection)
        var operations = fixture.scope.operations
        operations.validateFolder = { _ in throw BackupDestinationError.notWritable }
        let source = BackupDestinationStore(defaults: try PersistentTestDefaults(record: original), operations: operations,
                                            saveRecord: { _ in Issue.record("A history check must not persist a destination") })
        let check = source.selectionForHistoryCheck(destinationID: original.id, selectFolder: { fixture.folder })
        #expect(await check.chooseFolder())
        let lease = try await check.acquireLease(readOnly: true)
        #expect(lease.url == fixture.folder)
        lease.release()
        #expect(source.selection == original && source.readiness == .unchecked)
        #expect(fixture.scope.counts.active == 0)
    }

    @Test func cancelledFolderPickerKeepsThePreviousCheckAndBackupSelections() async throws {
        let fixture = try DestinationRecallFixture()
        let source = fixture.store { fixture.first }
        #expect(await source.chooseFolder())
        let original = try #require(source.selection)
        let check = source.selectionForHistoryCheck(destinationID: original.id, selectFolder: { nil })
        #expect(await check.chooseFolder() == false)
        #expect(check.selection == original && source.selection == original)
        #expect(check.errorMessage == nil && !check.isChoosing)
    }

    @Test func isolatedCheckValidatesSavedOriginalsWithoutChangingHistoryOrSelection() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog(companion: true)
        try await fixture.accept(catalog)
        try await fixture.backup(catalog)
        let sessions = try await fixture.persistence.store().recentSessions()
        let session = try #require(sessions.first)
        let original = fixture.controller.destination.selection
        let check = fixture.controller.destination.selectionForHistoryCheck(destinationID: session.destinationID)
        let checker = BackupSessionCheckController(activity: BackupActivityProbe().activity)
        await checker.run(session: session, selectedDestinationID: session.destinationID,
                          destination: check, persistence: fixture.persistence)
        #expect(checker.phase == .completed && checker.progress.matchingFiles == 2)
        #expect(checker.progress.unverifiedFiles == 0)
        #expect(try await fixture.persistence.store().recentSessions() == sessions)
        #expect(fixture.controller.destination.selection == original)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
    }

    @Test(arguments: [StoredBackupSessionStatus.cancelled, .interrupted, .failed, .recovered])
    func savedLivePhotoCompanionIsCheckableWithoutACompletedItem(status: StoredBackupSessionStatus) {
        let partial = session(status: status, verified: 1)
        #expect(partial.canCheckSavedFiles)
        #expect(partial.historySummary.hasPrefix("1 original saved"))
        let empty = session(status: status, verified: 0)
        #expect(!empty.canCheckSavedFiles && empty.historySummary == "No originals saved")
    }

    @Test func runningBackupsCannotBeCheckedWhileTheirOriginalsAreChanging() {
        #expect(!session(status: .running, verified: 1).canCheckSavedFiles)
    }

    private func session(status: StoredBackupSessionStatus, verified: Int) -> StoredBackupSession {
        StoredBackupSession(id: UUID(), deviceName: "iPhone", destinationID: UUID(), status: status,
                            startedAt: Date(), finishedAt: nil, totalAssets: 1, totalResources: 2,
                            completedAssets: 0, verifiedResources: verified, verifiedBytes: Int64(verified * 1024), transferredBytes: 0)
    }
}
