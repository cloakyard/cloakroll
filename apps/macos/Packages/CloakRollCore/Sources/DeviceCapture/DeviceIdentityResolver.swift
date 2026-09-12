import Foundation
import ImageCaptureCore
import MediaModels

enum DeviceIdentityResolver {
    static func resolve(
        persistentID: String?, serialNumber: String?, uuid: String?, sessionID: UUID
    ) -> DeviceIdentity {
        let candidates: [(DeviceIdentity.Kind, String?)] = [
            (.persistent, persistentID), (.serialNumber, serialNumber), (.uuid, uuid)
        ]
        for (kind, candidate) in candidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return DeviceIdentity(kind: kind, value: value)
            }
        }
        return DeviceIdentity(kind: .sessionOnly, value: sessionID.uuidString)
    }
}

enum DeviceClassification {
    /// Vendor plus transport plus product metadata; the user-editable display name is deliberately absent.
    static func isSupported(productKind: String?, usbVendorID: Int, transportType: String?) -> Bool {
        guard usbVendorID == 0x05AC,
              transportType == ICDeviceTransport.transportTypeUSB.rawValue,
              let product = productKind?.lowercased() else { return false }
        return ["iphone", "ipad", "ipod"].contains { product.contains($0) }
    }
}
