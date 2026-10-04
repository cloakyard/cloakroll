import Foundation
import MediaModels
import OSLog

enum OriginalDownloadEvent: Sendable {
    case progress(DownloadProgress)
    case completed(Result<DownloadedOriginal, OriginalDownloadError>)
}

@MainActor
struct OriginalDownloadHandle {
    let cancel: @MainActor () -> Void
    let cleanup: @MainActor () -> Void
}

/// One actual original transfer across browser generations. A cancelled or retired operation
/// retains its slot, continuation and framework ownership until a real completion arrives.
@MainActor
final class OriginalDownloadCoordinator {
    typealias Callback = @Sendable (OriginalDownloadEvent) -> Void
    typealias Operation = @MainActor (@escaping Callback) throws -> OriginalDownloadHandle

    private struct Active {
        let id: UUID
        let sessionID: UUID
        let cancellation: OriginalDownloadCancellation
        let continuation: CheckedContinuation<DownloadedOriginal, any Error>
        let progress: @Sendable (DownloadProgress) -> Void
        var handle: OriginalDownloadHandle?
        var retired = false
        var cancellationRequested = false
        var downloadedBytes: Int64 = 0
    }

    private let logger = Logger(subsystem: "com.cloakroll.core", category: "OriginalDownloads")
    private(set) var sessionID: UUID?
    private var active: Active?
    /// The app's newest browser may resume deferred selection only after actual cleanup.
    var onSettled: (@MainActor () -> Void)?

    var isBusy: Bool { active != nil }

    func begin(sessionID: UUID) {
        guard self.sessionID != sessionID else { return }
        if let previous = self.sessionID { retire(sessionID: previous) }
        self.sessionID = sessionID
    }

    func retire(sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        self.sessionID = nil
        guard active?.sessionID == sessionID else { return }
        active?.retired = true
        requestCancellation()
    }

    func download(
        sessionID: UUID, progress: @escaping @Sendable (DownloadProgress) -> Void,
        operation: @escaping Operation
    ) async throws -> DownloadedOriginal {
        let identifier = UUID()
        let cancellation = OriginalDownloadCancellation()
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
                guard active == nil else {
                    continuation.resume(throwing: OriginalDownloadError.busy)
                    return
                }
                active = Active(
                    id: identifier, sessionID: sessionID, cancellation: cancellation,
                    continuation: continuation, progress: progress
                )
                do {
                    let handle = try operation { [self] event in
                        // The callback can be synchronous or arrive on another queue. Enqueue
                        // handling so the ownership handle is installed before terminal cleanup.
                        DispatchQueue.main.async { self.receive(event, identifier: identifier) }
                    }
                    active?.handle = handle
                    logger.info("Original download started; outstanding: 1")
                    if cancellation.isCancelled || active?.retired == true { requestCancellation() }
                } catch {
                    active = nil
                    continuation.resume(throwing: cancellation.isCancelled ? CancellationError() : error)
                    onSettled?()
                }
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor [weak self] in
                guard self?.active?.id == identifier else { return }
                self?.requestCancellation()
            }
        }
    }

    private func requestCancellation() {
        guard var operation = active, !operation.cancellationRequested, let handle = operation.handle else { return }
        operation.cancellationRequested = true
        active = operation
        handle.cancel()
        logger.info("Original download stop requested; waiting for completion")
    }

    private func receive(_ event: OriginalDownloadEvent, identifier: UUID) {
        guard var operation = active, operation.id == identifier else { return }
        switch event {
        case .progress(let value):
            guard !operation.cancellation.isCancelled, !operation.retired, sessionID == operation.sessionID else { return }
            operation.downloadedBytes = max(operation.downloadedBytes, value.downloadedBytes)
            active = operation
            operation.progress(DownloadProgress(downloadedBytes: operation.downloadedBytes, totalBytes: value.totalBytes))
        case .completed(let result):
            active = nil
            operation.handle?.cleanup()
            logger.info("Original download settled; outstanding: 0")
            if operation.cancellation.isCancelled {
                operation.continuation.resume(throwing: CancellationError())
            } else if operation.retired || sessionID != operation.sessionID {
                operation.continuation.resume(throwing: MediaSourceError.staleSession)
            } else {
                operation.continuation.resume(with: result.mapError { $0 as any Error })
            }
            onSettled?()
        }
    }
}

private final class OriginalDownloadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() { lock.withLock { cancelled = true } }
}
