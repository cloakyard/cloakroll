import Foundation
import ImageCaptureCore
import MediaModels

/// Reads only metadata already supplied by enumeration. There is no per-file metadata request.
@MainActor
enum CaptureRecordNormalizer {
    static func record(
        for file: ICCameraFile, id: String, deviceID: String,
        sidecarIDs: [String], pairedRawID: String?
    ) -> SourceMediaRecord {
        SourceMediaRecord(
            id: id, deviceID: deviceID,
            filename: present(file.name) ?? present(file.originalFilename) ?? "Unnamed resource",
            originalFilename: present(file.originalFilename), contextPath: context(for: file).names,
            uti: present(file.uti), isRaw: file.isRaw, byteCount: Int64(file.fileSize),
            createdAt: file.creationDate, modifiedAt: file.modificationDate,
            pixelWidth: file.width, pixelHeight: file.height, duration: file.duration,
            originatingAssetID: present(file.originatingAssetID), groupUUID: present(file.groupUUID),
            relatedUUID: present(file.relatedUUID), burstUUID: present(file.burstUUID),
            sidecarIDs: sidecarIDs, pairedRawID: pairedRawID
        )
    }

    static func context(for item: ICCameraItem) -> (names: [String], ancestors: Set<ObjectIdentifier>) {
        var names: [String] = []
        var ancestors: Set<ObjectIdentifier> = []
        var folder = item.parentFolder
        while let current = folder, ancestors.insert(ObjectIdentifier(current)).inserted {
            if let name = present(current.name) { names.append(name) }
            folder = current.parentFolder
        }
        return (names.reversed(), ancestors)
    }

    private static func present(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // Preserve exact Unicode and whitespace in real filenames; only absence is normalized.
        return value
    }
}
