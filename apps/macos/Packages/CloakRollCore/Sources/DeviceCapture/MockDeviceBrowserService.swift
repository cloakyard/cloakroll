import MediaModels

/// Deterministic injectable connection source; it never communicates with hardware.
@MainActor
public final class MockDeviceBrowserService: DeviceMediaSource {
    public let events: AsyncStream<DeviceEvent>
    public let catalogs: AsyncStream<DeviceMediaSnapshot>
    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private let catalogContinuation: AsyncStream<DeviceMediaSnapshot>.Continuation
    private var latestCatalog: DeviceMediaSnapshot?
    private var isRunning = false
    private var connection = DeviceConnection(state: .disconnected)

    public init() {
        let stream = AsyncStream<DeviceEvent>.makeStream(bufferingPolicy: .bufferingNewest(8))
        events = stream.stream
        continuation = stream.continuation
        let catalogs = AsyncStream<DeviceMediaSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.catalogs = catalogs.stream
        catalogContinuation = catalogs.continuation
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        continuation.yield(.stateChanged(connection))
        if let latestCatalog { catalogContinuation.yield(latestCatalog) }
    }

    public func stop() {
        isRunning = false
        connection = DeviceConnection(state: .disconnected)
        continuation.yield(.stateChanged(connection))
    }

    public func retry() {
        guard isRunning else { return }
        continuation.yield(.stateChanged(connection))
    }

    public func send(_ connection: DeviceConnection) {
        self.connection = connection
        if isRunning { continuation.yield(.stateChanged(connection)) }
    }

    public func sendCatalog(_ snapshot: DeviceMediaSnapshot) {
        latestCatalog = snapshot
        if isRunning { catalogContinuation.yield(snapshot) }
    }

    deinit {
        continuation.finish()
        catalogContinuation.finish()
    }
}
