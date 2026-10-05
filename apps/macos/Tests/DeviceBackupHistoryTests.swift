import BackupPersistence
import Foundation
import Testing
@testable import CloakRoll

@Suite("Sidebar device backup history", .timeLimit(.minutes(1)))
@MainActor
struct DeviceBackupHistoryTests {
    @Test func readsDeviceHistoryIndependentlyOfTheHistoryScreenFilter() async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog()
        try await fixture.accept(catalog)
        try await fixture.backup(catalog)
        await fixture.persistence.applySessionFilter(.init(deviceKey: "another-phone", outcome: .unfinished))
        #expect(fixture.persistence.recentSessions.isEmpty)
        let summary = DeviceBackupHistory()
        await summary.load(deviceKey: catalog.device.id) {
            try await fixture.persistence.store().lastCompletedSession(deviceKey: catalog.device.id)
        }
        guard case .loaded(let session?) = summary.state else { Issue.record("Missing device backup"); return }
        #expect(session.completedAssets == 1 && session.verifiedBytes == 3)
        #expect(fixture.persistence.sessionsRevision > 0)
    }

    @Test func failedReadsAreNotPresentedAsNoBackupsAndCanRetry() async {
        let summary = DeviceBackupHistory()
        await summary.load(deviceKey: "phone") { throw BackupStoreError.unavailable }
        #expect(summary.state == .unavailable)
        await summary.load(deviceKey: "phone") { nil }
        #expect(summary.state == .loaded(nil))
        #expect(summary.state(for: "different-phone") == .loading)
    }

    @Test(arguments: [false, true])
    func switchingDevicesRejectsOlderResultsAndErrors(fails: Bool) async throws {
        let summary = DeviceBackupHistory()
        let pending = PendingDeviceSummary()
        let first = Task { await summary.load(deviceKey: "first") { try await pending.read() } }
        try await pending.waitForRead()
        await summary.load(deviceKey: "second") { nil }
        await pending.finish(fails: fails)
        await first.value
        #expect(summary.deviceKey == "second" && summary.state == .loaded(nil))
        #expect(summary.state(for: "first") == .loading)
    }

    @Test func cancelledReadDoesNotPublishItsResult() async throws {
        let summary = DeviceBackupHistory()
        let pending = PendingDeviceSummary()
        let request = Task { await summary.load(deviceKey: "phone") { try await pending.read() } }
        try await pending.waitForRead()
        request.cancel()
        await pending.finish(fails: false)
        await request.value
        #expect(summary.state == .loading)
        await summary.load(deviceKey: "phone") { nil }
        #expect(summary.state == .loaded(nil))
    }
}

private actor PendingDeviceSummary {
    private var pending: CheckedContinuation<StoredBackupSession?, Error>?

    func read() async throws -> StoredBackupSession? {
        try await withCheckedThrowingContinuation { pending = $0 }
    }

    func finish(fails: Bool) {
        if fails {
            pending?.resume(throwing: BackupStoreError.unavailable)
        } else {
            pending?.resume(returning: StoredBackupSession(
                id: UUID(), deviceName: "Old iPhone", destinationID: UUID(), status: .completed,
                startedAt: Date(timeIntervalSince1970: 100), finishedAt: Date(timeIntervalSince1970: 200),
                totalAssets: 1, totalResources: 1, completedAssets: 1, verifiedResources: 1, verifiedBytes: 10, transferredBytes: 10
            ))
        }
        pending = nil
    }

    func waitForRead() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while pending == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(pending != nil)
    }
}
