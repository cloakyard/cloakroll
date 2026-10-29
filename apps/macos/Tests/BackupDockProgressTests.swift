import BackupEngine
import DeviceCapture
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Dock backup progress", .timeLimit(.minutes(1)))
@MainActor
struct BackupDockProgressTests {
    @Test func dockUsesDataBytesAndNeverRoundsIncompleteDataToOneHundred() {
        let partial = BackupSnapshot(phase: .downloading, totalAssets: 100, expectedBytes: 1_000,
                                     completedAssets: 90, verifiedBytes: 200,
                                     currentResourceBytes: 150, currentResourceExpectedBytes: 800)
        #expect(BackupDockState.make(snapshot: partial, isBackingUp: true, isStopping: false)?.percent == 35)
        let nearly = BackupSnapshot(phase: .verifying, expectedBytes: .max, verifiedBytes: .max - 1)
        #expect(BackupDockState.make(snapshot: nearly, isBackingUp: true, isStopping: false)?.percent == 99)
        #expect(BackupDockState.make(snapshot: .init(phase: .preparing), isBackingUp: true, isStopping: false)?.percent == nil)
        #expect(BackupDockState.make(snapshot: partial, isBackingUp: false, isStopping: false) == nil)
        #expect(BackupDockState.make(snapshot: .init(phase: .failed), isBackingUp: true, isStopping: false) == nil)
    }

    @Test func observedTransferUpdatesWithoutAWindowSkipsSamePercentageAndClearsOnCompletion() async throws {
        let fixture = try BackupControllerFixture()
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() }, backup: fixture.controller)
        var rendered: [BackupDockState?] = []
        let dock = BackupDockProgress(model: model) { rendered.append($0) }
        defer { dock.stop() }
        let asset = BackupLibraryFixture.asset(resource: .init(id: "still", filename: "IMG.HEIC", byteCount: 1_000))
        fixture.start([asset], session: UUID())
        await fixture.source.waitForStart("still")
        await fixture.source.report("still", downloadedBytes: 350)
        try await wait { rendered.last.flatMap { $0 }?.percent == 35 }
        let count = rendered.count
        // The engine publishes at most every 100 ms. Exercise a second published snapshot,
        // not one intentionally coalesced before reaching the Dock observer.
        try await Task.sleep(for: .milliseconds(120))
        await fixture.source.report("still", downloadedBytes: 351)
        try await wait { fixture.controller.snapshot?.currentResourceBytes == 351 }
        await Task.yield()
        #expect(rendered.count == count)
        try await fixture.source.finish("still", bytes: Data(repeating: 7, count: 1_000))
        await fixture.controller.waitUntilStopped()
        try await wait { !rendered.isEmpty && rendered.last! == nil }
        #expect(fixture.controller.snapshot?.phase == .completed)
    }

    @Test(arguments: ["failure", "stop", "disconnect"])
    func failureAndStopClearTheRingAfterSourceSettles(outcome: String) async throws {
        let fixture = try BackupControllerFixture()
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() }, backup: fixture.controller)
        var rendered: [BackupDockState?] = []
        let dock = BackupDockProgress(model: model) { rendered.append($0) }
        defer { dock.stop() }
        fixture.start([BackupLibraryFixture.asset()], session: UUID())
        await fixture.source.waitForStart("still")
        try await wait { rendered.last.flatMap { $0 } != nil }
        if outcome == "stop" { fixture.controller.cancel() }
        if outcome == "disconnect" { fixture.controller.sourceBecameUnavailable() }
        if outcome != "failure" {
            try await wait { rendered.last.flatMap { $0 }?.isStopping == true }
        }
        try await fixture.source.fail("still")
        await fixture.controller.waitUntilStopped()
        try await wait { rendered.last! == nil }
        #expect(fixture.scope.counts.active == 0)
    }

    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate())
    }
}
