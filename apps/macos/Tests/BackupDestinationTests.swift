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
        abandoned = nil
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
