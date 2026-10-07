import Foundation

public enum LibraryFilter: String, CaseIterable, Codable, Sendable {
    case all
    case photos
    case videos
    case livePhotos
    case raw
    case notBackedUp
    case backedUp
    case recentlyBackedUp
}

public enum CatalogSort: String, CaseIterable, Codable, Sendable {
    case newestFirst
    case oldestFirst
}

public enum CatalogGrouping: String, CaseIterable, Codable, Sendable {
    case automatic
    case day
    case month
    case year
}

public struct CatalogQuery: Equatable, Sendable {
    public var filter: LibraryFilter
    public var search: String
    public var sort: CatalogSort
    public var grouping: CatalogGrouping
    public var captureDateRange: CaptureDateRange?

    public init(
        filter: LibraryFilter = .all,
        search: String = "",
        sort: CatalogSort = .newestFirst,
        grouping: CatalogGrouping = .automatic,
        captureDateRange: CaptureDateRange? = nil
    ) {
        self.filter = filter
        self.search = search
        self.sort = sort
        self.grouping = grouping
        self.captureDateRange = captureDateRange
    }
}

public struct MediaSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date?
    public let assets: [MediaAsset]
    /// Resolved grouping, never `.automatic` in a projected section.
    public let grouping: CatalogGrouping

    public init(id: String, date: Date?, assets: [MediaAsset], grouping: CatalogGrouping = .day) {
        self.id = id
        self.date = date
        self.assets = assets
        self.grouping = grouping
    }
}

public struct CatalogSnapshot: Equatable, Sendable {
    public let sections: [MediaSection]
    /// Sidebar counts are for the full source catalog, independently of search and filter.
    public let counts: [LibraryFilter: Int]
    public let orderedIDs: [String]
    public let totalCount: Int
    /// Every item without a confirmed backup remains eligible, including uncertain/failed items.
    public let newCount: Int
    public let newBytes: Int64
    /// Eligible items after the current category, capture-date filter and filename search, matching backup candidates.
    public let visibleNewCount: Int
    public let visibleNewBytes: Int64
    public let totalBytes: Int64
    public let grouping: CatalogGrouping

    public var filteredCount: Int { orderedIDs.count }

    public init(
        sections: [MediaSection],
        counts: [LibraryFilter: Int],
        orderedIDs: [String],
        totalCount: Int,
        newCount: Int,
        newBytes: Int64,
        totalBytes: Int64,
        grouping: CatalogGrouping = .day,
        visibleNewCount: Int? = nil,
        visibleNewBytes: Int64? = nil
    ) {
        self.sections = sections
        self.counts = counts
        self.orderedIDs = orderedIDs
        self.totalCount = totalCount
        self.newCount = newCount
        self.newBytes = newBytes
        self.visibleNewCount = visibleNewCount ?? newCount
        self.visibleNewBytes = visibleNewBytes ?? newBytes
        self.totalBytes = totalBytes
        self.grouping = grouping
    }

    public static let empty = CatalogSnapshot(
        sections: [],
        counts: Dictionary(uniqueKeysWithValues: LibraryFilter.allCases.map { ($0, 0) }),
        orderedIDs: [],
        totalCount: 0,
        newCount: 0,
        newBytes: 0,
        totalBytes: 0
    )
}
