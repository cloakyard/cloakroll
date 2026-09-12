import Foundation
import MediaModels
import UniformTypeIdentifiers

struct SourceMediaClassification {
    let kind: MediaKind
    let isQuickTimeMovie: Bool
}

/// A supplied concrete type takes precedence over a misleading filename. The extension is a
/// fallback for missing or broad types, never evidence that two resources belong together.
struct SourceMediaClassifier {
    private var cache: [String: SourceMediaClassification] = [:]

    mutating func classify(_ record: SourceMediaRecord) -> SourceMediaClassification {
        if record.isRaw { return SourceMediaClassification(kind: .raw, isQuickTimeMovie: false) }
        let identifier = record.uti?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let suffix = (record.filename as NSString).pathExtension.lowercased()
        let key = "\(identifier.utf8.count):\(identifier)\(suffix)"
        if let cached = cache[key] { return cached }
        let result = Self.classify(identifier: identifier, suffix: suffix)
        cache[key] = result
        return result
    }

    private static func classify(identifier: String, suffix: String) -> SourceMediaClassification {
        let generic = ["", UTType.item.identifier, UTType.content.identifier, UTType.data.identifier,
                       UTType.image.identifier, UTType.movie.identifier, UTType.audiovisualContent.identifier]
        let supplied = identifier.isEmpty ? nil : UTType(identifier)
        let fallback = UTType(filenameExtension: suffix)
        let broadFamily = supplied == .image || supplied == .movie || supplied == .audiovisualContent
        let compatibleFallback = !broadFamily || supplied.map { fallback?.conforms(to: $0) == true } == true
        let type = generic.contains(identifier) && compatibleFallback ? fallback ?? supplied : supplied
        let kind: MediaKind
        if type?.conforms(to: .rawImage) == true {
            kind = .raw
        } else if type?.conforms(to: .image) == true {
            kind = .photo
        } else if type?.conforms(to: .movie) == true {
            kind = .video
        } else {
            kind = .other
        }
        return SourceMediaClassification(kind: kind, isQuickTimeMovie: type?.conforms(to: .quickTimeMovie) == true)
    }
}
