import MediaModels

/// Deterministic injectable connection source; it never communicates with hardware.
@MainActor
public final class MockDeviceBrowserService: DeviceBrowsing {
    public let events: AsyncStream<DeviceEvent>
    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private var isRunning = false
    private var connection = DeviceConnection(state: .disconnected)

    public init() {
        let stream = AsyncStream<DeviceEvent>.makeStream(bufferingPolicy: .bufferingNewest(8))
        events = stream.stream
        continuation = stream.continuation
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        continuation.yield(.stateChanged(connection))
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

    deinit {
        continuation.finish()
    }
}
