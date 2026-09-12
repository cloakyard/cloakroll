import Foundation
import MediaModels

struct CatalogEntry {
    let record: SourceMediaRecord
    let key: String
    let classification: SourceMediaClassification

    var isMedia: Bool { classification.kind != .other }
}

/// Relationships are scoped to one device. Connected media groups with more than two members
/// are deliberately left separate; taking the first plausible pair would silently discard ambiguity.
struct CatalogRelationships {
    let entries: [CatalogEntry]
    private var uniqueIndices: [String: Int] = [:]
    private(set) var mediaLinks: [Int: Set<Int>] = [:]
    private(set) var sidecarLinks: [Int: Set<Int>] = [:]
    private var provenPairs: Set<Set<Int>> = []

    init(entries: [CatalogEntry]) {
        self.entries = entries
        let indices = Dictionary(grouping: entries.indices, by: { entries[$0].record.id })
        uniqueIndices = indices.compactMapValues { $0.count == 1 ? $0.first : nil }
        collectExplicitLinks()
        collectOrigins()
    }

    func mediaGroups() -> [[Int]] {
        var visited: Set<Int> = []
        var result: [[Int]] = []
        for index in entries.indices where entries[index].isMedia && !visited.contains(index) {
            let group = Self.component(startingAt: index, links: mediaLinks)
            visited.formUnion(group)
            if group.count == 2, provenPairs.contains(group) {
                result.append(group.sorted())
            } else {
                result.append(contentsOf: group.sorted().map { [$0] })
            }
        }
        return result
    }

    /// Each non-media component attaches only if all its supplied associations resolve to one
    /// logical media asset. Shared or orphaned sidecars remain independently visible resources.
    func sidecarAttachments(owners: [Int: Int]) -> [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        var visited: Set<Int> = []
        for index in entries.indices where !entries[index].isMedia && !visited.contains(index) {
            var pending = [index]
            var component: Set<Int> = []
            var candidates: Set<Int> = []
            while let current = pending.popLast() {
                guard component.insert(current).inserted else { continue }
                for neighbor in sidecarLinks[current, default: []] {
                    if let owner = owners[neighbor] {
                        candidates.insert(owner)
                    } else if !entries[neighbor].isMedia {
                        pending.append(neighbor)
                    }
                }
            }
            visited.formUnion(component)
            if candidates.count == 1, let owner = candidates.first {
                result[owner, default: []].append(contentsOf: component.sorted())
            }
        }
        return result
    }

    private mutating func collectExplicitLinks() {
        for index in entries.indices {
            let record = entries[index].record
            for identifier in Set(record.sidecarIDs) {
                guard let target = uniqueIndices[identifier], target != index,
                      uniqueIndices[record.id] != nil else { continue }
                if entries[index].isMedia && entries[target].isMedia {
                    linkMedia(index, target, provesPair: isSupportedPair(index, target))
                } else {
                    Self.link(index, target, into: &sidecarLinks)
                }
            }
            if let identifier = record.pairedRawID, let target = uniqueIndices[identifier],
               target != index, uniqueIndices[record.id] != nil,
               entries[index].isMedia && entries[target].isMedia {
                let provesPair = entries[index].classification.kind == .photo && entries[target].classification.kind == .raw
                linkMedia(index, target, provesPair: provesPair)
            }
        }
    }

    private mutating func collectOrigins() {
        var origins: [String: [Int]] = [:]
        for index in entries.indices {
            guard let identifier = entries[index].record.originatingAssetID,
                  !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            origins[identifier, default: []].append(index)
        }
        for group in origins.values {
            let media = group.filter { entries[$0].isMedia }
            let sidecars = group.filter { !entries[$0].isMedia }
            if let first = media.first {
                for target in media.dropFirst() {
                    let provesPair = media.count == 2 && isLivePhotoPair(first, target)
                    linkMedia(first, target, provesPair: provesPair)
                }
            }
            if let first = sidecars.first {
                for target in sidecars.dropFirst() { Self.link(first, target, into: &sidecarLinks) }
                for target in media { Self.link(first, target, into: &sidecarLinks) }
            }
        }
    }

    private func isSupportedPair(_ left: Int, _ right: Int) -> Bool {
        let kinds = Set([entries[left].classification.kind, entries[right].classification.kind])
        return kinds == [.photo, .raw] || isLivePhotoPair(left, right)
    }

    private func isLivePhotoPair(_ left: Int, _ right: Int) -> Bool {
        let first = entries[left].classification
        let second = entries[right].classification
        return (first.kind == .photo && second.isQuickTimeMovie) || (second.kind == .photo && first.isQuickTimeMovie)
    }

    private mutating func linkMedia(_ left: Int, _ right: Int, provesPair: Bool) {
        Self.link(left, right, into: &mediaLinks)
        if provesPair { provenPairs.insert([left, right]) }
    }

    private static func link(_ left: Int, _ right: Int, into links: inout [Int: Set<Int>]) {
        links[left, default: []].insert(right)
        links[right, default: []].insert(left)
    }

    private static func component(startingAt start: Int, links: [Int: Set<Int>]) -> Set<Int> {
        var pending = [start]
        var visited: Set<Int> = []
        while let current = pending.popLast() {
            guard visited.insert(current).inserted else { continue }
            pending.append(contentsOf: links[current, default: []].filter { !visited.contains($0) })
        }
        return visited
    }
}
