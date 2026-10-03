import AppKit
import Foundation
import Testing
@testable import CloakRoll

@Suite("Graceful quit coordination", .timeLimit(.minutes(1)))
@MainActor
struct AppTerminationTests {
    @Test(arguments: [false, true])
    func idleQuitNeedsNoAsynchronousReply(hasController: Bool) throws {
        let fixture = try BackupControllerFixture()
        let delegate = AppDelegate()
        if hasController { delegate.backup = fixture.controller }
        let result = delegate.requestTermination { _ in
            Issue.record("An idle quit must not schedule an AppKit termination reply")
        }
        #expect(result == .terminateNow)
        #expect(fixture.scope.counts.active == 0)
    }

    @Test(arguments: [false, true])
    func quitWaitsForPhysicalSourceAndDurableSessionBeforeOneReply(sourceFails: Bool) async throws {
        let fixture = try PersistentLibraryFixture()
        let catalog = PersistentLibraryCatalog(companion: true)
        try await fixture.accept(catalog)
        let source = ControlledBackupOriginals()
        let controller = fixture.controller
        controller.start(assets: [catalog.asset], sessionID: catalog.source.sessionID) { request, progress in
            try await source.download(request, progress: progress)
        }
        await source.waitForStart("old-still")
        try await source.finish("old-still", bytes: Data([1, 2, 3]))
        await source.waitForStart("old-motion")
        let delegate = AppDelegate()
        delegate.backup = controller
        var didShutDown = false
        delegate.onTerminate = { didShutDown = true }
        var replies: [Bool] = []
        let result = delegate.requestTermination { shouldTerminate in
            #expect(!controller.isBusy && !controller.isStopping)
            #expect(fixture.destinationFixture.scope.counts.active == 0)
            #expect(controller.snapshot?.phase == .cancelled)
            replies.append(shouldTerminate)
        }
        #expect(result == .terminateLater)
        await source.waitForCancellation("old-motion")
        #expect(controller.isBusy && controller.isStopping)
        #expect(fixture.destinationFixture.scope.counts.active == 1)
        #expect(replies.isEmpty && !didShutDown)
        #expect(delegate.requestTermination { _ in
            Issue.record("Repeated Quit must share the first pending termination request")
        } == .terminateLater)
        if sourceFails { try await source.fail("old-motion") } else {
            try await source.finish("old-motion", bytes: Data([4, 5]))
        }
        try await waitForPersistentState { !replies.isEmpty }
        #expect(replies == [true] && !didShutDown)
        #expect(controller.snapshot?.verifiedResources == 1 && controller.snapshot?.completedAssets == 0)
        let sessions = try await fixture.persistence.store().recentSessions(limit: 10)
        let session = try #require(sessions.first)
        #expect(session.status == .cancelled && session.finishedAt != nil)
        #expect(session.verifiedResources == 1 && session.completedAssets == 0)
        let destinationID = try #require(controller.destination.selection?.id)
        let pending = try await fixture.persistence.store().pendingJournal(destinationID: destinationID)
        #expect(pending.count == 1 && pending.first?.staging.resourceID == "old-motion")
        #expect(pending.first?.publication == nil)
        #expect(delegate.requestTermination { _ in Issue.record("The settled request must be cleared") } == .terminateNow)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(didShutDown)
    }
}
