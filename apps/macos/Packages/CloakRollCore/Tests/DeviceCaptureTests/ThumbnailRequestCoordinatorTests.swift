import Foundation
import MediaModels
import Testing
@testable import DeviceCapture

@Suite("Physical thumbnail request ownership", .timeLimit(.minutes(1)))
@MainActor
struct ThumbnailRequestCoordinatorTests {
    @Test("Only two physical calls launch and queued callers advance after real callbacks")
    func concurrencyLimit() async throws {
        let fixture = ThumbnailFixture()
        let tasks = (0..<8).map { fixture.request($0) }
        try await waitUntil { fixture.coordinator.queuedCount == 6 }
        #expect(fixture.operation.started.count == 2)
        for _ in tasks {
            let count = fixture.operation.cleanupCount
            let identifier = try #require(fixture.operation.pending.first)
            fixture.operation.finish(identifier)
            try await waitUntil { fixture.operation.cleanupCount > count }
        }
        for (identifier, task) in tasks.enumerated() {
            #expect(try await task.value == Data([UInt8(identifier)]))
        }
        #expect(fixture.operation.peakOutstanding == 2)
        #expect(fixture.coordinator.outstandingCount == 0)
    }

    @Test("Cancelling a queued caller removes it without starting its framework operation")
    func queuedCancellation() async throws {
        let fixture = ThumbnailFixture()
        let first = fixture.request(0)
        let second = fixture.request(1)
        try await waitUntil { fixture.operation.started.count == 2 }
        let queued = fixture.request(2)
        try await waitUntil { fixture.coordinator.queuedCount == 1 }
        queued.cancel()
        await #expect(throws: CancellationError.self) { try await queued.value }
        #expect(fixture.coordinator.queuedCount == 0)
        #expect(!fixture.operation.started.contains(2))
        fixture.operation.finish(0)
        fixture.operation.finish(1)
        _ = try await first.value
        _ = try await second.value
    }

    @Test("Cancelling an active caller returns promptly while retaining the physical slot")
    func activeCancellationDoesNotFreeSlot() async throws {
        let fixture = ThumbnailFixture()
        let first = fixture.request(0)
        let second = fixture.request(1)
        try await waitUntil { fixture.operation.started.count == 2 }
        let third = fixture.request(2)
        try await waitUntil { fixture.coordinator.queuedCount == 1 }
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(fixture.coordinator.outstandingCount == 2)
        #expect(fixture.operation.cleanupCount == 0)
        #expect(!fixture.operation.started.contains(2))
        fixture.operation.finish(0)
        try await waitUntil { fixture.operation.started.contains(2) }
        #expect(fixture.coordinator.outstandingCount == 2)
        #expect(fixture.operation.peakOutstanding == 2)
        fixture.operation.finish(1)
        fixture.operation.finish(2)
        _ = try await second.value
        _ = try await third.value
    }

    @Test("A task cancelled before enqueue never calls the framework")
    func cancelledBeforeRegistration() async {
        let fixture = ThumbnailFixture()
        let task = fixture.request(0)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.operation.started.isEmpty)
        #expect(fixture.coordinator.queuedCount == 0)
        #expect(fixture.coordinator.outstandingCount == 0)
    }

    @Test("Retired sessions reject results and new sessions still count old outstanding calls")
    func reconnectRetainsOldPhysicalSlots() async throws {
        let fixture = ThumbnailFixture()
        let first = fixture.request(0)
        let second = fixture.request(1)
        try await waitUntil { fixture.operation.started.count == 2 }
        let queued = fixture.request(2)
        try await waitUntil { fixture.coordinator.queuedCount == 1 }
        fixture.coordinator.retire(sessionID: fixture.sessionID)
        for task in [first, second, queued] {
            await #expect(throws: MediaSourceError.staleSession) { try await task.value }
        }
        #expect(fixture.coordinator.queuedCount == 0)
        #expect(fixture.coordinator.outstandingCount == 2)
        let replacement = UUID()
        fixture.coordinator.begin(sessionID: replacement)
        let current = fixture.request(3, sessionID: replacement)
        try await waitUntil { fixture.coordinator.queuedCount == 1 }
        #expect(!fixture.operation.started.contains(3))
        fixture.operation.finish(0)
        try await waitUntil { fixture.operation.started.contains(3) }
        fixture.operation.finish(0) // Duplicate stale callback must not release another slot.
        fixture.coordinator.retire(sessionID: fixture.sessionID) // Late old retirement is harmless.
        #expect(fixture.coordinator.sessionID == replacement)
        fixture.operation.finish(1)
        fixture.operation.finish(3)
        #expect(try await current.value == Data([3]))
        #expect(fixture.operation.peakOutstanding == 2)
        #expect(fixture.operation.cleanupCount == 3)
        #expect(!fixture.operation.started.contains(2))
    }

    @Test("Missing, empty, or failed thumbnail data never becomes a successful result")
    func failuresAreTerminalAndReleaseSlots() async throws {
        let fixture = ThumbnailFixture()
        let responses = [
            ThumbnailResponse(data: nil),
            ThumbnailResponse(data: Data()),
            ThumbnailResponse(data: Data([99]), error: NSError(domain: "test", code: 42))
        ]
        for (identifier, response) in responses.enumerated() {
            let task = fixture.request(identifier)
            try await waitUntil { fixture.operation.started.contains(identifier) }
            fixture.operation.finish(identifier, response: response)
            await #expect(throws: MediaSourceError.thumbnailUnavailable) { try await task.value }
            #expect(fixture.coordinator.outstandingCount == 0)
        }
        #expect(fixture.operation.cleanupCount == 3)
    }

    @Test("A synchronous duplicate callback completes and cleans up exactly once")
    func synchronousDuplicateCompletion() async throws {
        let coordinator = ThumbnailRequestCoordinator()
        let session = UUID()
        coordinator.begin(sessionID: session)
        var cleanups = 0
        let data = try await coordinator.data(sessionID: session) { completion in
            completion(ThumbnailResponse(data: Data([1])))
            completion(ThumbnailResponse(data: Data([2])))
            return { cleanups += 1 }
        }
        #expect(data == Data([1]))
        #expect(cleanups == 1)
        #expect(coordinator.outstandingCount == 0)
    }

    @Test("A launch-time validation failure releases its reserved slot without a callback")
    func launchFailure() async {
        let coordinator = ThumbnailRequestCoordinator()
        let session = UUID()
        coordinator.begin(sessionID: session)
        await #expect(throws: MediaSourceError.missingResource) {
            try await coordinator.data(sessionID: session) { _ in throw MediaSourceError.missingResource }
        }
        #expect(coordinator.outstandingCount == 0)
    }

    @Test("Cancellation winning a completion race still resumes the caller only once")
    func cancellationCompletionRace() async throws {
        let fixture = ThumbnailFixture()
        let task = fixture.request(0)
        try await waitUntil { fixture.operation.started.count == 1 }
        task.cancel()
        fixture.operation.finish(0)
        await #expect(throws: CancellationError.self) { try await task.value }
        try await waitUntil { fixture.operation.cleanupCount == 1 }
        #expect(fixture.coordinator.outstandingCount == 0)
    }

    @Test("Queued demand is bounded even while both physical requests are stalled")
    func queueLimit() async throws {
        let fixture = ThumbnailFixture(maximumQueued: 3)
        let active = [fixture.request(0), fixture.request(1)]
        try await waitUntil { fixture.operation.started.count == 2 }
        let queued = [fixture.request(2), fixture.request(3), fixture.request(4)]
        try await waitUntil { fixture.coordinator.queuedCount == 3 }
        let overflow = fixture.request(5)
        await #expect(throws: MediaSourceError.thumbnailQueueFull) { try await overflow.value }
        #expect(fixture.coordinator.queuedCount == 3)
        #expect(!fixture.operation.started.contains(5))
        fixture.coordinator.retire(sessionID: fixture.sessionID)
        for task in active + queued {
            await #expect(throws: MediaSourceError.staleSession) { try await task.value }
        }
        fixture.operation.finish(0)
        fixture.operation.finish(1)
        try await waitUntil { fixture.coordinator.outstandingCount == 0 }
    }
}

@MainActor
private final class ThumbnailFixture {
    let coordinator: ThumbnailRequestCoordinator
    let operation = FakeThumbnailOperation()
    let sessionID = UUID()

    init(maximumQueued: Int = 128) {
        coordinator = ThumbnailRequestCoordinator(maximumQueued: maximumQueued)
        coordinator.begin(sessionID: sessionID)
    }

    func request(_ identifier: Int, sessionID: UUID? = nil) -> Task<Data, any Error> {
        Task {
            try await coordinator.data(sessionID: sessionID ?? self.sessionID) { completion in
                self.operation.start(identifier, completion: completion)
            }
        }
    }
}

@MainActor
private final class FakeThumbnailOperation {
    private(set) var started: [Int] = []
    private(set) var pending: Set<Int> = []
    private(set) var peakOutstanding = 0
    private(set) var cleanupCount = 0
    private var callbacks: [Int: ThumbnailRequestCoordinator.Completion] = [:]

    func start(_ identifier: Int, completion: @escaping ThumbnailRequestCoordinator.Completion) -> @MainActor () -> Void {
        started.append(identifier)
        pending.insert(identifier)
        peakOutstanding = max(peakOutstanding, pending.count)
        callbacks[identifier] = completion
        return { [self] in
            pending.remove(identifier)
            cleanupCount += 1
        }
    }

    func finish(_ identifier: Int, response: ThumbnailResponse? = nil) {
        callbacks[identifier]?(response ?? ThumbnailResponse(data: Data([UInt8(identifier)])))
    }
}

@MainActor
private func waitUntil(_ predicate: () -> Bool) async throws {
    for _ in 0..<5_000 {
        if predicate() { return }
        await Task.yield()
    }
    Issue.record("A deterministic thumbnail operation did not reach the expected state")
    throw MediaSourceError.unavailable
}
