import Foundation

/// Exact lowercase byte encoding shared by persisted digests and metadata identities.
/// Package visibility keeps this implementation detail out of the app's public model API.
package enum HexEncoding {
    private static let digits = Array("0123456789abcdef".utf8)

    package static func lowercase(_ bytes: some Sequence<UInt8>) -> String {
        var encoded: [UInt8] = []
        encoded.reserveCapacity(bytes.underestimatedCount * 2)
        for byte in bytes {
            encoded.append(digits[Int(byte >> 4)])
            encoded.append(digits[Int(byte & 0x0f)])
        }
        return String(bytes: encoded, encoding: .utf8) ?? ""
    }
}
