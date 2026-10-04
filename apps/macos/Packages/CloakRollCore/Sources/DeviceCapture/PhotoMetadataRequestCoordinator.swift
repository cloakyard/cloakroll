import Foundation
import MediaModels

public enum PhotoMetadataError: Error, Equatable, Sendable {
    case unavailable
    case busy
    case timedOut
}

/// Owns one actual metadata operation. Cancellation, timeout and session retirement finish
/// callers, but retain the physical slot and framework references until its callback arrives.
@MainActor
final class PhotoMetadataRequestCoordinator {
    typealias Completion = @Sendable (Result<PhotoCameraMetadata, MediaSourceError>) -> Void
    // Throw only before starting device I/O. Cleanup retains the file until physical completion.
    typealias Operation = @MainActor (@escaping Completion) throws -> (@MainActor () -> Void)
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private struct Request {
        let id: UUID
        let sessionID: UUID
        let cancellation: PhotoMetadataCancellation
        var operation: Operation?
        var continuation: CheckedContinuation<PhotoCameraMetadata, any Error>?
        var cleanup: (@MainActor () -> Void)?
        var timeoutTask: Task<Void, Never>?
    }

    private let maximumQueued: Int
    private let timeout: Duration
    private let sleep: Sleep
    private(set) var sessionID: UUID?
    private var queued: [Request] = []
    private var active: Request?
    private var isPumping = false

    init(
        maximumQueued: Int = 8,
        timeout: Duration = .seconds(15),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.maximumQueued = max(1, maximumQueued)
        self.timeout = max(.zero, timeout)
        self.sleep = sleep
    }

    var outstandingCount: Int { active == nil ? 0 : 1 }
    var queuedCount: Int { queued.count }

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
            request.timeoutTask?.cancel()
            request.continuation?.resume(throwing: MediaSourceError.staleSession)
        }
        if let identifier = active?.id, active?.sessionID == sessionID {
            finishCaller(identifier, error: MediaSourceError.staleSession)
        }
    }

    func metadata(sessionID: UUID, start: @escaping Operation) async throws -> PhotoCameraMetadata {
        let identifier = UUID()
        let cancellation = PhotoMetadataCancellation()
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
                    continuation.resume(throwing: PhotoMetadataError.busy)
                    return
                }
                var request = Request(
                    id: identifier, sessionID: sessionID, cancellation: cancellation,
                    operation: start, continuation: continuation
                )
                request.timeoutTask = deadline(for: identifier)
                queued.append(request)
                pump()
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor [weak self] in
                self?.finishCaller(identifier, error: CancellationError())
            }
        }
    }

    private func deadline(for identifier: UUID) -> Task<Void, Never> {
        let sleep = sleep
        let timeout = timeout
        return Task { @MainActor [weak self] in
            do {
                try await sleep(timeout)
                try Task.checkCancellation()
                self?.finishCaller(identifier, error: PhotoMetadataError.timedOut)
            } catch {
                // Logical completion cancels this deadline. It never settles device I/O.
            }
        }
    }

    private func finishCaller(_ identifier: UUID, error: any Error) {
        if let index = queued.firstIndex(where: { $0.id == identifier }) {
            let request = queued.remove(at: index)
            request.timeoutTask?.cancel()
            request.continuation?.resume(throwing: error)
        } else if var request = active, request.id == identifier {
            request.timeoutTask?.cancel()
            request.timeoutTask = nil
            let continuation = request.continuation
            request.continuation = nil
            active = request
            continuation?.resume(throwing: error)
        }
    }

    private func pump() {
        guard !isPumping else { return }
        isPumping = true
        defer { isPumping = false }
        while active == nil, !queued.isEmpty {
            var request = queued.removeFirst()
            if request.cancellation.isCancelled {
                request.timeoutTask?.cancel()
                request.continuation?.resume(throwing: CancellationError())
                continue
            }
            guard request.sessionID == sessionID else {
                request.timeoutTask?.cancel()
                request.continuation?.resume(throwing: MediaSourceError.staleSession)
                continue
            }
            guard let operation = request.operation else { continue }
            request.operation = nil
            active = request
            let identifier = request.id
            do {
                let cleanup = try operation { [self] result in
                    // Enqueue even a synchronous callback so cleanup is installed before settling.
                    // Strong retention keeps the slot owner alive after the UI/browser retires it.
                    DispatchQueue.main.async { self.complete(identifier, result: result) }
                }
                // Preserve any retirement/cancellation triggered synchronously while launching.
                active?.cleanup = cleanup
            } catch {
                let failed = active
                active = nil
                failed?.timeoutTask?.cancel()
                failed?.continuation?.resume(throwing: error)
            }
        }
    }

    private func complete(_ identifier: UUID, result: Result<PhotoCameraMetadata, MediaSourceError>) {
        guard let request = active, request.id == identifier else { return }
        // Claim the continuation before cleanup, which may synchronously retire this session.
        active?.continuation = nil
        active?.timeoutTask = nil
        request.timeoutTask?.cancel()
        // Keep the slot occupied while cleanup runs, even if cleanup enqueues another request.
        request.cleanup?()
        active = nil
        if let continuation = request.continuation {
            if request.cancellation.isCancelled {
                continuation.resume(throwing: CancellationError())
            } else if request.sessionID != sessionID {
                continuation.resume(throwing: MediaSourceError.staleSession)
            } else {
                switch result {
                case .success(let metadata): continuation.resume(returning: metadata)
                case .failure(.staleSession): continuation.resume(throwing: MediaSourceError.staleSession)
                case .failure(.missingResource): continuation.resume(throwing: MediaSourceError.missingResource)
                case .failure: continuation.resume(throwing: PhotoMetadataError.unavailable)
                }
            }
        }
        pump()
    }
}

/// Cancellation arrives on any executor. Every mutable access is protected by this lock.
private final class PhotoMetadataCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() { lock.withLock { cancelled = true } }
}
