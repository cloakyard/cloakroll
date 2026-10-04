import MediaModels
import SwiftUI

struct DevicePickerOption: Identifiable, Equatable {
    let id: UUID
    let title: String

    static func make(from devices: [DeviceSelectionItem]) -> [DevicePickerOption] {
        let counts = Dictionary(grouping: devices, by: \.displayName).mapValues(\.count)
        var occurrences: [String: Int] = [:]
        return devices.map { device in
            occurrences[device.displayName, default: 0] += 1
            let number = occurrences[device.displayName, default: 1]
            let title = counts[device.displayName, default: 0] > 1 ? "\(device.displayName) (\(number))" : device.displayName
            return DevicePickerOption(id: device.id, title: title)
        }
    }
}

/// The system picker supplies selection, keyboard navigation, accessibility and appearance.
struct ConnectedDevicePicker: View {
    let inventory: DeviceInventory
    let isEnabled: Bool
    let select: (UUID) -> Void

    var body: some View {
        Picker("iPhone", selection: selection) {
            if inventory.selectedID == nil {
                Text("Choose iPhone").tag(nil as UUID?)
            }
            ForEach(DevicePickerOption.make(from: inventory.devices)) { device in
                Text(device.title).tag(Optional(device.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .disabled(!isEnabled)
        .accessibilityLabel("iPhone")
        .help(isEnabled ? "Choose the iPhone to browse." : "Wait for the current operation to finish before switching iPhones.")
    }

    private var selection: Binding<UUID?> {
        Binding(get: { inventory.selectedID }, set: { if let value = $0 { select(value) } })
    }
}
