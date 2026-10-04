import Foundation

/// A browser-local address for choosing a discovered phone. It is never backup identity.
public struct DeviceSelectionItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let productKind: String?

    public init(id: UUID, displayName: String, productKind: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.productKind = productKind
    }
}

public struct DeviceInventory: Equatable, Sendable {
    public let devices: [DeviceSelectionItem]
    public let selectedID: UUID?

    public init(devices: [DeviceSelectionItem] = [], selectedID: UUID? = nil) {
        self.devices = devices
        self.selectedID = selectedID
    }
}

/// Optional capability for sources that expose more than one connected device.
@MainActor
public protocol DeviceSelectionBrowsing: DeviceBrowsing {
    var inventory: DeviceInventory { get }
    /// The current catalog namespace, for rejecting delayed envelopes from another selection.
    var selectedSessionID: UUID? { get }
    /// Authoritative current state, rather than a potentially buffered prior connection event.
    var selectedConnection: DeviceConnection { get }

    /// Returns false for an unknown selection or while a physical original is outstanding.
    /// Selecting the current device succeeds without reopening its session.
    @discardableResult func selectDevice(id: UUID) -> Bool
}
