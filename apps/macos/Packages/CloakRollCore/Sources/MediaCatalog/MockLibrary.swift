import Foundation
import MediaModels

/// Explicit sample metadata for previews and tests. It contains no source handles or backup records.
public struct MockLibrary: Equatable, Sendable {
    public let device: ConnectedDevice
    public let assets: [MediaAsset]
    public let statuses: [String: BackupStatus]
    public let backupDates: [String: Date]

    public static func make(count: Int, now: Date = Date(timeIntervalSince1970: 1_789_214_400)) -> MockLibrary {
        let device = ConnectedDevice(id: "sample-device", displayName: "Sample iPhone")
        var assets: [MediaAsset] = []
        var statuses: [String: BackupStatus] = [:]
        var backupDates: [String: Date] = [:]
        assets.reserveCapacity(max(0, count))
        for index in 0..<max(0, count) {
            let asset = makeAsset(index: index, deviceID: device.id, now: now)
            assets.append(asset)
            let status: BackupStatus = index % 4 == 0 ? .notBackedUp : .backedUp
            statuses[asset.id] = status
            if status == .backedUp {
                backupDates[asset.id] = now.addingTimeInterval(-Double(index % 16) * 86_400)
            }
        }
        return MockLibrary(device: device, assets: assets, statuses: statuses, backupDates: backupDates)
    }

    private static func makeAsset(index: Int, deviceID: String, now: Date) -> MediaAsset {
        let id = "fixture-\(index)"
        let stem = String(format: "IMG_%04d", index + 1)
        let kind = mediaKind(at: index)
        let baseBytes = Int64(2_400_000 + (index % 31) * 137_000)
        let resources: [MediaResource]
        switch kind {
        case .livePhoto:
            resources = [
                MediaResource(id: "\(id)-image", filename: "\(stem).HEIC", byteCount: baseBytes),
                MediaResource(id: "\(id)-motion", filename: "\(stem).MOV", byteCount: 3_200_000)
            ]
        case .raw:
            resources = [
                MediaResource(id: "\(id)-raw", filename: "\(stem).DNG", byteCount: baseBytes * 7),
                MediaResource(id: "\(id)-image", filename: "\(stem).JPG", byteCount: baseBytes)
            ]
        case .video:
            resources = [MediaResource(id: "\(id)-video", filename: "\(stem).MOV", byteCount: baseBytes * 12)]
        case .photo:
            resources = [MediaResource(id: "\(id)-image", filename: "\(stem).HEIC", byteCount: baseBytes)]
        case .other:
            resources = [MediaResource(id: "\(id)-image", filename: "\(stem).GIF", byteCount: baseBytes / 2)]
        }
        let date = index > 0 && index % 97 == 0
            ? nil
            : now.addingTimeInterval(-Double(index / 8) * 86_400 - Double(index % 8) * 1_200)
        return MediaAsset(
            id: id,
            deviceID: deviceID,
            resources: resources,
            kind: kind,
            createdAt: date,
            duration: kind == .video ? Double(12 + index % 180) : nil,
            pixelWidth: kind == .video ? 3_840 : 4_032,
            pixelHeight: kind == .video ? 2_160 : 3_024
        )
    }

    private static func mediaKind(at index: Int) -> MediaKind {
        if index > 0, index % 53 == 0 { return .other }
        switch index % 12 {
        case 2, 10: return .livePhoto
        case 4, 9: return .video
        case 7: return .raw
        default: return .photo
        }
    }
}
