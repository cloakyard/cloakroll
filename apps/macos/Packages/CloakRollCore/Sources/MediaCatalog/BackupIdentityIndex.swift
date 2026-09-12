import CryptoKit
import Foundation
import MediaModels

public enum BackupIdentityError: Error, Equatable, Sendable {
    case incompleteCatalog
    case inconsistentCatalog
}

/// Builds conservative original-file evidence, independently of disposable preview identities.
/// The caller supplies the complete catalog collected using originalAssets, and runs this
/// cancellable work off the main actor. Device scope is carried separately in the returned catalog.
public enum BackupIdentityIndex {
    public static func make(
        source: DeviceMediaSnapshot, assets: [MediaAsset], deviceIdentity: DeviceIdentity?
    ) throws -> BackupCatalogIdentity {
        try Task.checkCancellation()
        guard source.state == .complete else { throw BackupIdentityError.incompleteCatalog }
        guard hasText(source.deviceID), Set(assets.map(\.id)).count == assets.count,
              source.records.allSatisfy({ $0.deviceID == source.deviceID }),
              assets.allSatisfy({ $0.deviceID == source.deviceID }) else {
            throw BackupIdentityError.inconsistentCatalog
        }
        let encoder = canonicalEncoder()
        let index = try SourceIndex(records: source.records, encoder: encoder)
        var owners: [String: Int] = [:]
        for asset in assets {
            try Task.checkCancellation()
            for resource in asset.resources { owners[resource.id, default: 0] += 1 }
        }
        let persistent = deviceIdentity.map {
            $0.isPersistent && hasText($0.value) && $0.key == source.deviceID
        } ?? false
        var candidates: [AssetCandidate] = []
        var candidateCounts: [String: Int] = [:]
        for asset in assets {
            try Task.checkCancellation()
            let candidate = try AssetCandidate(asset: asset, index: index, owners: owners, encoder: encoder)
            candidates.append(candidate)
            candidateCounts[candidate.canonical, default: 0] += 1
        }
        var result: [String: BackupAssetIdentity] = [:]
        for candidate in candidates {
            try Task.checkCancellation()
            let reusable = persistent && candidate.isEligible && candidateCounts[candidate.canonical] == 1
            let canonical: String
            if reusable {
                canonical = candidate.canonical
            } else {
                canonical = try encode(SessionAssetEvidence(
                    evidence: candidate.canonical, deviceKey: source.deviceID, sessionID: source.sessionID,
                    assetID: candidate.asset.id, resources: candidate.asset.resources.sorted { $0.id < $1.id }
                ), using: encoder)
            }
            let assetDigest = digest(canonical)
            var resources: [String: BackupResourceIdentity] = [:]
            for resource in candidate.asset.resources {
                try Task.checkCancellation()
                let resourceCanonical = try encode(ResourceEvidence(
                    assetDigest: assetDigest, component: candidate.components[resource.id, default: ""],
                    runtimeID: reusable ? nil : resource.id
                ), using: encoder)
                resources[resource.id] = BackupResourceIdentity(
                    resourceID: resource.id, canonical: resourceCanonical, digest: digest(resourceCanonical),
                    isReusableAcrossConnections: reusable
                )
            }
            result[candidate.asset.id] = BackupAssetIdentity(
                assetID: candidate.asset.id, canonical: canonical, digest: assetDigest,
                isReusableAcrossConnections: reusable, resources: resources
            )
        }
        return BackupCatalogIdentity(deviceKey: source.deviceID, sessionID: source.sessionID, assets: result)
    }

    fileprivate static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "+infinity", negativeInfinity: "-infinity", nan: "nan"
        )
        return encoder
    }

    fileprivate static func encode(_ value: some Encodable, using encoder: JSONEncoder) throws -> String {
        guard let canonical = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw BackupIdentityError.inconsistentCatalog
        }
        return canonical
    }

    fileprivate static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    fileprivate static func hasText(_ value: String?) -> Bool {
        value.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
    }
}

private struct SourceIndex {
    struct Entry {
        let record: SourceMediaRecord
        let canonical: String
        let isEligible: Bool
    }

    var entries: [String: [Entry]] = [:]
    var evidenceCounts: [String: Int] = [:]
    var duplicateDigests: [String: String] = [:]

    init(records: [SourceMediaRecord], encoder: JSONEncoder) throws {
        for record in records {
            try Task.checkCancellation()
            let facts = SourceFacts(record)
            let canonical = try BackupIdentityIndex.encode(facts, using: encoder)
            entries[record.id, default: []].append(Entry(
                record: record, canonical: canonical, isEligible: facts.isEligible && BackupIdentityIndex.hasText(record.id)
            ))
            evidenceCounts[canonical, default: 0] += 1
        }
        for (identifier, candidates) in entries where candidates.count != 1 {
            try Task.checkCancellation()
            // These variants are already ineligible for reconnect reuse. Preserve runtime links
            // too, so an ambiguous record changing within this session cannot reuse older evidence.
            let variants = try candidates.map { try BackupIdentityIndex.encode($0.record, using: encoder) }.sorted()
            duplicateDigests[identifier] = BackupIdentityIndex.digest(try BackupIdentityIndex.encode(variants, using: encoder))
        }
    }

    func unique(_ identifier: String) -> Entry? {
        guard let candidates = entries[identifier], candidates.count == 1 else { return nil }
        return candidates.first
    }
}

private struct AssetCandidate {
    let asset: MediaAsset
    let canonical: String
    let components: [String: String]
    let isEligible: Bool

    init(asset: MediaAsset, index: SourceIndex, owners: [String: Int], encoder: JSONEncoder) throws {
        self.asset = asset
        let memberIDs = Set(asset.resources.map(\.id))
        guard memberIDs.count == asset.resources.count else { throw BackupIdentityError.inconsistentCatalog }
        var eligible = !memberIDs.isEmpty && BackupIdentityIndex.hasText(asset.id)
        var components: [String: String] = [:]
        for resource in asset.resources {
            try Task.checkCancellation()
            guard let entry = index.unique(resource.id) else {
                eligible = false
                components[resource.id] = try BackupIdentityIndex.encode(MissingSourceEvidence(
                    resource: resource, ambiguousSourceDigest: index.duplicateDigests[resource.id]
                ), using: encoder)
                continue
            }
            let links = try SourceLinks(record: entry.record, index: index, memberIDs: memberIDs)
            eligible = eligible && entry.isEligible && index.evidenceCounts[entry.canonical] == 1
                && owners[resource.id] == 1 && links.isResolved && Self.matches(resource, entry.record)
            components[resource.id] = try BackupIdentityIndex.encode(ComponentEvidence(
                facts: entry.canonical, sidecars: links.sidecars, pairedRaw: links.pairedRaw,
                unresolvedSidecars: links.unresolvedSidecars, unresolvedPairedRaw: links.unresolvedPairedRaw
            ), using: encoder)
        }
        let primary = asset.primaryResourceID.flatMap { components[$0] }
        eligible = eligible && primary != nil && Self.hasValidLogicalMetadata(asset)
        canonical = try BackupIdentityIndex.encode(AssetEvidence(
            kind: asset.kind, createdAt: asset.createdAt?.timeIntervalSince1970, duration: asset.duration,
            pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight,
            primaryComponent: primary, components: components.values.sorted()
        ), using: encoder)
        self.components = components
        isEligible = eligible
    }

    private static func matches(_ resource: MediaResource, _ record: SourceMediaRecord) -> Bool {
        resource.filename == record.filename && resource.byteCount == record.byteCount && resource.modifiedAt == record.modifiedAt
    }

    private static func hasValidLogicalMetadata(_ asset: MediaAsset) -> Bool {
        asset.createdAt.map { $0.timeIntervalSince1970.isFinite } == true
            && asset.duration.map { $0.isFinite && $0 > 0 } != false
            && asset.pixelWidth.map { $0 > 0 } != false && asset.pixelHeight.map { $0 > 0 } != false
    }
}

private struct SourceLinks {
    var sidecars: [String] = []
    var pairedRaw: String?
    var unresolvedSidecars: [String] = []
    var unresolvedPairedRaw: String?
    var isResolved = true

    init(record: SourceMediaRecord, index: SourceIndex, memberIDs: Set<String>) throws {
        for identifier in Set(record.sidecarIDs).sorted() {
            try Task.checkCancellation()
            if let target = index.unique(identifier), identifier != record.id, memberIDs.contains(identifier) {
                sidecars.append(target.canonical)
            } else {
                unresolvedSidecars.append(identifier)
                isResolved = false
            }
        }
        sidecars.sort()
        if let identifier = record.pairedRawID {
            if let target = index.unique(identifier), identifier != record.id, memberIDs.contains(identifier) {
                pairedRaw = target.canonical
            } else {
                unresolvedPairedRaw = identifier
                isResolved = false
            }
        }
    }
}

private struct SourceFacts: Encodable {
    let filename: String
    let originalFilename: String?
    let contextPath: [String]
    let uti: String?
    let isRaw: Bool
    let byteCount: Int64
    let createdAt: Double?
    let modifiedAt: Double?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let duration: Double?
    let originatingAssetID: String?
    let groupUUID: String?
    let relatedUUID: String?
    let burstUUID: String?

    init(_ record: SourceMediaRecord) {
        filename = record.filename
        originalFilename = record.originalFilename
        contextPath = record.contextPath
        uti = record.uti
        isRaw = record.isRaw
        byteCount = record.byteCount
        createdAt = record.createdAt?.timeIntervalSince1970
        modifiedAt = record.modifiedAt?.timeIntervalSince1970
        pixelWidth = record.pixelWidth
        pixelHeight = record.pixelHeight
        duration = record.duration
        originatingAssetID = record.originatingAssetID
        groupUUID = record.groupUUID
        relatedUUID = record.relatedUUID
        burstUUID = record.burstUUID
    }

    var isEligible: Bool {
        BackupIdentityIndex.hasText(filename) && BackupIdentityIndex.hasText(uti) && byteCount > 0
            && !contextPath.isEmpty && contextPath.allSatisfy(BackupIdentityIndex.hasText)
            && createdAt.map(\.isFinite) == true && modifiedAt.map(\.isFinite) != false
            && duration.map { $0.isFinite && $0 > 0 } != false
            && pixelWidth.map { $0 > 0 } != false && pixelHeight.map { $0 > 0 } != false
    }
}

private struct ComponentEvidence: Encodable {
    let facts: String
    let sidecars: [String]
    let pairedRaw: String?
    let unresolvedSidecars: [String]
    let unresolvedPairedRaw: String?
}

private struct AssetEvidence: Encodable {
    let schemaVersion = 1
    let representation = "originalAssets"
    let kind: MediaKind
    let createdAt: Double?
    let duration: Double?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let primaryComponent: String?
    let components: [String]
}

private struct SessionAssetEvidence: Encodable {
    let schemaVersion = 1
    let scope = "connection"
    let evidence: String
    let deviceKey: String
    let sessionID: UUID
    let assetID: String
    let resources: [MediaResource]
}

private struct ResourceEvidence: Encodable {
    let schemaVersion = 1
    let representation = "originalAssets"
    let assetDigest: String
    let component: String
    let runtimeID: String?
}

private struct MissingSourceEvidence: Encodable {
    let resource: MediaResource
    let ambiguousSourceDigest: String?
}
