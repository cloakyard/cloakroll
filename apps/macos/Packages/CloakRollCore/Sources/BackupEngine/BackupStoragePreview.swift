import Foundation
import MediaModels

public struct BackupStoragePreview: Sendable, Equatable {
    public let itemCount: Int
    public let originalCount: Int
    public let reusableOriginals: Int
    public let additionalBytes: Int64
    public let availableBytes: Int64?
    public let unknownSizeCount: Int

    public var hasKnownShortfall: Bool { availableBytes.map { $0 < additionalBytes } ?? false }
    public var canStart: Bool { itemCount > 0 && originalCount > 0 && unknownSizeCount == 0 && !hasKnownShortfall }

    public static func prepare(
        assets: [MediaAsset], sessionID: UUID, destination: URL, records: [VerifiedBackupResource]
    ) async throws -> Self {
        try await prepare(assets: assets, sessionID: sessionID, destination: destination, records: records, capacity: .live)
    }

    static func prepare(
        assets: [MediaAsset], sessionID: UUID, destination: URL, records: [VerifiedBackupResource], capacity: BackupCapacity
    ) async throws -> Self {
        let verified = try await BackupVerification.validateExisting(
            assets: assets, sessionID: sessionID, destination: destination, records: records
        )
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let resources = assets.flatMap(\.resources)
            let reusable = Set(verified.records.map(\.resourceID))
            var bytes: Int64 = 0
            for resource in resources where !reusable.contains(resource.id) {
                try Task.checkCancellation()
                let sum = bytes.addingReportingOverflow(resource.byteCount)
                guard !sum.overflow else { throw BackupEngineError.invalidResourceSize }
                bytes = sum.partialValue
            }
            let capacity = try? capacity.availableBytes(destination)
            return Self(itemCount: assets.count, originalCount: resources.count, reusableOriginals: reusable.count,
                        additionalBytes: bytes, availableBytes: capacity.flatMap { $0 >= 0 ? $0 : nil },
                        unknownSizeCount: resources.filter { $0.byteCount <= 0 }.count)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
