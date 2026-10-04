import Foundation
import MediaModels

/// Pure inventory policy; framework handles stay in DeviceBrowserService. Opaque addresses
/// are stable only while that exact discovered object remains in this browser's inventory.
struct DeviceSelectionRegistry {
    private struct Entry {
        let key: ObjectIdentifier
        var item: DeviceSelectionItem
    }

    private var entries: [Entry] = []
    private(set) var selectedID: UUID?

    var inventory: DeviceInventory { DeviceInventory(devices: entries.map(\.item), selectedID: selectedID) }
    var firstID: UUID? { entries.first?.item.id }

    func key(for id: UUID) -> ObjectIdentifier? { entries.first { $0.item.id == id }?.key }

    mutating func upsert(_ key: ObjectIdentifier, name: String, productKind: String?) {
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries[index].item = DeviceSelectionItem(id: entries[index].item.id, displayName: name, productKind: productKind)
        } else {
            entries.append(Entry(key: key, item: DeviceSelectionItem(id: UUID(), displayName: name, productKind: productKind)))
        }
    }

    @discardableResult mutating func select(_ id: UUID, originalIsBusy: Bool) -> Bool {
        guard key(for: id) != nil else { return false }
        guard selectedID != id else { return true }
        guard !originalIsBusy else { return false }
        selectedID = id
        return true
    }

    mutating func remove(_ key: ObjectIdentifier) {
        if let selectedID, self.key(for: selectedID) == key { self.selectedID = nil }
        entries.removeAll { $0.key == key }
    }

    mutating func reset() {
        entries.removeAll()
        selectedID = nil
    }
}
