import Foundation
import MediaModels
import Testing
@testable import DeviceCapture

@Suite("Original download lifetime", .timeLimit(.minutes(1)))
@MainActor
struct OriginalDownloadCoordinatorTests {
    @Test func onlyOneActualOriginalCanBeActive() async throws {
        let fixture = OriginalFixture()
        let first = fixture.request(1)
        try await waitFor { fixture.operation.started == [1] }
        let busy = fixture.request(2)
        await #expect(throws: OriginalDownloadError.busy) { try await busy.value }
        #expect(fixture.operation.started == [1])
        fixture.operation.finish(1)
        #expect(try await first.value == FakeOriginalOperation.result(1))
        let next = fixture.request(3)
        try await waitFor { fixture.operation.started == [1, 3] }
        fixture.operation.finish(3)
        _ = try await next.value
        #expect(!fixture.coordinator.isBusy)
        #expect(fixture.operation.cleanupCount == 2)
    }

    @Test func activeCancellationWaitsForActualCompletionAndRetainsTheSlot() async throws {
        let fixture = OriginalFixture()
        var settled = false
        let task = Task {
            defer { settled = true }
            return try await fixture.download(1)
        }
        try await waitFor { fixture.operation.started == [1] }
        task.cancel()
        try await waitFor { fixture.operation.cancelled == [1] }
        #expect(!settled)
        #expect(fixture.coordinator.isBusy)
        #expect(fixture.operation.cleanupCount == 0)
        let busy = fixture.request(2)
        await #expect(throws: OriginalDownloadError.busy) { try await busy.value }
        fixture.operation.finish(1)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(settled)
        #expect(!fixture.coordinator.isBusy)
        #expect(fixture.operation.cleanupCount == 1)
    }

    @Test func cancellationBeforeRegistrationNeverLaunches() async {
        let fixture = OriginalFixture()
        let task = fixture.request(1)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.operation.started.isEmpty)
        #expect(!fixture.coordinator.isBusy)
    }

    @Test func cancellationWinsTheCompletionRaceAfterActualCleanup() async throws {
        let fixture = OriginalFixture()
        let task = fixture.request(1)
        try await waitFor { fixture.operation.started == [1] }
        task.cancel()
        fixture.operation.finish(1)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.operation.cleanupCount == 1)
        #expect(!fixture.coordinator.isBusy)
    }

    @Test func retiredSessionsKeepTheirSlotUntilCallbackAndCannotRevive() async throws {
        let fixture = OriginalFixture()
        var settled = false
        let task = Task {
            defer { settled = true }
            return try await fixture.download(1)
        }
        try await waitFor { fixture.operation.started == [1] }
        fixture.coordinator.retire(sessionID: fixture.sessionID)
        #expect(!settled)
        #expect(fixture.operation.cancelled == [1])
        #expect(fixture.operation.cleanupCount == 0)
        let replacement = UUID()
        fixture.coordinator.begin(sessionID: replacement)
        let busy = fixture.request(2, sessionID: replacement)
        await #expect(throws: OriginalDownloadError.busy) { try await busy.value }
        fixture.operation.finish(1)
        await #expect(throws: MediaSourceError.staleSession) { try await task.value }
        let next = fixture.request(3, sessionID: replacement)
        try await waitFor { fixture.operation.started == [1, 3] }
        fixture.operation.finish(1)
        fixture.coordinator.retire(sessionID: fixture.sessionID)
        #expect(fixture.coordinator.sessionID == replacement)
        fixture.operation.finish(3)
        #expect(try await next.value == FakeOriginalOperation.result(3))
        #expect(fixture.operation.cleanupCount == 2)
    }

    @Test func restoringTheSameSessionTokenDoesNotReviveARetiredDownload() async throws {
        let fixture = OriginalFixture()
        let task = fixture.request(1)
        try await waitFor { fixture.operation.started == [1] }
        fixture.coordinator.retire(sessionID: fixture.sessionID)
        fixture.coordinator.begin(sessionID: fixture.sessionID)
        fixture.operation.finish(1)
        await #expect(throws: MediaSourceError.staleSession) { try await task.value }
        #expect(fixture.operation.cleanupCount == 1)
    }

    @Test func repeatedCancelAndRetireRequestsCancelUnderlyingOperationOnlyOnce() async throws {
        let fixture = OriginalFixture()
        let task = fixture.request(1)
        try await waitFor { fixture.operation.started == [1] }
        task.cancel()
        try await waitFor { fixture.operation.cancelled == [1] }
        fixture.coordinator.retire(sessionID: fixture.sessionID)
        fixture.coordinator.retire(sessionID: fixture.sessionID)
        #expect(fixture.operation.cancelled == [1])
        fixture.operation.finish(1)
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func synchronousAndDuplicateCallbacksCleanUpExactlyOnce() async throws {
        let coordinator = OriginalDownloadCoordinator()
        let sessionID = UUID()
        coordinator.begin(sessionID: sessionID)
        var cleanups = 0
        let expected = FakeOriginalOperation.result(1)
        let result = try await coordinator.download(sessionID: sessionID, progress: { _ in }) { receive in
            receive(.completed(.success(expected)))
            receive(.completed(.failure(.missingResult)))
            return OriginalDownloadHandle(cancel: {}, cleanup: { cleanups += 1 })
        }
        #expect(result == expected)
        #expect(cleanups == 1)
        #expect(!coordinator.isBusy)
    }

    @Test func retirementDuringLaunchCancelsAfterTheHandleIsInstalled() async {
        let coordinator = OriginalDownloadCoordinator()
        let sessionID = UUID()
        coordinator.begin(sessionID: sessionID)
        var cancellations = 0
        var cleanups = 0
        await #expect(throws: MediaSourceError.staleSession) {
            try await coordinator.download(sessionID: sessionID, progress: { _ in }) { receive in
                coordinator.retire(sessionID: sessionID)
                receive(.completed(.success(FakeOriginalOperation.result(1))))
                return OriginalDownloadHandle(cancel: { cancellations += 1 }, cleanup: { cleanups += 1 })
            }
        }
        #expect(cancellations == 1)
        #expect(cleanups == 1)
    }

    @Test func launchValidationFailureAndStaleTokensNeverOccupyTheSlot() async {
        let coordinator = OriginalDownloadCoordinator()
        let sessionID = UUID()
        coordinator.begin(sessionID: sessionID)
        await #expect(throws: MediaSourceError.missingResource) {
            try await coordinator.download(sessionID: sessionID, progress: { _ in }) { _ in
                throw MediaSourceError.missingResource
            }
        }
        #expect(!coordinator.isBusy)
        await #expect(throws: MediaSourceError.staleSession) {
            try await coordinator.download(sessionID: UUID(), progress: { _ in }) { _ in
                Issue.record("Stale session must not launch")
                return OriginalDownloadHandle(cancel: {}, cleanup: {})
            }
        }
        #expect(!coordinator.isBusy)
    }

    @Test func frameworkFailureSettlesOnlyAfterCallback() async throws {
        let fixture = OriginalFixture()
        let task = fixture.request(1)
        try await waitFor { fixture.operation.started == [1] }
        let failure = OriginalDownloadError.failed(domain: "test", code: 12)
        fixture.operation.finish(1, result: .failure(failure))
        await #expect(throws: failure) { try await task.value }
        #expect(fixture.operation.cleanupCount == 1)
        #expect(!fixture.coordinator.isBusy)
    }

    @Test func byteProgressIsMonotonicAndStopsAfterCancellation() async throws {
        let fixture = OriginalFixture()
        let values = DownloadProgressRecorder()
        let task = fixture.request(1, progress: { values.append($0) })
        try await waitFor { fixture.operation.started == [1] }
        fixture.operation.report(1, downloaded: 10, total: 100)
        fixture.operation.report(1, downloaded: 5, total: 0)
        try await waitFor { values.values.count == 2 }
        #expect(values.values == [
            DownloadProgress(downloadedBytes: 10, totalBytes: 100),
            DownloadProgress(downloadedBytes: 10, totalBytes: nil)
        ])
        task.cancel()
        fixture.operation.report(1, downloaded: 90, total: 100)
        fixture.operation.finish(1)
        await #expect(throws: CancellationError.self) { try await task.value }
        fixture.operation.report(1, downloaded: 100, total: 100)
        await Task.yield()
        #expect(values.values.count == 2)
    }
}

@MainActor
private final class OriginalFixture {
    let coordinator = OriginalDownloadCoordinator()
    let operation = FakeOriginalOperation()
    let sessionID = UUID()

    init() { coordinator.begin(sessionID: sessionID) }

    func request(
        _ id: Int, sessionID: UUID? = nil, progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) -> Task<DownloadedOriginal, any Error> {
        Task { try await download(id, sessionID: sessionID, progress: progress) }
    }

    func download(
        _ id: Int, sessionID: UUID? = nil, progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) async throws -> DownloadedOriginal {
        try await coordinator.download(sessionID: sessionID ?? self.sessionID, progress: progress) { receive in
            self.operation.start(id, receive: receive)
        }
    }
}

@MainActor
private final class FakeOriginalOperation {
    private(set) var started: [Int] = []
    private(set) var cancelled: [Int] = []
    private(set) var cleanupCount = 0
    private var callbacks: [Int: OriginalDownloadCoordinator.Callback] = [:]

    func start(_ id: Int, receive: @escaping OriginalDownloadCoordinator.Callback) -> OriginalDownloadHandle {
        started.append(id)
        callbacks[id] = receive
        return OriginalDownloadHandle(cancel: { self.cancelled.append(id) }, cleanup: { self.cleanupCount += 1 })
    }

    func finish(_ id: Int, result: Result<DownloadedOriginal, OriginalDownloadError>? = nil) {
        callbacks[id]?(.completed(result ?? .success(Self.result(id))))
    }

    func report(_ id: Int, downloaded: Int64, total: Int64) {
        callbacks[id]?(.progress(DownloadProgress(downloadedBytes: downloaded, totalBytes: total)))
    }

    static func result(_ id: Int) -> DownloadedOriginal {
        DownloadedOriginal(url: URL(fileURLWithPath: "/unused-staging/\(id)/original.HEIC"), expectedByteCount: 200)
    }
}

private final class DownloadProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DownloadProgress] = []

    var values: [DownloadProgress] { lock.withLock { storage } }

    func append(_ value: DownloadProgress) { lock.withLock { storage.append(value) } }
}

@MainActor
private func waitFor(_ condition: () -> Bool) async throws {
    for _ in 0..<5_000 {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("An explicitly controlled original download did not reach its expected state")
    throw MediaSourceError.unavailable
}
