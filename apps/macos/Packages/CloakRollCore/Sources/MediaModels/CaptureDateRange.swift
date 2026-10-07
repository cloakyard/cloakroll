import Foundation

/// Whole capture days in the calendar used when the user applies the filter.
/// The exclusive end respects daylight-saving changes and calendar boundaries.
public struct CaptureDateRange: Equatable, Sendable {
    public let from: Date
    public let through: Date
    public let end: Date

    public init?(from: Date, through: Date, calendar: Calendar = .current) {
        guard from.timeIntervalSinceReferenceDate.isFinite,
              through.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let firstDay = calendar.startOfDay(for: from)
        let lastDay = calendar.startOfDay(for: through)
        guard firstDay <= lastDay,
              let end = calendar.date(byAdding: .day, value: 1, to: lastDay),
              end > lastDay else { return nil }
        self.from = firstDay
        self.through = lastDay
        self.end = end
    }

    public func contains(_ date: Date?) -> Bool {
        guard let date else { return false }
        return date >= from && date < end
    }
}
