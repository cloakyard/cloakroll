import Foundation

public struct DeviceIdentity: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case persistent
        case serialNumber
        case uuid
        case sessionOnly
    }

    public let kind: Kind
    public let value: String

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    public var isPersistent: Bool { kind != .sessionOnly }
    public var key: String { "\(kind.rawValue):\(value)" }
}

public struct ConnectedDevice: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let identity: DeviceIdentity?
    public let productKind: String?

    /// Preserves fixture and existing value-model compatibility.
    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
        self.identity = nil
        self.productKind = nil
    }

    public init(identity: DeviceIdentity, name: String, productKind: String? = nil) {
        self.id = identity.key
        self.displayName = name
        self.identity = identity
        self.productKind = productKind
    }

    public var name: String { displayName }
}

public enum DeviceConnectionState: String, Codable, Sendable {
    case disconnected
    case opening
    case restricted
    case ready
    case unavailable
}

public struct DeviceConnection: Equatable, Sendable {
    public let device: ConnectedDevice?
    public let state: DeviceConnectionState
    public let message: String?

    public init(device: ConnectedDevice? = nil, state: DeviceConnectionState, message: String? = nil) {
        self.device = device
        self.state = state
        self.message = message
    }
}

public enum DeviceEvent: Equatable, Sendable {
    case stateChanged(DeviceConnection)
    case inventoryChanged(DeviceInventory)
}

/// One consumer owns this stream. Recreate the service after cancelling that consumer.
@MainActor
public protocol DeviceBrowsing: AnyObject {
    var events: AsyncStream<DeviceEvent> { get }
    func start()
    func stop()
    func retry()
}
