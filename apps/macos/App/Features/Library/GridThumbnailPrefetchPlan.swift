import Foundation
import MediaModels

/// Section rows, independent of whether SwiftUI has instantiated their cells yet.
struct GridThumbnailPrefetchPlan: Sendable {
    private let rows: [ArraySlice<MediaAsset>]
    private let positions: [String: Int]

    init(sections: [MediaSection], columns: Int) throws {
        let width = max(1, columns)
        var rows: [ArraySlice<MediaAsset>] = []
        var positions: [String: Int] = [:]
        for section in sections {
            for start in stride(from: 0, to: section.assets.count, by: width) {
                try Task.checkCancellation()
                let row = section.assets[start..<min(start + width, section.assets.count)]
                for asset in row { positions[asset.id] = rows.count }
                rows.append(row)
            }
        }
        self.rows = rows
        self.positions = positions
    }

    func contains(_ id: String) -> Bool { positions[id] != nil }

    /// Two actual rows ahead, then one behind. No work is inferred until cells report visibility.
    func candidates(visibleIDs: Set<String>, limit: Int = 32) -> [MediaAsset] {
        let visibleRows = visibleIDs.compactMap { positions[$0] }
        guard let first = visibleRows.min(), let last = visibleRows.max(), limit > 0 else { return [] }
        var rowIndices: [Int] = []
        for row in (last + 1)...(last + 2) where row < rows.count { rowIndices.append(row) }
        if first > 0 { rowIndices.append(first - 1) }
        var result: [MediaAsset] = []
        for row in rowIndices {
            for asset in rows[row] where !visibleIDs.contains(asset.id) {
                result.append(asset)
                if result.count == limit { return result }
            }
        }
        return result
    }
}
