import Foundation
import MediaModels
import Testing
@testable import DeviceCapture

@Suite("Physical photo metadata request ownership", .timeLimit(.minutes(1)))
@MainActor
struct PhotoMetadataRequestCoordinatorTests {
    @Test("Only one physical call launches and callbacks advance the queue")
    func concurrencyLimit() async throws {
        let fixture = MetadataFixture()
        let tasks = (0..<6).map { fixture.request($0) }
        try await waitForMetadata { fixture.coordinator.queuedCount == 5 }
        #expect(fixture.operation.started.count == 1)
        for _ in tasks {
            let count = fixture.operation.cleanupCount
            let identifier = try #require(fixture.operation.pending.first)
            fixture.operation.finish(identifier)
            try await waitForMetadata { fixture.operation.cleanupCount > count }
        }
        for (identifier, task) in tasks.enumerated() {
            #expect(try await task.value == MetadataOperation.value(identifier))
        }
        #expect(fixture.operation.peakOutstanding == 1)
        #expect(fixture.coordinator.outstandingCount == 0)
    }

    @Test("Cancelling a queued caller never launches its operation")
    func queuedCancellation() async throws {
        let fixture = MetadataFixture()
        let active = fixture.request(0)
        try await waitForMetadata { fixture.operation.started.count == 1 }
        let queued = fixture.request(1)
        try await waitForMetadata { fixture.coordinator.queuedCount == 1 }
        queued.cancel()
        await #expect(throws: CancellationError.self) { try await queued.value }
        #expect(fixture.coordinator.queuedCount == 0)
        fixture.operation.finish(0)
        _ = try await active.value
        #expect(fixture.operation.started == [0])
    }

    @Test("Active cancellation returns while retaining the physical slot and cleanup")
    func activeCancellation() async throws {
        let fixture = MetadataFixture()
        let active = fixture.request(0)
        try await waitForMetadata { fixture.operation.started.count == 1 }
        let queued = fixture.request(1)
        try await waitForMetadata { fixture.coordinator.queuedCount == 1 }
        active.cancel()
        await #expect(throws: CancellationError.self) { try await active.value }
        #expect(fixture.coordinator.outstandingCount == 1)
        #expect(fixture.operation.cleanupCount == 0)
        #expect(fixture.operation.started == [0])
        fixture.operation.finish(0)
        try await waitForMetadata { fixture.operation.started.contains(1) }
        fixture.operation.finish(1)
        _ = try await queued.value
        #expect(fixture.operation.peakOutstanding == 1)
        #expect(fixture.operation.cleanupCount == 2)
    }

    @Test("Pre-cancelled callers do not enqueue or launch")
    func cancellationBeforeRegistration() async {
        let fixture = MetadataFixture()
        let task = fixture.request(0)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.operation.started.isEmpty)
        #expect(fixture.coordinator.queuedCount == 0)
        #expect(fixture.coordinator.outstandingCount == 0)
    }

    @Test("Retirement rejects callers while a replacement session waits for old physical I/O")
    func reconnectAndLateCallback() async throws {
        let fixture = MetadataFixture()
        let old = fixture.request(0)
        try await waitForMetadata { fixture.operation.started.count == 1 }
        let oldCallback = try #require(fixture.operation.callbacks[0])
        let queued = fixture.request(1)
        try await waitForMetadata { fixture.coordinator.queuedCount == 1 }
        fixture.coordinator.retire(sessionID: fixture.sessionID)
        for task in [old, queued] {
            await #expect(throws: MediaSourceError.staleSession) { try await task.value }
        }
        #expect(fixture.coordinator.outstandingCount == 1)
        #expect(fixture.coordinator.queuedCount == 0)
        let replacement = UUID()
        fixture.coordinator.begin(sessionID: replacement)
        let current = fixture.request(2, sessionID: replacement)
        try await waitForMetadata { fixture.coordinator.queuedCount == 1 }
        #expect(fixture.operation.started == [0])
        fixture.operation.finish(0)
        try await waitForMetadata { fixture.operation.started.contains(2) }
        oldCallback(.success(MetadataOperation.value(0)))
        fixture.coordinator.retire(sessionID: fixture.sessionID)
        #expect(fixture.coordinator.sessionID == replacement)
        fixture.operation.finish(2)
        #expect(try await current.value == MetadataOperation.value(2))
        #expect(fixture.operation.cleanupCount == 2)
        #expect(fixture.operation.peakOutstanding == 1)
        #expect(!fixture.operation.started.contains(1))
    }

    @Test("Beginning a replacement retires the old session and repeated begin is harmless")
    func replacementAndStaleSubmission() async throws {
        let fixture = MetadataFixture()
        let old = fixture.request(0)
        try await waitForMetadata { fixture.operation.started.count == 1 }
        fixture.coordinator.begin(sessionID: fixture.sessionID)
        #expect(fixture.coordinator.outstandingCount == 1)
        let replacement = UUID()
        fixture.coordinator.begin(sessionID: replacement)
        await #expect(throws: MediaSourceError.staleSession) { try await old.value }
        let stale = fixture.request(1)
        await #expect(throws: MediaSourceError.staleSession) { try await stale.value }
        fixture.operation.finish(0)
        try await waitForMetadata { fixture.coordinator.outstandingCount == 0 }
        #expect(fixture.operation.started == [0])
    }

    @Test("The default limit allows eight waiting callers and rejects overflow")
    func queueBound() async throws {
        let fixture = MetadataFixture()
        let active = fixture.request(0)
        try await waitForMetadata { fixture.operation.started.count == 1 }
        let queued = (1...8).map { fixture.request($0) }
        try await waitForMetadata { fixture.coordinator.queuedCount == 8 }
        let overflow = fixture.request(9)
        await #expect(throws: PhotoMetadataError.busy) { try await overflow.value }
        #expect(fixture.coordinator.outstandingCount == 1)
        #expect(fixture.coordinator.queuedCount == 8)
        fixture.coordinator.retire(sessionID: fixture.sessionID)
        for task in [active] + queued {
            await #expect(throws: MediaSourceError.staleSession) { try await task.value }
        }
        fixture.operation.finish(0)
        try await waitForMetadata { fixture.coordinator.outstandingCount == 0 }
        #expect(fixture.operation.started == [0])
    }

    @Test("An active timeout returns but cannot release the physical slot")
    func activeTimeout() async throws {
        let clock = MetadataDeadlines()
        let fixture = MetadataFixture(sleep: { try await clock.sleep($0) })
        let first = fixture.request(0)
        try await waitForMetadata { clock.pendingCount == 1 }
        clock.fireAll()
        await #expect(throws: PhotoMetadataError.timedOut) { try await first.value }
        #expect(fixture.coordinator.outstandingCount == 1)
        #expect(fixture.operation.cleanupCount == 0)
        let next = fixture.request(1)
        try await waitForMetadata { fixture.coordinator.queuedCount == 1 }
        #expect(fixture.operation.started == [0])
        fixture.operation.finish(0)
        try await waitForMetadata { fixture.operation.started.contains(1) }
        fixture.operation.finish(1)
        _ = try await next.value
        #expect(fixture.operation.peakOutstanding == 1)
        #expect(fixture.operation.cleanupCount == 2)
        try await waitForMetadata { clock.pendingCount == 0 }
    }

    @Test("Queued callers have a deadline and never launch after timing out")
    func queuedTimeout() async throws {
        let clock = MetadataDeadlines()
        let fixture = MetadataFixture(sleep: { try await clock.sleep($0) })
        let first = fixture.request(0)
        try await waitForMetadata { fixture.operation.started.count == 1 }
        let queued = fixture.request(1)
        try await waitForMetadata { clock.pendingCount == 2 }
        clock.fireAll()
        for task in [first, queued] {
            await #expect(throws: PhotoMetadataError.timedOut) { try await task.value }
        }
        #expect(fixture.coordinator.queuedCount == 0)
        #expect(fixture.coordinator.outstandingCount == 1)
        fixture.operation.finish(0)
        try await waitForMetadata { fixture.coordinator.outstandingCount == 0 }
        #expect(fixture.operation.started == [0])
    }

    @Test("Synchronous duplicate callbacks run cleanup and resume only once")
    func synchronousDuplicateCallbacks() async throws {
        let coordinator = PhotoMetadataRequestCoordinator()
        let sessionID = UUID()
        coordinator.begin(sessionID: sessionID)
        var cleanups = 0
        let value = try await coordinator.metadata(sessionID: sessionID) { completion in
            completion(.success(PhotoCameraMetadata()))
            completion(.failure(.unavailable))
            return { cleanups += 1 }
        }
        #expect(value.isEmpty)
        #expect(cleanups == 1)
        #expect(coordinator.outstandingCount == 0)
    }

    @Test("A launch failure frees capacity without inventing a physical request")
    func launchFailure() async throws {
        let fixture = MetadataFixture()
        await #expect(throws: MediaSourceError.missingResource) {
            try await fixture.coordinator.metadata(sessionID: fixture.sessionID) { _ in
                throw MediaSourceError.missingResource
            }
        }
        #expect(fixture.coordinator.outstandingCount == 0)
        let next = fixture.request(0)
        try await waitForMetadata { fixture.operation.started.count == 1 }
        fixture.operation.finish(0)
        _ = try await next.value
    }

    @Test("Metadata failures use semantic errors and preserve resource/session errors")
    func failureMapping() async throws {
        for source in [MediaSourceError.unavailable, .thumbnailUnavailable, .thumbnailQueueFull] {
            let fixture = MetadataFixture()
            let task = fixture.request(0)
            try await waitForMetadata { fixture.operation.started.count == 1 }
            fixture.operation.finish(0, result: .failure(source))
            await #expect(throws: PhotoMetadataError.unavailable) { try await task.value }
        }
        for source in [MediaSourceError.missingResource, .staleSession] {
            let fixture = MetadataFixture()
            let task = fixture.request(0)
            try await waitForMetadata { fixture.operation.started.count == 1 }
            fixture.operation.finish(0, result: .failure(source))
            await #expect(throws: source) { try await task.value }
        }
    }

    @Test("Cancellation recorded before callback processing wins the completion race")
    func cancellationCompletionRace() async throws {
        let fixture = MetadataFixture()
        let task = fixture.request(0)
        try await waitForMetadata { fixture.operation.started.count == 1 }
        fixture.operation.finish(0)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try await waitForMetadata { fixture.operation.cleanupCount == 1 }
    }

    @Test("Retirement during launch still retains cleanup until callback")
    func retirementDuringLaunch() async throws {
        let fixture = MetadataFixture()
        let task = Task {
            try await fixture.coordinator.metadata(sessionID: fixture.sessionID) { completion in
                let cleanup = fixture.operation.start(0, completion: completion)
                fixture.coordinator.retire(sessionID: fixture.sessionID)
                return cleanup
            }
        }
        await #expect(throws: MediaSourceError.staleSession) { try await task.value }
        #expect(fixture.coordinator.outstandingCount == 1)
        #expect(fixture.operation.cleanupCount == 0)
        fixture.operation.finish(0)
        try await waitForMetadata { fixture.operation.cleanupCount == 1 }
        #expect(fixture.coordinator.outstandingCount == 0)
    }

    @Test("Retirement during cleanup owns the continuation exactly once")
    func retirementDuringCleanup() async throws {
        let coordinator = PhotoMetadataRequestCoordinator()
        let sessionID = UUID()
        coordinator.begin(sessionID: sessionID)
        var cleanups = 0
        await #expect(throws: MediaSourceError.staleSession) {
            try await coordinator.metadata(sessionID: sessionID) { completion in
                completion(.success(PhotoCameraMetadata()))
                return {
                    cleanups += 1
                    coordinator.retire(sessionID: sessionID)
                }
            }
        }
        #expect(cleanups == 1)
        #expect(coordinator.outstandingCount == 0)
    }

    @Test("The physical callback retains the coordinator after its caller and context leave")
    func callbackRetainsOwner() async throws {
        let operation = MetadataOperation()
        let sessionID = UUID()
        var owner: PhotoMetadataRequestCoordinator? = PhotoMetadataRequestCoordinator()
        let weakOwner = WeakMetadataCoordinator(owner)
        owner?.begin(sessionID: sessionID)
        var task: Task<PhotoCameraMetadata, any Error>? = Task { [coordinator = owner!] in
            try await coordinator.metadata(sessionID: sessionID) { completion in
                operation.start(0, completion: completion)
            }
        }
        try await waitForMetadata { operation.started.count == 1 }
        task?.cancel()
        await #expect(throws: CancellationError.self) { try await task?.value }
        task = nil
        owner = nil
        #expect(weakOwner.value != nil)
        #expect(operation.cleanupCount == 0)
        operation.finish(0)
        try await waitForMetadata { weakOwner.value == nil }
        #expect(operation.cleanupCount == 1)
    }
}

@MainActor
private final class WeakMetadataCoordinator {
    weak var value: PhotoMetadataRequestCoordinator?

    init(_ value: PhotoMetadataRequestCoordinator?) {
        self.value = value
    }
}

@MainActor
private struct MetadataFixture {
    let sessionID = UUID()
    let operation = MetadataOperation()
    let coordinator: PhotoMetadataRequestCoordinator

    init(sleep: @escaping PhotoMetadataRequestCoordinator.Sleep = { try await Task.sleep(for: $0) }) {
        coordinator = PhotoMetadataRequestCoordinator(sleep: sleep)
        coordinator.begin(sessionID: sessionID)
    }

    func request(_ identifier: Int, sessionID requestedSession: UUID? = nil) -> Task<PhotoCameraMetadata, any Error> {
        Task {
            try await coordinator.metadata(sessionID: requestedSession ?? sessionID) { completion in
                operation.start(identifier, completion: completion)
            }
        }
    }
}

@MainActor
private final class MetadataOperation {
    var started: [Int] = []
    var pending: Set<Int> = []
    var callbacks: [Int: PhotoMetadataRequestCoordinator.Completion] = [:]
    var cleanupCount = 0
    var peakOutstanding = 0

    static func value(_ identifier: Int) -> PhotoCameraMetadata {
        PhotoCameraMetadata(cameraModel: "Camera \(identifier)")
    }

    func start(
        _ identifier: Int,
        completion: @escaping PhotoMetadataRequestCoordinator.Completion
    ) -> @MainActor () -> Void {
        started.append(identifier)
        pending.insert(identifier)
        callbacks[identifier] = completion
        peakOutstanding = max(peakOutstanding, pending.count)
        return {
            self.pending.remove(identifier)
            self.cleanupCount += 1
        }
    }

    func finish(_ identifier: Int, result: Result<PhotoCameraMetadata, MediaSourceError>? = nil) {
        let completion = callbacks.removeValue(forKey: identifier)
        completion?(result ?? .success(Self.value(identifier)))
    }
}

@MainActor
private final class MetadataDeadlines {
    private var waiters: [UUID: AsyncStream<Void>.Continuation] = [:]
    var pendingCount: Int { waiters.count }

    func sleep(_ duration: Duration) async throws {
        let identifier = UUID()
        let stream = AsyncStream<Void>.makeStream()
        waiters[identifier] = stream.continuation
        defer {
            waiters[identifier] = nil
            stream.continuation.finish()
        }
        var iterator = stream.stream.makeAsyncIterator()
        guard await iterator.next() != nil else { throw CancellationError() }
        try Task.checkCancellation()
    }

    func fireAll() {
        for continuation in Array(waiters.values) {
            continuation.yield(())
            continuation.finish()
        }
    }
}

@MainActor
private func waitForMetadata(_ condition: () -> Bool) async throws {
    for _ in 0..<5_000 {
        if condition() { return }
        await Task.yield()
    }
    #expect(condition())
    throw PhotoMetadataError.unavailable
}
