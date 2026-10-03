import CryptoKit
import Foundation
import MediaModels

/// Conservative metadata matching for disposable previews, never backup or content identity.
/// Call only with a complete catalog and separately established persistent device identity.
public enum ThumbnailReuseIndex {
    public static func make(records: [SourceMediaRecord]) -> [String: String] {
        var resourceCounts: [String: Int] = [:]
        var candidates: [ThumbnailReuseSignature: Candidate] = [:]
        for record in records {
            resourceCounts[record.id, default: 0] += 1
            guard let signature = ThumbnailReuseSignature(record) else { continue }
            candidates[signature, default: Candidate(resourceID: record.id)].count += 1
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var result: [String: String] = [:]
        for (signature, candidate) in candidates {
            guard candidate.count == 1, resourceCounts[candidate.resourceID] == 1,
                  let data = try? encoder.encode(signature) else { continue }
            result[candidate.resourceID] = HexEncoding.lowercase(SHA256.hash(data: data))
        }
        return result
    }

    private struct Candidate {
        let resourceID: String
        var count = 0
    }
}

private struct ThumbnailReuseSignature: Hashable, Encodable {
    let schemaVersion = 1
    let deviceID: String
    let contextPath: [String]
    let filename: String
    let originalFilename: String?
    let byteCount: Int64
    let createdAt: Double
    let modifiedAt: Double?
    let uti: String
    let originatingAssetID: String?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let duration: Double?

    init?(_ record: SourceMediaRecord) {
        guard Self.hasText(record.id), Self.hasText(record.deviceID), Self.hasText(record.filename),
              let uti = record.uti, Self.hasText(uti), record.byteCount > 0,
              let createdAt = record.createdAt?.timeIntervalSince1970, createdAt.isFinite,
              record.contextPath.contains(where: Self.hasText) || Self.hasText(record.originatingAssetID),
              record.modifiedAt.map({ $0.timeIntervalSince1970.isFinite }) != false,
              record.duration.map({ $0.isFinite && $0 > 0 }) != false,
              record.pixelWidth.map({ $0 > 0 }) != false,
              record.pixelHeight.map({ $0 > 0 }) != false else { return nil }
        deviceID = record.deviceID
        contextPath = record.contextPath
        filename = record.filename
        originalFilename = record.originalFilename
        byteCount = record.byteCount
        self.createdAt = createdAt
        modifiedAt = record.modifiedAt?.timeIntervalSince1970
        self.uti = uti
        originatingAssetID = record.originatingAssetID
        pixelWidth = record.pixelWidth
        pixelHeight = record.pixelHeight
        duration = record.duration
    }

    private static func hasText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
