import Foundation

enum BackupPathNaming {
    static func folders(createdAt: Date?, timeZone: TimeZone) -> [String] {
        guard let createdAt, createdAt.timeIntervalSinceReferenceDate.isFinite else { return ["Date Unknown"] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month], from: createdAt)
        guard let year = parts.year, (1...9_999).contains(year), let month = parts.month, (1...12).contains(month) else {
            return ["Date Unknown"]
        }
        return [String(format: "%04d", year), String(format: "%02d", month)]
    }

    static func filename(_ original: String, collision: Int = 0, maximumBytes: Int = 255) -> String {
        let scalars = original.precomposedStringWithCanonicalMapping.unicodeScalars.map { scalar -> String in
            if scalar.value < 32 || scalar.value == 127 || ["/", "\\", ":"].contains(String(scalar)) { return "_" }
            return String(scalar)
        }
        var cleaned = scalars.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        if cleaned.isEmpty { cleaned = "Original" }
        let extensionPart = (cleaned as NSString).pathExtension
        let suffix = collision == 0 ? "" : " (\(collision))"
        let fileExtension = extensionPart.isEmpty ? "" : "." + prefix(extensionPart, maximumBytes: 32)
        let stem = extensionPart.isEmpty ? cleaned : (cleaned as NSString).deletingPathExtension
        let budget = max(1, maximumBytes - suffix.utf8.count - fileExtension.utf8.count)
        let shortStem = prefix(stem, maximumBytes: budget)
        return (shortStem.isEmpty ? "Original" : shortStem) + suffix + fileExtension
    }

    private static func prefix(_ value: String, maximumBytes: Int) -> String {
        var result = ""
        var bytes = 0
        for character in value {
            let count = character.utf8.count
            guard bytes + count <= maximumBytes else { break }
            result.append(character)
            bytes += count
        }
        return result
    }
}
