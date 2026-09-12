import Foundation
import MediaModels
import OSLog

struct ThumbnailResponse: Sendable {
    let data: Data?
    let error: CaptureError?

    init(data: Data?, error: (any Error)? = nil) {
        self.data = data
        self.error = error.map(CaptureError.init)
    }
}

/// Slots represent actual framework operations, not suspended Swift callers. A cancelled caller
/// returns promptly, while its physical slot and cleanup remain owned until the callback arrives.
@MainActor
final class ThumbnailRequestCoordinator {
    typealias Completion = @Sendable (ThumbnailResponse) -> Void
    // An operation may throw only before launching the physical request. Its returned cleanup
    // owns any framework references until a real completion, independent of caller cancellation.
    typealias Operation = @MainActor (@escaping Completion) throws -> (@MainActor () -> Void)

    private struct Request {
        let id: UUID
        let sessionID: UUID
        let cancellation: ThumbnailCancellation
        let operation: Operation
        var continuation: CheckedContinuation<Data, any Error>?
        var cleanup: (@MainActor () -> Void)?
    }

    private let logger = Logger(subsystem: "com.cloakroll.core", category: "Thumbnails")
    private let maximumQueued: Int
    private(set) var sessionID: UUID?
    private var queued: [Request] = []
    private var active: [UUID: Request] = [:]
    private var isPumping = false
    private var metrics = ThumbnailRequestDiagnostics()
    #if DEBUG
    private var lastLoggedMetrics: ThumbnailRequestDiagnostics?
    private var lastLoggedAt = Date.distantPast
    #endif

    init(maximumQueued: Int = 128) {
        self.maximumQueued = max(1, maximumQueued)
    }

    var outstandingCount: Int { active.count }
    var queuedCount: Int { queued.count }

    var diagnostics: ThumbnailRequestDiagnostics {
        var value = metrics
        value.actualOutstandingCount = active.values.filter { $0.cleanup != nil }.count
        value.queuedCount = queued.count
        return value
    }

    func begin(sessionID: UUID) {
        guard self.sessionID != sessionID else { return }
        if let previous = self.sessionID { retire(sessionID: previous) }
        self.sessionID = sessionID
        pump()
    }

    func retire(sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        self.sessionID = nil
        let retired = queued
        queued.removeAll()
        for request in retired {
            if request.continuation != nil { metrics.retiredCount += 1 }
            request.continuation?.resume(throwing: MediaSourceError.staleSession)
        }
        for identifier in Array(active.keys) {
            guard var request = active[identifier], request.sessionID == sessionID else { continue }
            if request.continuation != nil { metrics.retiredCount += 1 }
            request.continuation?.resume(throwing: MediaSourceError.staleSession)
            request.continuation = nil
            active[identifier] = request
        }
        // Do not remove active requests: session closure is not proof their callbacks completed.
        logDiagnostics(force: true)
    }

    func data(sessionID: UUID, operation: @escaping Operation) async throws -> Data {
        let identifier = UUID()
        let cancellation = ThumbnailCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard !cancellation.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard self.sessionID == sessionID else {
                    continuation.resume(throwing: MediaSourceError.staleSession)
                    return
                }
                guard queued.count < maximumQueued else {
                    continuation.resume(throwing: MediaSourceError.thumbnailQueueFull)
                    return
                }
                queued.append(Request(
                    id: identifier, sessionID: sessionID, cancellation: cancellation,
                    operation: operation, continuation: continuation
                ))
                metrics.queuedHighWaterMark = max(metrics.queuedHighWaterMark, queued.count)
                pump()
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor [weak self] in self?.cancel(identifier) }
        }
    }

    private func cancel(_ identifier: UUID) {
        if let index = queued.firstIndex(where: { $0.id == identifier }) {
            let request = queued.remove(at: index)
            if request.continuation != nil { metrics.cancelledCount += 1 }
            request.continuation?.resume(throwing: CancellationError())
        } else if var request = active[identifier] {
            if request.continuation != nil { metrics.cancelledCount += 1 }
            request.continuation?.resume(throwing: CancellationError())
            request.continuation = nil
            active[identifier] = request
        }
    }

    private func pump() {
        guard !isPumping else { return }
        isPumping = true
        defer { isPumping = false }
        while active.count < 2, !queued.isEmpty {
            var request = queued.removeFirst()
            if request.cancellation.isCancelled {
                if request.continuation != nil { metrics.cancelledCount += 1 }
                request.continuation?.resume(throwing: CancellationError())
                continue
            }
            guard request.sessionID == sessionID else {
                if request.continuation != nil { metrics.retiredCount += 1 }
                request.continuation?.resume(throwing: MediaSourceError.staleSession)
                continue
            }
            let identifier = request.id
            active[identifier] = request
            do {
                request.cleanup = try request.operation { [self] response in
                    // The block API can complete on any queue, including synchronously. Always
                    // enqueue result handling so operation cleanup is installed before it runs.
                    DispatchQueue.main.async { self.complete(identifier, response: response) }
                }
                active[identifier] = request
                metrics.startedCount += 1
                if active.count > metrics.actualHighWaterMark {
                    metrics.actualHighWaterMark = active.count
                    logDiagnostics(force: true)
                }
            } catch {
                active[identifier] = nil
                request.continuation?.resume(throwing: error)
            }
        }
    }

    private func complete(_ identifier: UUID, response: ThumbnailResponse) {
        guard let request = active.removeValue(forKey: identifier) else { return }
        request.cleanup?()
        metrics.completedCount += 1
        if response.error != nil || response.data?.isEmpty != false { metrics.failedCount += 1 }
        if let continuation = request.continuation {
            if request.cancellation.isCancelled {
                metrics.cancelledCount += 1
                continuation.resume(throwing: CancellationError())
            } else if request.sessionID != sessionID {
                metrics.retiredCount += 1
                continuation.resume(throwing: MediaSourceError.staleSession)
            } else if let error = response.error {
                logger.error("Thumbnail error domain: \(error.domain, privacy: .public), code: \(error.code, privacy: .public)")
                logger.debug("Thumbnail error detail: \(error.message, privacy: .private)")
                continuation.resume(throwing: MediaSourceError.thumbnailUnavailable)
            } else if let data = response.data, !data.isEmpty {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: MediaSourceError.thumbnailUnavailable)
            }
        }
        pump()
        if metrics.completedCount.isMultiple(of: 32) || active.isEmpty {
            logDiagnostics(force: metrics.completedCount.isMultiple(of: 32))
        }
    }

    private func logDiagnostics(force: Bool = false) {
        #if DEBUG
        let value = diagnostics
        guard value != lastLoggedMetrics, force || Date().timeIntervalSince(lastLoggedAt) >= 1 else { return }
        lastLoggedMetrics = value
        lastLoggedAt = Date()
        logger.info("""
        Thumbnail framework metrics: started=\(value.startedCount, privacy: .public) \
        completed=\(value.completedCount, privacy: .public) failed=\(value.failedCount, privacy: .public) \
        outstanding=\(value.actualOutstandingCount, privacy: .public) highWater=\(value.actualHighWaterMark, privacy: .public) \
        queued=\(value.queuedCount, privacy: .public) queueHighWater=\(value.queuedHighWaterMark, privacy: .public) \
        cancelled=\(value.cancelledCount, privacy: .public) retired=\(value.retiredCount, privacy: .public)
        """)
        #endif
    }
}
