import CryptoKit
import Foundation

enum ThumbnailDiskCodec {
    static let maximumHeaderBytes = 64 * 1_024
    private static let magic = Data("CRTHMB01".utf8)

    private struct Header: Codable {
        let key: ThumbnailKey
        let byteCount: Int
        let digest: String
    }

    static func filename(for key: ThumbnailKey) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(key), data.count <= maximumHeaderBytes else { return nil }
        return digest(data) + ".thumb"
    }

    static func encode(_ data: Data, key: ThumbnailKey) -> Data? {
        let header = Header(key: key, byteCount: data.count, digest: digest(data))
        guard let encoded = try? JSONEncoder().encode(header), encoded.count <= maximumHeaderBytes else { return nil }
        var result = magic
        let length = UInt32(encoded.count)
        result.append(contentsOf: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: length >> $0) })
        result.append(encoded)
        result.append(data)
        return result
    }

    static func decode(_ data: Data, key: ThumbnailKey, maximumDataBytes: Int) -> Data? {
        guard data.count >= 12, data.prefix(8) == magic else { return nil }
        let headerLength = data[8..<12].reduce(0) { ($0 << 8) | Int($1) }
        guard headerLength > 0, headerLength <= maximumHeaderBytes, headerLength <= data.count - 12,
              let header = try? JSONDecoder().decode(Header.self, from: data[12..<(12 + headerLength)]),
              header.key == key, header.byteCount > 0, header.byteCount <= maximumDataBytes,
              header.byteCount == data.count - 12 - headerLength else { return nil }
        let payload = Data(data[(12 + headerLength)...])
        return digest(payload) == header.digest ? payload : nil
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
