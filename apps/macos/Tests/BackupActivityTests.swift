import Foundation
import Testing
@testable import CloakRoll

@Suite("Backup power activity ownership", .timeLimit(.minutes(1)))
@MainActor
struct BackupActivityTests {
    @Test func overlappingWorkOwnsSeparateTokensAndCancellationWaitsForCleanup() async throws {
        let probe = BackupActivityProbe()
        let firstGate = BackupActivityGate()
        let secondGate = BackupActivityGate()
        let first = Task {
            try await probe.activity.perform(reason: "First operation") {
                await firstGate.wait()
                try Task.checkCancellation()
            }
        }
        await firstGate.waitUntilEntered()
        let second = Task {
            try await probe.activity.perform(reason: "Second operation") {
                await secondGate.wait()
                // A committed result is not turned into cancellation by the wrapper.
                return 42
            }
        }
        await secondGate.waitUntilEntered()
        #expect(probe.activeCount == 2)
        first.cancel()
        second.cancel()
        #expect(probe.activeCount == 2)
        await firstGate.release()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(probe.activeCount == 1 && probe.ended == 1)
        await secondGate.release()
        #expect(try await second.value == 42)
        #expect(probe.activeCount == 0 && probe.ended == 2)
        #expect(probe.reasons == ["First operation", "Second operation"])
        #expect(probe.options.allSatisfy { $0.contains(.idleSystemSleepDisabled) && !$0.contains(.idleDisplaySleepDisabled) })
    }

    @Test func cancelledBeforeWorkDoesNotAcquireAnActivity() async {
        let probe = BackupActivityProbe()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await probe.activity.perform(reason: "Already stopped") { () -> Void in
                Issue.record("Cancelled work must not start")
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(probe.started == 0 && probe.ended == 0)
    }

    @Test(arguments: [false, true])
    func completionAndSourceFailureReleaseActivity(sourceFails: Bool) async throws {
        let probe = BackupActivityProbe()
        let fixture = try BackupControllerFixture(activity: probe.activity)
        fixture.start([BackupLibraryFixture.asset()], session: UUID())
        await fixture.source.waitForStart("still")
        #expect(probe.activeCount == 1 && probe.started == 1)
        if sourceFails { try await fixture.source.fail("still") } else {
            try await fixture.source.finish("still", bytes: Data([1, 2, 3]))
        }
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == (sourceFails ? .failed : .completed))
        #expect(probe.activeCount == 0 && probe.ended == 1)
        #expect(fixture.scope.counts.active == 0)
    }

    @Test func emptySelectionAndDismissedFolderPickerNeverKeepMacAwake() async throws {
        let probe = BackupActivityProbe()
        let fixture = try BackupControllerFixture(hasSelection: false, activity: probe.activity)
        fixture.start([], session: UUID())
        #expect(!fixture.controller.isBusy && probe.started == 0)
        fixture.start([BackupLibraryFixture.asset()], session: UUID())
        await fixture.controller.waitUntilStopped()
        #expect(!fixture.controller.isBusy && probe.started == 0 && probe.ended == 0)
        #expect(await fixture.source.totalCalls == 0)
    }

    @Test func unavailableFolderReleasesActivityWithoutCallingTheSource() async throws {
        let probe = BackupActivityProbe()
        let fixture = try BackupControllerFixture(activity: probe.activity)
        try FileManager.default.removeItem(at: fixture.folder)
        fixture.start([BackupLibraryFixture.asset()], session: UUID())
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == .failed)
        #expect(probe.started == 1 && probe.ended == 1 && probe.activeCount == 0)
        #expect(await fixture.source.totalCalls == 0)
    }

    @Test func activityCoversHistorySavingAndIncrementalVerificationButNotIdleHistoryRefresh() async throws {
        let probe = BackupActivityProbe()
        let fixture = try PersistentLibraryFixture(activity: probe.activity)
        let catalog = PersistentLibraryCatalog(companion: true)
        try await fixture.accept(catalog)
        #expect(probe.started == 0)
        var completions = 0
        fixture.controller.onStatusesChanged = {
            if fixture.controller.snapshot?.phase == .completed {
                #expect(probe.activeCount == 1)
                completions += 1
            }
        }
        defer { fixture.controller.onStatusesChanged = nil }
        try await fixture.backup(catalog)
        #expect(probe.started == 1 && probe.ended == 1)
        try await fixture.backup(catalog)
        #expect(fixture.controller.snapshot?.transferredBytes == 0)
        #expect(probe.started == 2 && probe.ended == 2 && probe.activeCount == 0)
        #expect(completions == 2)
        let sessions = try await fixture.persistence.store().recentSessions()
        #expect(sessions.count == 2 && sessions.allSatisfy { $0.status == .completed && $0.finishedAt != nil })
    }
}

@MainActor
final class BackupActivityProbe {
    private(set) var reasons: [String] = []
    private(set) var options: [ProcessInfo.ActivityOptions] = []
    private(set) var ended = 0
    private var active: Set<ObjectIdentifier> = []
    var started: Int { reasons.count }
    var activeCount: Int { active.count }

    var activity: BackupActivity {
        BackupActivity(begin: { options, reason in
            let token = NSObject()
            self.reasons.append(reason)
            self.options.append(options)
            self.active.insert(ObjectIdentifier(token))
            return token
        }, end: { token in
            #expect(self.active.remove(ObjectIdentifier(token)) != nil, "Each activity must end exactly once")
            self.ended += 1
        })
    }
}

private actor BackupActivityGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered?.resume()
            entered = nil
        }
    }
    func waitUntilEntered() async {
        if continuation != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
