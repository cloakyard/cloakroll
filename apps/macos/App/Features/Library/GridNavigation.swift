import Foundation

/// Grid rows restart at each date section. Preserve the intended column across
/// short rows, while clicks, horizontal movement and layout changes reset it.
enum GridDirection: CaseIterable, Equatable { case left, right, up, down }

struct GridNavigation {
    private var preferredColumn: Int?
    private var lastIndex: Int?
    private var lastColumns = 0
    private var lastRevision = -1
    private var lastSectionCounts: [Int] = []

    mutating func reset() { preferredColumn = nil; lastIndex = nil }

    mutating func target(
        from current: Int?, direction: GridDirection, sectionCounts: [Int], columns: Int, revision: Int
    ) -> Int? {
        let counts = sectionCounts.filter { $0 > 0 }
        let total = counts.reduce(0, +)
        guard total > 0 else { reset(); return nil }
        let columns = max(1, columns)
        if current != lastIndex || columns != lastColumns || revision != lastRevision || counts != lastSectionCounts { reset() }
        lastSectionCounts = counts
        lastColumns = columns
        lastRevision = revision
        guard let current, (0..<total).contains(current) else {
            lastIndex = 0
            return 0
        }
        let target: Int
        if direction == .left || direction == .right {
            preferredColumn = nil
            target = min(total - 1, max(0, current + (direction == .left ? -1 : 1)))
        } else {
            var section = 0
            var start = 0
            while current >= start + counts[section] { start += counts[section]; section += 1 }
            let local = current - start
            let rowStart = (local / columns) * columns
            let column = preferredColumn ?? local % columns
            preferredColumn = column
            if direction == .down {
                if rowStart + columns < counts[section] {
                    target = start + min(counts[section] - 1, rowStart + columns + column)
                } else if section + 1 < counts.count {
                    target = start + counts[section] + min(counts[section + 1] - 1, column)
                } else { target = current }
            } else if rowStart >= columns {
                target = start + rowStart - columns + column
            } else if section > 0 {
                let previousCount = counts[section - 1]
                let previousRow = ((previousCount - 1) / columns) * columns
                target = start - previousCount + min(previousCount - 1, previousRow + column)
            } else { target = current }
        }
        lastIndex = target
        return target
    }
}
