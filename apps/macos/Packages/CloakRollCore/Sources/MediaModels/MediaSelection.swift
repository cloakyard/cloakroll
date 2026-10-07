import Foundation

/// Finder-style selection independent of views, resource handles, and catalog storage.
public struct MediaSelection: Equatable, Sendable {
    public private(set) var selectedIDs: Set<String>
    public private(set) var anchorID: String?

    public init(selectedIDs: Set<String> = [], anchorID: String? = nil) {
        self.selectedIDs = selectedIDs
        self.anchorID = anchorID
    }

    public mutating func select(
        id: String,
        orderedIDs: [String],
        extendingRange: Bool = false,
        toggling: Bool = false
    ) {
        guard let targetIndex = orderedIDs.firstIndex(of: id) else { return }
        if extendingRange,
           let anchorID,
           let anchorIndex = orderedIDs.firstIndex(of: anchorID) {
            let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
            let rangeIDs = Set(orderedIDs[range])
            selectedIDs = toggling ? selectedIDs.union(rangeIDs) : rangeIDs
        } else if toggling {
            if !selectedIDs.insert(id).inserted {
                selectedIDs.remove(id)
            }
            anchorID = id
        } else {
            selectedIDs = [id]
            anchorID = id
        }
    }

    public mutating func selectAll(_ ids: [String]) {
        selectedIDs = Set(ids)
        anchorID = ids.first
    }

    /// Add or remove a visible group without replacing selections in other groups.
    /// The first added item becomes the range anchor; removing that anchor repairs it.
    public mutating func setSelected(_ selected: Bool, ids: [String], orderedIDs: [String]) {
        let group = Set(ids).intersection(orderedIDs)
        guard !group.isEmpty else { return }
        selectedIDs.formIntersection(orderedIDs)
        if selected {
            selectedIDs.formUnion(group)
            anchorID = orderedIDs.first(where: group.contains)
        } else {
            selectedIDs.subtract(group)
            if anchorID.map({ selectedIDs.contains($0) }) != true {
                anchorID = orderedIDs.first(where: selectedIDs.contains)
            }
        }
    }

    /// Hidden or removed items cannot remain selected after a new projection.
    public mutating func reconcile(with ids: [String]) {
        let visibleIDs = Set(ids)
        selectedIDs.formIntersection(visibleIDs)
        if let anchorID, !visibleIDs.contains(anchorID) {
            self.anchorID = nil
        }
    }

    public mutating func clear() {
        selectedIDs.removeAll()
        anchorID = nil
    }
}
