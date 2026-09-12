import Foundation

/// Bounded logical work and encoded caches. The source adapter separately owns the lifetime and
/// limit of actual USB operations, which may outlive cancellation of a source-loading closure.
public actor ThumbnailPipeline {
    private struct Consumer {
        let continuation: CheckedContinuation<Data, any Error>
        let cancellation: ThumbnailConsumerCancellation
        let priority: ThumbnailPriority
    }

    private struct Request {
        let id: UUID
        let key: ThumbnailKey
        let generation: UUID
        let load: @Sendable () async throws -> Data
        var priority: ThumbnailPriority
        var consumers: [UUID: Consumer]
        var task: Task<Void, Never>?
    }

    private let configuration: ThumbnailPipelineConfiguration
    private var memory: ThumbnailMemoryCache
    private var disk: ThumbnailDiskCache
    private var sessionID: UUID?
    private var hasInitializedSession = false
    private var generation = UUID()
    private var requests: [UUID: Request] = [:]
    private var currentRequests: [ThumbnailKey: UUID] = [:]
    private var queued: [UUID] = []
    private var active: Set<UUID> = []
    private var memoryHits = 0
    private var diskHits = 0
    private var sourceLoads = 0
    private var coalesced = 0
    private var failed = 0

    public init(cacheDirectory: URL? = nil, configuration: ThumbnailPipelineConfiguration = .init()) {
        self.configuration = configuration
        memory = ThumbnailMemoryCache(configuration: configuration)
        disk = ThumbnailDiskCache(directory: cacheDirectory, configuration: configuration)
    }

    public func setSession(_ sessionID: UUID?) {
        guard !hasInitializedSession || self.sessionID != sessionID else { return }
        hasInitializedSession = true
        self.sessionID = sessionID
        generation = UUID()
        memory.discardSessionScopedEntries()
        disk.setSession(sessionID)
        currentRequests.removeAll()
        queued.removeAll()
        for identifier in Array(requests.keys) {
            guard var request = requests[identifier] else { continue }
            for consumer in request.consumers.values {
                consumer.continuation.resume(throwing: MediaError.forRetiredConsumer(consumer.cancellation))
            }
            request.consumers.removeAll()
            if active.contains(identifier) {
                request.task?.cancel()
                requests[identifier] = request
            } else {
                requests[identifier] = nil
            }
        }
        // An active task may ignore cancellation. Its slot is retained until complete runs.
    }

    public func data(
        for key: ThumbnailKey,
        priority: ThumbnailPriority = .visible,
        load: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let consumerID = UUID()
        let cancellation = ThumbnailConsumerCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                accept(key, priority: priority, consumerID: consumerID, cancellation: cancellation,
                       continuation: continuation, load: load)
            }
        } onCancel: {
            cancellation.cancel()
            Task { await self.cancel(consumerID, key: key) }
        }
    }

    public func metrics() -> ThumbnailPipelineMetrics {
        ThumbnailPipelineMetrics(
            memoryHits: memoryHits, diskHits: diskHits, sourceLoads: sourceLoads, coalesced: coalesced,
            failed: failed, memoryBytes: memory.bytes, memoryItems: memory.count,
            diskBytes: disk.bytes, diskItems: disk.count, diskFailures: disk.failures,
            active: active.count, queued: queued.count
        )
    }

    private func accept(
        _ key: ThumbnailKey, priority: ThumbnailPriority, consumerID: UUID,
        cancellation: ThumbnailConsumerCancellation, continuation: CheckedContinuation<Data, any Error>,
        load: @escaping @Sendable () async throws -> Data
    ) {
        guard !cancellation.isCancelled else { continuation.resume(throwing: CancellationError()); return }
        guard key.sessionID == sessionID else { continuation.resume(throwing: ThumbnailPipelineError.staleSession); return }
        if let cached = memory.data(for: key.storageKey) {
            memoryHits += 1
            continuation.resume(returning: cached)
            return
        }
        if let cached = disk.data(for: key.storageKey) {
            guard !cancellation.isCancelled else { continuation.resume(throwing: CancellationError()); return }
            diskHits += 1
            memory.insert(cached, for: key.storageKey)
            continuation.resume(returning: cached)
            return
        }
        guard !cancellation.isCancelled else { continuation.resume(throwing: CancellationError()); return }
        let consumer = Consumer(continuation: continuation, cancellation: cancellation, priority: priority)
        if let identifier = currentRequests[key], var request = requests[identifier] {
            request.consumers[consumerID] = consumer
            if priority == .visible { request.priority = .visible }
            requests[identifier] = request
            coalesced += 1
        } else {
            guard queued.count < configuration.maximumQueuedRequests || canStart(priority) else {
                continuation.resume(throwing: ThumbnailPipelineError.queueFull)
                return
            }
            let identifier = UUID()
            requests[identifier] = Request(
                id: identifier, key: key, generation: generation, load: load, priority: priority,
                consumers: [consumerID: consumer]
            )
            currentRequests[key] = identifier
            queued.append(identifier)
        }
        pump()
    }

    private func cancel(_ consumerID: UUID, key: ThumbnailKey) {
        guard let identifier = currentRequests[key], var request = requests[identifier],
              let consumer = request.consumers.removeValue(forKey: consumerID) else { return }
        consumer.continuation.resume(throwing: CancellationError())
        requests[identifier] = request
        if request.consumers.isEmpty, !active.contains(identifier) { removeQueued(identifier) }
        // Active work can still populate the cache or acquire a new consumer. Do not cancel it.
        pump()
    }

    private func canStart(_ priority: ThumbnailPriority) -> Bool {
        active.count < configuration.maximumActiveLoads && (priority == .visible || !hasActivePrefetch)
    }

    private var hasActivePrefetch: Bool {
        active.contains { requests[$0]?.priority == .prefetch }
    }

    private func pump() {
        refreshQueuedDemand()
        while active.count < configuration.maximumActiveLoads {
            let next = queued.first { requests[$0]?.priority == .visible }
                ?? (!hasActivePrefetch ? queued.first : nil)
            guard let identifier = next, var request = requests[identifier] else { return }
            queued.removeAll { $0 == identifier }
            active.insert(identifier)
            sourceLoads += 1
            let load = request.load
            request.task = Task.detached(priority: request.priority == .visible ? .userInitiated : .utility) { [weak self] in
                let result: Result<Data, any Error>
                do { result = .success(try await load()) } catch { result = .failure(error) }
                await self?.complete(identifier, result: result)
            }
            requests[identifier] = request
        }
    }

    private func refreshQueuedDemand() {
        for identifier in queued {
            guard var request = requests[identifier] else { continue }
            for consumerID in Array(request.consumers.keys) {
                guard let consumer = request.consumers[consumerID], consumer.cancellation.isCancelled else { continue }
                request.consumers[consumerID] = nil
                consumer.continuation.resume(throwing: CancellationError())
            }
            if request.consumers.isEmpty {
                removeQueued(identifier)
            } else {
                request.priority = request.consumers.values.contains { $0.priority == .visible } ? .visible : .prefetch
                requests[identifier] = request
            }
        }
    }

    private func removeQueued(_ identifier: UUID) {
        guard let request = requests.removeValue(forKey: identifier) else { return }
        if currentRequests[request.key] == identifier { currentRequests[request.key] = nil }
        queued.removeAll { $0 == identifier }
    }

    private func complete(_ identifier: UUID, result: Result<Data, any Error>) {
        guard let request = requests.removeValue(forKey: identifier) else { return }
        active.remove(identifier)
        if currentRequests[request.key] == identifier { currentRequests[request.key] = nil }
        guard request.generation == generation, request.key.sessionID == sessionID else { pump(); return }
        let validated = result.flatMap { data -> Result<Data, any Error> in
            if data.isEmpty { return .failure(ThumbnailPipelineError.emptyData) }
            if data.count > configuration.maximumDataBytes { return .failure(ThumbnailPipelineError.oversizedData) }
            return .success(data)
        }
        switch validated {
        case .success(let data):
            memory.insert(data, for: request.key.storageKey)
            disk.insert(data, for: request.key.storageKey)
        case .failure:
            failed += 1
        }
        for consumer in request.consumers.values {
            if consumer.cancellation.isCancelled {
                consumer.continuation.resume(throwing: CancellationError())
            } else {
                consumer.continuation.resume(with: validated)
            }
        }
        pump()
    }
}

private enum MediaError {
    static func forRetiredConsumer(_ cancellation: ThumbnailConsumerCancellation) -> any Error {
        cancellation.isCancelled ? CancellationError() : ThumbnailPipelineError.staleSession
    }
}

/// Cancellation handlers can run outside the pipeline actor, including before enqueueing.
private final class ThumbnailConsumerCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}
