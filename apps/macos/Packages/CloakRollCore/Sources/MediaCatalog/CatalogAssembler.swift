import Foundation
import MediaModels

/// Turns a replaceable resource snapshot into logical assets without device I/O or actor affinity.
/// Identity follows the primary resource, so discovering a companion does not rename a still asset.
/// Source IDs are connection-scoped evidence; these IDs are not persisted backup-match guarantees.
public enum CatalogAssembler {
    public static func assemble(records: [SourceMediaRecord]) -> [MediaAsset] {
        var classifier = SourceMediaClassifier()
        let devices = Dictionary(grouping: records, by: \.deviceID)
        var result: [MediaAsset] = []
        result.reserveCapacity(records.count)
        for deviceID in devices.keys.sorted() {
            let entries = makeEntries(records: devices[deviceID, default: []], classifier: &classifier)
            result.append(contentsOf: assemble(entries: entries))
        }
        return result.sorted { $0.id < $1.id }
    }

    private static func assemble(entries: [CatalogEntry]) -> [MediaAsset] {
        let relationships = CatalogRelationships(entries: entries)
        let mediaGroups = relationships.mediaGroups()
        var owners: [Int: Int] = [:]
        for (owner, group) in mediaGroups.enumerated() {
            for index in group { owners[index] = owner }
        }
        let attachments = relationships.sidecarAttachments(owners: owners)
        var consumed: Set<Int> = []
        var result: [MediaAsset] = []
        for (owner, group) in mediaGroups.enumerated() {
            let members = group + attachments[owner, default: []]
            consumed.formUnion(members)
            result.append(makeAsset(indices: members, entries: entries))
        }
        for index in entries.indices where !consumed.contains(index) {
            result.append(makeAsset(indices: [index], entries: entries))
        }
        return result
    }

    private static func makeAsset(indices: [Int], entries: [CatalogEntry]) -> MediaAsset {
        // A rendered still is the useful preview for both RAW pairs and Live Photos.
        let primaryIndex = indices.first { entries[$0].classification.kind == .photo } ?? indices[0]
        let primary = entries[primaryIndex]
        let companions = indices.filter { $0 != primaryIndex }.sorted { entries[$0].key < entries[$1].key }
        let resources = ([primaryIndex] + companions).map { index in
            let record = entries[index].record
            return MediaResource(id: record.id, filename: record.filename, byteCount: record.byteCount)
        }
        let media = indices.filter { entries[$0].isMedia }
        let kind: MediaKind
        if media.count == 2 {
            kind = media.contains { entries[$0].classification.kind == .raw } ? .raw : .livePhoto
        } else {
            kind = primary.classification.kind
        }
        let duration = media.first { entries[$0].classification.kind == .video }.flatMap { entries[$0].record.duration }
        return MediaAsset(
            id: primary.key, deviceID: primary.record.deviceID, resources: resources, kind: kind,
            createdAt: primary.record.createdAt.flatMap { $0.timeIntervalSinceReferenceDate.isFinite ? $0 : nil },
            duration: duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
            pixelWidth: primary.record.pixelWidth.flatMap { $0 > 0 ? $0 : nil },
            pixelHeight: primary.record.pixelHeight.flatMap { $0 > 0 ? $0 : nil },
            primaryResourceID: primary.record.id
        )
    }

    private static func makeEntries(
        records: [SourceMediaRecord], classifier: inout SourceMediaClassifier
    ) -> [CatalogEntry] {
        let byID = Dictionary(grouping: records, by: \.id)
        var result: [CatalogEntry] = []
        for identifier in byID.keys.sorted() {
            let candidates = byID[identifier, default: []]
            // A valid adapter snapshot has unique IDs. Defensive handling preserves conflicting
            // records separately while refusing to resolve their ambiguous relationship references.
            let distinct = candidates.count == 1 ? candidates : Array(Set(candidates)).sorted { canonical($0) < canonical($1) }
            for (ordinal, record) in distinct.enumerated() {
                let key = "resource:\(record.deviceID.utf8.count):\(record.deviceID):\(identifier.utf8.count):\(identifier):\(ordinal)"
                result.append(CatalogEntry(record: record, key: key, classification: classifier.classify(record)))
            }
        }
        return result
    }

    private static func canonical(_ record: SourceMediaRecord) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "+infinity", negativeInfinity: "-infinity", nan: "nan"
        )
        return (try? encoder.encode(record)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
