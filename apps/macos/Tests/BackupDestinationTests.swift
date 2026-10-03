import Foundation
import Testing
@testable import CloakRoll

@MainActor
struct BackupDestinationTests {
    @Test func choosingFolderPersistsRecordAndReopensWithoutFilesystemWork() async throws {
        let storage = try DestinationTestDefaults()
        let probe = DestinationOperationProbe()
        let store = BackupDestinationStore(defaults: storage.value, operations: probe.operations, selectFolder: { Self.folder })
        #expect(await store.chooseFolder())
        let record = try #require(store.selection)
        #expect(record.displayName == "Backup")
        #expect(record.lastKnownPath == Self.folder.path)
        #expect(!record.bookmarkData.isEmpty)
        #expect(store.readiness == .available)
        #expect(probe.counts.started == probe.counts.stopped)
        #expect(!probe.counts.usedMainThread)

        let before = probe.counts.validated
        let reopened = BackupDestinationStore(defaults: storage.value, operations: probe.operations)
        #expect(reopened.selection == record)
        #expect(probe.counts.validated == before)
    }

    @Test func cancellingPickerKeepsSelectionAndDoesNoFilesystemWork() async throws {
        let storage = try DestinationTestDefaults(record: Self.record())
        let probe = DestinationOperationProbe()
        let store = BackupDestinationStore(defaults: storage.value, operations: probe.operations, selectFolder: { nil })
        let previous = store.selection
        #expect(await store.chooseFolder() == false)
        #expect(store.selection == previous)
        #expect(!store.isChoosing)
        #expect(store.errorMessage == nil)
        #expect(probe.counts.started == 0)
    }

    @Test func selectingValidatedSameFolderPreservesUUIDButAnotherFolderDoesNot() async throws {
        let original = Self.record()
        let storage = try DestinationTestDefaults(record: original)
        let probe = DestinationOperationProbe()
        var chosen = Self.folder
        let store = BackupDestinationStore(defaults: storage.value, operations: probe.operations, selectFolder: { chosen })
        #expect(await store.chooseFolder())
        #expect(store.selection?.id == original.id)

        chosen = URL(fileURLWithPath: "/Volumes/Other/Backup", isDirectory: true)
        #expect(await store.chooseFolder())
        #expect(store.selection?.id != original.id)
        #expect(probe.counts.started == probe.counts.stopped)
    }

    @Test func pickerPersistenceFailureKeepsPriorSelectionAndBalancesScope() async throws {
        let original = Self.record()
        let storage = try DestinationTestDefaults(record: original)
        let probe = DestinationOperationProbe()
        let store = BackupDestinationStore(
            defaults: storage.value, operations: probe.operations, selectFolder: { Self.folder },
            saveRecord: { _ in throw BackupDestinationError.persistenceFailed }
        )
        #expect(await store.chooseFolder() == false)
        #expect(store.selection == original)
        #expect(store.errorMessage == BackupDestinationError.persistenceFailed.message)
        #expect(probe.counts.started == probe.counts.stopped)
        store.clearError()
        #expect(store.errorMessage == nil)
    }

    @Test func staleBookmarkRefreshPreservesUUIDAndLeaseHoldsScope() async throws {
        let original = Self.record()
        let storage = try DestinationTestDefaults(record: original)
        let probe = DestinationOperationProbe()
        var operations = probe.operations
        operations.resolveBookmark = { _ in ResolvedBackupBookmark(url: Self.folder, isStale: true) }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        let lease = try await store.acquireLease()
        #expect(lease.url == Self.folder)
        #expect(lease.destinationID == original.id)
        #expect(store.selection?.id == original.id)
        #expect(store.selection?.bookmarkData != original.bookmarkData)
        #expect(probe.counts.started == 1)
        #expect(probe.counts.stopped == 0)
        lease.release()
        lease.release()
        #expect(probe.counts.stopped == 1)
        let reopened = BackupDestinationStore(defaults: storage.value, operations: operations)
        #expect(reopened.selection == store.selection)
    }

    @Test func staleRefreshPersistenceFailureReleasesLeaseAndKeepsRecord() async throws {
        let original = Self.record()
        let storage = try DestinationTestDefaults(record: original)
        let probe = DestinationOperationProbe()
        var operations = probe.operations
        operations.resolveBookmark = { _ in ResolvedBackupBookmark(url: Self.folder, isStale: true) }
        let store = BackupDestinationStore(
            defaults: storage.value, operations: operations,
            saveRecord: { _ in throw BackupDestinationError.persistenceFailed }
        )
        await #expect(throws: BackupDestinationError.persistenceFailed) { _ = try await store.acquireLease() }
        #expect(store.selection == original)
        #expect(probe.counts.started == 1)
        #expect(probe.counts.stopped == 1)
    }

    @Test func deniedScopeDoesNotValidateOrFallBackToStoredPath() async throws {
        let original = Self.record()
        let storage = try DestinationTestDefaults(record: original)
        let probe = DestinationOperationProbe(grantsAccess: false)
        let store = BackupDestinationStore(defaults: storage.value, operations: probe.operations)
        await #expect(throws: BackupDestinationError.accessDenied) { _ = try await store.acquireLease() }
        #expect(store.selection == original)
        #expect(probe.counts.validated == 0)
        #expect(probe.counts.stopped == 0)
    }

    @Test func unavailableResolvedFolderNeverUsesLastKnownPath() async throws {
        let original = Self.record(path: "/not-a-fallback")
        let storage = try DestinationTestDefaults(record: original)
        let probe = DestinationOperationProbe()
        var operations = probe.operations
        operations.validateFolder = { url in
            #expect(url == Self.folder)
            throw BackupDestinationError.unavailable
        }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        await #expect(throws: BackupDestinationError.unavailable) { _ = try await store.acquireLease() }
        #expect(store.selection == original)
        #expect(probe.counts.started == probe.counts.stopped)
    }

    @Test func invalidAndReadOnlyFoldersFailBeforeBookmarkCreation() async throws {
        for failure in [BackupDestinationError.notDirectory, .notWritable] {
            let storage = try DestinationTestDefaults()
            let probe = DestinationOperationProbe()
            var operations = probe.operations
            operations.validateFolder = { _ in throw failure }
            let store = BackupDestinationStore(defaults: storage.value, operations: operations, selectFolder: { Self.folder })
            #expect(await store.chooseFolder() == false)
            #expect(store.selection == nil)
            #expect(store.errorMessage == failure.message)
            #expect(probe.counts.bookmarks == 0)
            #expect(probe.counts.started == probe.counts.stopped)
        }
    }

    @Test func containerLeaseDoesNotStopAnAccessThatNeverStarted() async throws {
        let storage = try DestinationTestDefaults(record: Self.record())
        let probe = DestinationOperationProbe(grantsAccess: false)
        var operations = probe.operations
        operations.requiresSecurityScope = { _ in false }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        let lease = try await store.acquireLease()
        lease.release()
        #expect(probe.counts.started == 1)
        #expect(probe.counts.stopped == 0)
    }

    @Test func leaseDeinitAndConcurrentReleaseBalanceExactlyOnce() async throws {
        let storage = try DestinationTestDefaults(record: Self.record())
        let probe = DestinationOperationProbe()
        let store = BackupDestinationStore(defaults: storage.value, operations: probe.operations)
        var abandoned: DestinationLease? = try await store.acquireLease()
        #expect(abandoned != nil)
        weak let observedLease = abandoned
        abandoned = nil
        #expect(observedLease == nil) // No queued task may retain the returned lease past this call.
        #expect(probe.counts.stopped == 1)
        let lease = try await store.acquireLease()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<16 { group.addTask { lease.release() } }
        }
        #expect(probe.counts.started == 2)
        #expect(probe.counts.stopped == 2)
    }

    @Test func cancelledAcquisitionReleasesScopeAfterValidationReturns() async throws {
        let storage = try DestinationTestDefaults(record: Self.record())
        let probe = DestinationOperationProbe()
        let entered = AsyncStream<Void>.makeStream()
        let releaseValidation = DispatchSemaphore(value: 0)
        var operations = probe.operations
        operations.validateFolder = { _ in
            entered.continuation.yield(())
            releaseValidation.wait()
            return "Backup"
        }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        let acquisition = Task { try await store.acquireLease() }
        for await _ in entered.stream { break }
        acquisition.cancel()
        releaseValidation.signal()
        await #expect(throws: CancellationError.self) { _ = try await acquisition.value }
        #expect(probe.counts.started == 1)
        #expect(probe.counts.stopped == 1)
    }

    @Test func checkingWithoutASelectionDoesNoFilesystemWork() async throws {
        let storage = try DestinationTestDefaults()
        let probe = DestinationOperationProbe()
        let store = BackupDestinationStore(defaults: storage.value, operations: probe.operations)
        await store.checkFolder()
        #expect(store.readiness == .unchecked && store.errorMessage == nil)
        #expect(probe.counts.started == 0 && probe.counts.validated == 0 && probe.counts.bookmarks == 0)
    }

    @Test(arguments: [BackupDestinationError.unavailable, .notWritable])
    func failedChecksHaveInlineErrorsAndRetryReleasesEveryScope(failure: BackupDestinationError) async throws {
        let storage = try DestinationTestDefaults(record: Self.record())
        let probe = DestinationOperationProbe()
        let availability = DestinationAvailabilityProbe(failure: failure)
        var operations = probe.operations
        let validate = operations.validateFolder
        operations.validateFolder = { url in
            try availability.check()
            return try validate(url)
        }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        let identifier = store.selection?.id
        await store.checkFolder()
        #expect(store.readiness == .unavailable(failure.message))
        #expect(store.errorMessage == nil) // Explicit checks do not also open the modal error path.
        availability.setFailure(nil)
        await store.checkFolder()
        #expect(store.readiness == .available && store.selection?.id == identifier)
        #expect(probe.counts.started == 2 && probe.counts.stopped == 2)
        #expect(!probe.counts.usedMainThread)
    }

    @Test func deniedFolderCheckNeverValidatesOrFallsBackToTheDisplayPath() async throws {
        let storage = try DestinationTestDefaults(record: Self.record(path: "/not-a-fallback"))
        let probe = DestinationOperationProbe(grantsAccess: false)
        let store = BackupDestinationStore(defaults: storage.value, operations: probe.operations)
        await store.checkFolder()
        #expect(store.readiness == .unavailable(BackupDestinationError.accessDenied.message))
        #expect(store.errorMessage == nil)
        #expect(probe.counts.validated == 0 && probe.counts.stopped == 0)
    }

    @Test func cachedSuccessfulCheckDoesNotAuthorizeALaterLease() async throws {
        let storage = try DestinationTestDefaults(record: Self.record())
        let probe = DestinationOperationProbe()
        let availability = DestinationAvailabilityProbe()
        var operations = probe.operations
        let validate = operations.validateFolder
        operations.validateFolder = { url in
            try availability.check()
            return try validate(url)
        }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        await store.checkFolder()
        #expect(store.readiness == .available)
        availability.setFailure(.unavailable)
        await #expect(throws: BackupDestinationError.unavailable) { _ = try await store.acquireLease() }
        #expect(store.readiness == .unavailable(BackupDestinationError.unavailable.message))
        #expect(probe.counts.started == probe.counts.stopped)
    }

    @Test func cancelledCheckRetainsItsScopeUntilValidationSettles() async throws {
        let storage = try DestinationTestDefaults(record: Self.record())
        let probe = DestinationOperationProbe()
        let gate = DestinationCheckGate()
        defer { gate.release() }
        var operations = probe.operations
        operations.validateFolder = { _ in try gate.validateFirst() }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        let check = Task { await store.checkFolder() }
        try await gate.waitUntilEntered()
        #expect(store.readiness == .checking && probe.counts.stopped == 0)
        check.cancel()
        gate.release()
        await check.value
        #expect(store.readiness == .unchecked && store.errorMessage == nil)
        #expect(probe.counts.started == 1 && probe.counts.stopped == 1)
    }

    @Test func olderCancelledCheckCannotClearANewerSuccessfulCheck() async throws {
        let storage = try DestinationTestDefaults(record: Self.record())
        let probe = DestinationOperationProbe()
        let gate = DestinationCheckGate()
        defer { gate.release() }
        var operations = probe.operations
        operations.validateFolder = { _ in try gate.validateFirst() }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        let old = Task { await store.checkFolder() }
        try await gate.waitUntilEntered()
        await store.checkFolder()
        #expect(store.readiness == .available)
        old.cancel()
        gate.release()
        await old.value
        #expect(store.readiness == .available && store.errorMessage == nil)
        #expect(probe.counts.started == 2 && probe.counts.stopped == 2)
    }

    @Test func anOldFailedCheckCannotReplaceAReselectedFoldersStatus() async throws {
        let storage = try DestinationTestDefaults(record: Self.record())
        let probe = DestinationOperationProbe()
        let gate = DestinationCheckGate(failure: .unavailable)
        defer { gate.release() }
        let other = URL(fileURLWithPath: "/Volumes/Other/Backup", isDirectory: true)
        var operations = probe.operations
        operations.resolveBookmark = { data in
            let value = String(decoding: data, as: UTF8.self)
            let url = value.hasPrefix("new:") ? URL(fileURLWithPath: String(value.dropFirst(4))) : Self.folder
            return ResolvedBackupBookmark(url: url, isStale: false)
        }
        operations.validateFolder = { _ in try gate.validateFirst() }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations, selectFolder: { other })
        let originalID = store.selection?.id
        let old = Task { await store.checkFolder() }
        try await gate.waitUntilEntered()
        #expect(await store.chooseFolder())
        #expect(store.selection?.id != originalID && store.readiness == .available)
        gate.release()
        await old.value
        #expect(store.readiness == .available && store.errorMessage == nil)
        #expect(store.selection?.lastKnownPath == other.path)
        #expect(probe.counts.started == probe.counts.stopped)
    }

    @Test func folderRetryAlsoRetriesBlockedLibraryHistory() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        let record = try #require(fixture.controller.destination.selection)
        let storage = try DestinationTestDefaults(record: record)
        let availability = DestinationAvailabilityProbe(failure: .unavailable)
        var operations = fixture.destinationFixture.scope.operations
        let validate = operations.validateFolder
        operations.validateFolder = { url in
            try availability.check()
            return try validate(url)
        }
        let destination = BackupDestinationStore(defaults: storage.value, operations: operations)
        let controller = LibraryBackupController(destination: destination, persistence: fixture.persistence)
        controller.acceptCatalog(source: catalog.source, assets: [catalog.asset], device: catalog.device)
        try await waitForPersistentState { !controller.isCheckingHistory }
        #expect(controller.historyErrorMessage != nil)
        availability.setFailure(nil)
        await controller.checkDestination()
        try await waitForPersistentState { !controller.isCheckingHistory }
        #expect(controller.historyErrorMessage == nil && destination.readiness == .available)
        #expect(fixture.destinationFixture.scope.counts.active == 0)
        #expect(controller.snapshot == nil && !controller.isBusy)
        await controller.checkDestination()
        #expect(!controller.isCheckingHistory) // A healthy history is not rescanned on Settings entry.
    }

    @Test func folderCheckDoesNotPersistARefreshedBookmark() async throws {
        let original = Self.record()
        let storage = try DestinationTestDefaults(record: original)
        let probe = DestinationOperationProbe()
        var operations = probe.operations
        operations.resolveBookmark = { _ in ResolvedBackupBookmark(url: Self.folder, isStale: true) }
        let store = BackupDestinationStore(
            defaults: storage.value, operations: operations,
            saveRecord: { _ in Issue.record("An advisory check must not persist a bookmark") }
        )
        await store.checkFolder()
        #expect(store.readiness == .available && store.selection == original)
        #expect(probe.counts.started == 1 && probe.counts.stopped == 1)
        #expect(probe.counts.bookmarks == 1)
    }

    @Test func olderFolderCheckCannotInvalidateANewerRealLease() async throws {
        let original = Self.record()
        let storage = try DestinationTestDefaults(record: original)
        let probe = DestinationOperationProbe()
        let gate = DestinationAcquisitionGate()
        defer { gate.releaseAll() }
        var operations = probe.operations
        operations.resolveBookmark = { _ in ResolvedBackupBookmark(url: Self.folder, isStale: true) }
        operations.validateFolder = { _ in try gate.validate() }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        let check = Task { await store.checkFolder() }
        try await gate.waitForCalls(1)
        let acquisition = Task { try await store.acquireLease() }
        try await gate.waitForCalls(2)
        gate.release(0)
        await check.value
        #expect(store.selection == original)
        gate.release(1)
        let lease = try await acquisition.value
        lease.release()
        #expect(store.selection?.id == original.id && store.selection?.bookmarkData != original.bookmarkData)
        #expect(store.readiness == .available && store.errorMessage == nil)
        #expect(probe.counts.started == 2 && probe.counts.stopped == 2)
    }

    @Test(arguments: [true, false])
    func newerFolderCheckCannotInvalidateAnOlderRealLease(checkFinishesFirst: Bool) async throws {
        let original = Self.record()
        let storage = try DestinationTestDefaults(record: original)
        let probe = DestinationOperationProbe()
        let gate = DestinationAcquisitionGate()
        defer { gate.releaseAll() }
        var operations = probe.operations
        operations.resolveBookmark = { _ in ResolvedBackupBookmark(url: Self.folder, isStale: true) }
        operations.validateFolder = { _ in try gate.validate() }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        let acquisition = Task { try await store.acquireLease() }
        try await gate.waitForCalls(1)
        let check = Task { await store.checkFolder() }
        try await gate.waitForCalls(2)
        if checkFinishesFirst {
            gate.release(1)
            await check.value
            #expect(store.selection == original && store.readiness == .available)
        }
        gate.release(0)
        let lease = try await acquisition.value
        lease.release()
        if !checkFinishesFirst {
            gate.release(1)
            await check.value
        }
        #expect(store.selection?.id == original.id && store.selection?.bookmarkData != original.bookmarkData)
        #expect(store.readiness == (checkFinishesFirst ? .available : .unchecked))
        #expect(!store.readiness.isChecking && store.errorMessage == nil)
        #expect(probe.counts.started == 2 && probe.counts.stopped == 2)
    }

    @Test func aFailedCheckForAnAlreadyRefreshedBookmarkLeavesNoStaleErrorOrSpinner() async throws {
        let original = Self.record()
        let storage = try DestinationTestDefaults(record: original)
        let probe = DestinationOperationProbe()
        let gate = DestinationAcquisitionGate(failingCall: 1)
        defer { gate.releaseAll() }
        var operations = probe.operations
        operations.resolveBookmark = { _ in ResolvedBackupBookmark(url: Self.folder, isStale: true) }
        operations.validateFolder = { _ in try gate.validate() }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        let acquisition = Task { try await store.acquireLease() }
        try await gate.waitForCalls(1)
        let check = Task { await store.checkFolder() }
        try await gate.waitForCalls(2)
        gate.release(0)
        let lease = try await acquisition.value
        lease.release()
        #expect(store.selection?.bookmarkData != original.bookmarkData)
        gate.release(1)
        await check.value
        #expect(store.readiness == .unchecked && store.errorMessage == nil)
        #expect(probe.counts.started == 2 && probe.counts.stopped == 2)
    }

    @Test func concurrentRealLeasesSerializeStaleRefreshAndKeepIndependentScopes() async throws {
        let original = Self.record()
        let storage = try DestinationTestDefaults(record: original)
        let probe = DestinationOperationProbe()
        let gate = DestinationAcquisitionGate()
        defer { gate.releaseAll() }
        var operations = probe.operations
        operations.resolveBookmark = { _ in ResolvedBackupBookmark(url: Self.folder, isStale: true) }
        operations.validateFolder = { _ in try gate.validate() }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        let first = Task { try await store.acquireLease() }
        try await gate.waitForCalls(1)
        var secondRequested = false
        let second = Task {
            secondRequested = true
            return try await store.acquireLease()
        }
        try await waitForPersistentState { secondRequested }
        #expect(gate.numberOfCalls == 1 && probe.counts.started == 1)
        gate.release(0)
        let firstLease = try await first.value
        defer { firstLease.release() }
        try await gate.waitForCalls(2)
        #expect(probe.counts.started == 2 && probe.counts.stopped == 0)
        gate.release(1)
        let secondLease = try await second.value
        secondLease.release()
        #expect(probe.counts.stopped == 1)
        #expect(firstLease.destinationID == secondLease.destinationID && firstLease !== secondLease)
        #expect(store.selection?.id == original.id && store.selection?.bookmarkData != original.bookmarkData)
        #expect(store.readiness == .available && store.errorMessage == nil)
        firstLease.release()
        #expect(probe.counts.started == probe.counts.stopped)
    }

    @Test func cancelledQueuedLeaseDoesNoAccessAndLetsTheNextCallerProceed() async throws {
        let storage = try DestinationTestDefaults(record: Self.record())
        let probe = DestinationOperationProbe()
        let gate = DestinationAcquisitionGate()
        defer { gate.releaseAll() }
        var operations = probe.operations
        operations.validateFolder = { _ in try gate.validate() }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        let first = Task { try await store.acquireLease() }
        try await gate.waitForCalls(1)
        var cancelledRequested = false
        let cancelled = Task {
            cancelledRequested = true
            return try await store.acquireLease()
        }
        try await waitForPersistentState { cancelledRequested }
        cancelled.cancel()
        var finalRequested = false
        let final = Task {
            finalRequested = true
            return try await store.acquireLease()
        }
        try await waitForPersistentState { finalRequested }
        #expect(gate.numberOfCalls == 1)
        gate.release(0)
        let firstLease = try await first.value
        firstLease.release()
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        try await gate.waitForCalls(2)
        gate.release(1)
        let finalLease = try await final.value
        finalLease.release()
        #expect(store.readiness == .available && store.errorMessage == nil)
        #expect(probe.counts.started == 2 && probe.counts.stopped == 2)
    }

    @Test func cancelledActiveLeaseReleasesItsScopeBeforeTheNextAcquisition() async throws {
        let storage = try DestinationTestDefaults(record: Self.record())
        let probe = DestinationOperationProbe()
        let gate = DestinationAcquisitionGate()
        defer { gate.releaseAll() }
        var operations = probe.operations
        operations.validateFolder = { _ in try gate.validate() }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations)
        let first = Task { try await store.acquireLease() }
        try await gate.waitForCalls(1)
        let next = Task { try await store.acquireLease() }
        first.cancel()
        gate.release(0)
        await #expect(throws: CancellationError.self) { _ = try await first.value }
        try await gate.waitForCalls(2)
        #expect(probe.counts.started == 2 && probe.counts.stopped == 1)
        gate.release(1)
        let nextLease = try await next.value
        nextLease.release()
        #expect(store.readiness == .available && store.errorMessage == nil)
        #expect(probe.counts.started == probe.counts.stopped)
    }

    @Test(arguments: [false, true])
    func reselectingAFolderInvalidatesInFlightAndQueuedAcquisitions(sameFolder: Bool) async throws {
        let original = Self.record()
        let storage = try DestinationTestDefaults(record: original)
        let probe = DestinationOperationProbe()
        let gate = DestinationCheckGate()
        defer { gate.release() }
        let chosen = sameFolder ? Self.folder : URL(fileURLWithPath: "/Volumes/Other/Backup", isDirectory: true)
        var operations = probe.operations
        operations.resolveBookmark = { data in
            let value = String(decoding: data, as: UTF8.self)
            let url = value.hasPrefix("new:") ? URL(fileURLWithPath: String(value.dropFirst(4))) : Self.folder
            return ResolvedBackupBookmark(url: url, isStale: true)
        }
        operations.validateFolder = { _ in try gate.validateFirst() }
        let store = BackupDestinationStore(defaults: storage.value, operations: operations, selectFolder: { chosen })
        let first = Task { try await store.acquireLease() }
        try await gate.waitUntilEntered()
        var nextRequested = false
        let next = Task {
            nextRequested = true
            return try await store.acquireLease()
        }
        try await waitForPersistentState { nextRequested }
        #expect(await store.chooseFolder())
        let selected = try #require(store.selection)
        #expect((selected.id == original.id) == sameFolder)
        #expect(store.readiness == .available)
        gate.release()
        await #expect(throws: BackupDestinationError.selectionChanged) { _ = try await first.value }
        await #expect(throws: BackupDestinationError.selectionChanged) { _ = try await next.value }
        #expect(store.selection == selected && store.readiness == .available && store.errorMessage == nil)
        #expect(probe.counts.started == probe.counts.stopped)
    }

    private nonisolated static let folder = URL(fileURLWithPath: "/Volumes/Test/Backup", isDirectory: true)

    private static func record(path: String = folder.path) -> BackupDestination {
        BackupDestination(id: UUID(), displayName: "Backup", lastKnownPath: path, bookmarkData: Data("saved".utf8))
    }
}

private final class DestinationTestDefaults {
    let name = "CloakRollDestinationTests-" + UUID().uuidString
    let value: UserDefaults

    init(record: BackupDestination? = nil) throws {
        value = try #require(UserDefaults(suiteName: name))
        if let record { value.set(try JSONEncoder().encode(record), forKey: BackupDestinationStore.storageKey) }
    }

    deinit { value.removePersistentDomain(forName: name) }
}

private final class DestinationOperationProbe: @unchecked Sendable {
    struct Counts {
        var started = 0
        var stopped = 0
        var validated = 0
        var bookmarks = 0
        var usedMainThread = false
    }

    private let lock = NSLock()
    private var recorded = Counts()
    private let grantsAccess: Bool
    var counts: Counts { lock.withLock { recorded } }

    init(grantsAccess: Bool = true) { self.grantsAccess = grantsAccess }

    var operations: BackupDestinationOperations {
        BackupDestinationOperations(
            resolveBookmark: { _ in
                ResolvedBackupBookmark(url: URL(fileURLWithPath: "/Volumes/Test/Backup", isDirectory: true), isStale: false)
            },
            makeBookmark: { [self] url in
                record { $0.bookmarks += 1 }
                return Data(("new:" + url.path).utf8)
            },
            startAccess: { [self] _ in
                record { $0.started += 1 }
                return grantsAccess
            },
            stopAccess: { [self] _ in record { $0.stopped += 1 } },
            requiresSecurityScope: { _ in true },
            validateFolder: { [self] _ in
                record { $0.validated += 1 }
                return "Backup"
            },
            sameFolder: { $0 == $1 }
        )
    }

    private func record(_ update: (inout Counts) -> Void) {
        lock.withLock {
            update(&recorded)
            recorded.usedMainThread = recorded.usedMainThread || Thread.isMainThread
        }
    }
}

private final class DestinationAvailabilityProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var failure: BackupDestinationError?

    init(failure: BackupDestinationError? = nil) { self.failure = failure }

    func setFailure(_ failure: BackupDestinationError?) { lock.withLock { self.failure = failure } }

    func check() throws {
        if let failure = lock.withLock({ failure }) { throw failure }
    }
}

private final class DestinationCheckGate: @unchecked Sendable {
    private let condition = NSCondition()
    private let failure: BackupDestinationError?
    private var entered = false
    private var released = false

    init(failure: BackupDestinationError? = nil) { self.failure = failure }

    func validateFirst() throws -> String {
        condition.lock()
        defer { condition.unlock() }
        guard !entered else { return "Backup" }
        entered = true
        while !released { condition.wait() }
        if let failure { throw failure }
        return "Backup"
    }

    @MainActor func waitUntilEntered() async throws {
        try await waitForPersistentState { condition.withLock { entered } }
    }

    func release() { condition.withLock { released = true; condition.broadcast() } }
}

private final class DestinationAcquisitionGate: @unchecked Sendable {
    private let condition = NSCondition()
    private let failingCall: Int?
    private var entered = 0
    private var released: Set<Int> = []
    private var allReleased = false

    var numberOfCalls: Int { condition.withLock { entered } }

    init(failingCall: Int? = nil) { self.failingCall = failingCall }

    func validate() throws -> String {
        condition.lock()
        defer { condition.unlock() }
        let ordinal = entered
        entered += 1
        while !allReleased && !released.contains(ordinal) { condition.wait() }
        if ordinal == failingCall { throw BackupDestinationError.unavailable }
        return "Backup"
    }

    @MainActor func waitForCalls(_ count: Int) async throws {
        try await waitForPersistentState { condition.withLock { entered >= count } }
    }

    func release(_ ordinal: Int) {
        condition.withLock { _ = released.insert(ordinal); condition.broadcast() }
    }

    func releaseAll() { condition.withLock { allReleased = true; condition.broadcast() } }
}
