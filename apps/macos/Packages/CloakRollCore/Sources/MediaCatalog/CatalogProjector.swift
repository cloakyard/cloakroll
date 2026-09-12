import Foundation
import MediaModels

/// Prepares a complete immutable view of the library away from the UI actor.
/// Superseded requests throw CancellationError without publishing a partial snapshot.
public actor CatalogProjector {
    public init() {}

    public func project(
        assets: [MediaAsset],
        statuses: [String: BackupStatus],
        backupDates: [String: Date],
        query: CatalogQuery,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> CatalogSnapshot {
        try Task.checkCancellation()
        let recentStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        var counts = Dictionary(uniqueKeysWithValues: LibraryFilter.allCases.map { ($0, 0) })
        var totalBytes: Int64 = 0
        var newBytes: Int64 = 0
        var visibleNewCount = 0
        var visibleNewBytes: Int64 = 0
        var filtered: [MediaAsset] = []
        filtered.reserveCapacity(assets.count)

        for (index, asset) in assets.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let status = statuses[asset.id] ?? .notBackedUp
            let isRecent = status == .backedUp && backupDates[asset.id].map {
                $0 >= recentStart && $0 <= now
            } == true
            Self.count(asset, status: status, isRecent: isRecent, into: &counts)
            totalBytes = Self.addBytes(totalBytes, asset.byteCount)
            if status != .backedUp {
                newBytes = Self.addBytes(newBytes, asset.byteCount)
            }
            guard Self.matches(asset, status: status, isRecent: isRecent, filter: query.filter) else { continue }
            guard search.isEmpty || asset.resources.contains(where: {
                $0.filename.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }) else { continue }
            filtered.append(asset)
            if status != .backedUp {
                visibleNewCount += 1
                visibleNewBytes = Self.addBytes(visibleNewBytes, asset.byteCount)
            }
        }

        try Task.checkCancellation()
        var comparisons = 0
        try filtered.sort { left, right in
            comparisons += 1
            if comparisons.isMultiple(of: 1_024) { try Task.checkCancellation() }
            switch (left.createdAt, right.createdAt) {
            case let (leftDate?, rightDate?) where leftDate != rightDate:
                return query.sort == .newestFirst ? leftDate > rightDate : leftDate < rightDate
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                return left.id < right.id
            }
        }

        try Task.checkCancellation()
        let grouping = Self.resolvedGrouping(query.grouping, count: filtered.count)
        let sections = try Self.sections(for: filtered, grouping: grouping, calendar: calendar)
        return CatalogSnapshot(
            sections: sections,
            counts: counts,
            orderedIDs: filtered.map(\.id),
            totalCount: assets.count,
            newCount: counts[.notBackedUp, default: 0],
            newBytes: newBytes,
            totalBytes: totalBytes,
            grouping: grouping,
            visibleNewCount: visibleNewCount,
            visibleNewBytes: visibleNewBytes
        )
    }

    private static func count(
        _ asset: MediaAsset,
        status: BackupStatus,
        isRecent: Bool,
        into counts: inout [LibraryFilter: Int]
    ) {
        counts[.all, default: 0] += 1
        if asset.kind.isStillImage { counts[.photos, default: 0] += 1 }
        switch asset.kind {
        case .video: counts[.videos, default: 0] += 1
        case .livePhoto: counts[.livePhotos, default: 0] += 1
        case .raw: counts[.raw, default: 0] += 1
        case .photo, .other: break
        }
        counts[status == .backedUp ? .backedUp : .notBackedUp, default: 0] += 1
        if isRecent { counts[.recentlyBackedUp, default: 0] += 1 }
    }

    private static func matches(
        _ asset: MediaAsset,
        status: BackupStatus,
        isRecent: Bool,
        filter: LibraryFilter
    ) -> Bool {
        switch filter {
        case .all: true
        case .photos: asset.kind.isStillImage
        case .videos: asset.kind == .video
        case .livePhotos: asset.kind == .livePhoto
        case .raw: asset.kind == .raw
        case .notBackedUp: status != .backedUp
        case .backedUp: status == .backedUp
        case .recentlyBackedUp: isRecent
        }
    }

    private static func resolvedGrouping(_ grouping: CatalogGrouping, count: Int) -> CatalogGrouping {
        guard grouping == .automatic else { return grouping }
        if count > 50_000 { return .year }
        if count > 2_000 { return .month }
        return .day
    }

    private static func sections(
        for assets: [MediaAsset],
        grouping: CatalogGrouping,
        calendar: Calendar
    ) throws -> [MediaSection] {
        let component: Calendar.Component
        switch grouping {
        case .automatic, .day: component = .day
        case .month: component = .month
        case .year: component = .year
        }
        var dates: [Date?] = []
        var groups: [[MediaAsset]] = []
        var interval: DateInterval?
        // Sorted dates form contiguous calendar buckets. Append directly without a second sort.
        for (index, asset) in assets.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let bucket: Date?
            if let date = asset.createdAt {
                // DateInterval.contains includes its end; calendar buckets must be half-open
                // so midnight belongs to the following day in either sort direction.
                if let current = interval, date >= current.start, date < current.end {
                    bucket = current.start
                } else {
                    interval = calendar.dateInterval(of: component, for: date)
                    bucket = interval?.start
                }
            } else {
                bucket = nil
            }
            if !groups.isEmpty, dates.last == .some(bucket) {
                groups[groups.count - 1].append(asset)
            } else {
                dates.append(bucket)
                groups.append([asset])
            }
        }
        try Task.checkCancellation()
        return zip(dates, groups).map { date, assets in
            let key = date.map { String($0.timeIntervalSince1970) } ?? "unknown"
            return MediaSection(id: "\(grouping.rawValue):\(key)", date: date, assets: assets, grouping: grouping)
        }
    }

    private static func addBytes(_ left: Int64, _ right: Int64) -> Int64 {
        let result = left.addingReportingOverflow(right)
        return result.overflow ? Int64.max : result.partialValue
    }
}
