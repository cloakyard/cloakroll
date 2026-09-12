import Foundation
import MediaModels

extension LibraryFilter {
    var title: String {
        switch self {
        case .all: "All Photos"
        case .photos: "Photos"
        case .videos: "Videos"
        case .livePhotos: "Live Photos"
        case .raw: "RAW"
        case .notBackedUp: "Not Backed Up"
        case .backedUp: "Backed Up"
        case .recentlyBackedUp: "Recently Backed Up"
        }
    }

    var symbol: String {
        switch self {
        case .all: "photo.on.rectangle"
        case .photos: "photo"
        case .videos: "video"
        case .livePhotos: "livephoto"
        case .raw: "camera.aperture"
        case .notBackedUp: "circle.dashed"
        case .backedUp: "checkmark.circle"
        case .recentlyBackedUp: "clock.arrow.circlepath"
        }
    }
}

extension MediaKind {
    var title: String {
        switch self {
        case .photo: "Photo"
        case .video: "Video"
        case .livePhoto: "Live Photo"
        case .raw: "RAW"
        case .other: "Media"
        }
    }
}

extension BackupStatus {
    var title: String {
        switch self {
        case .notBackedUp: "Not backed up"
        case .backedUp: "Backed up"
        case .uncertain: "Needs checking"
        case .failed: "Backup incomplete"
        }
    }
}

enum Format {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "–:––" }
        let total = Int(min(seconds, 359_999))
        return total >= 3_600
            ? String(format: "%d:%02d:%02d", total / 3_600, (total / 60) % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
