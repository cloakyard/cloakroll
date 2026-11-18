import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Backup storage preview")
struct BackupStoragePreviewTests {
    @Test func partialCompanionReuseCountsOnlyFreshlyVerifiedBytes() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = backupAsset(resources: [MediaResource(id: "photo", filename: "IMG.HEIC", byteCount: 3),
                                           MediaResource(id: "motion", filename: "IMG.MOV", byteCount: 3)])
        let session = UUID()
        let result = try await BackupEngine().run(assets: [asset], sessionID: session, destination: root) { request, _ in
            try writeOriginal(request, data: Data([1, 2, 3]))
        }
        let record = try #require(result.records.first)
        let all = try await BackupStoragePreview.prepare(assets: [asset], sessionID: session, destination: root,
                                                         records: result.records, capacity: .init(availableBytes: { _ in 0 }))
        #expect(all.additionalBytes == 0 && all.reusableOriginals == 2 && all.canStart)
        try FileManager.default.removeItem(at: root.appendingPathComponent(record.relativePath))
        let partial = try await BackupStoragePreview.prepare(assets: [asset], sessionID: session, destination: root,
                                                             records: result.records, capacity: .init(availableBytes: { _ in 2 }))
        #expect(partial.additionalBytes == 3 && partial.reusableOriginals == 1)
        #expect(partial.originalCount == 2 && partial.hasKnownShortfall && !partial.canStart)
        let enough = try await BackupStoragePreview.prepare(assets: [asset], sessionID: session, destination: root,
                                                            records: result.records, capacity: .init(availableBytes: { _ in 3 }))
        #expect(enough.canStart)
    }

    @Test func unknownCapacityIsAdvisoryButUnknownOriginalSizeBlocksStart() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = backupAsset(resources: [.init(id: "known", filename: "photo.heic", byteCount: 7)])
        let summary = try await BackupStoragePreview.prepare(assets: [valid], sessionID: UUID(), destination: root,
                                                             records: [], capacity: .init(availableBytes: { _ in nil }))
        #expect(summary.availableBytes == nil && summary.additionalBytes == 7 && summary.canStart)
        let unknown = backupAsset(resources: [.init(id: "unknown", filename: "photo.heic", byteCount: 0)])
        let blocked = try await BackupStoragePreview.prepare(assets: [unknown], sessionID: UUID(), destination: root,
                                                             records: [], capacity: .init(availableBytes: { _ in 1_000 }))
        #expect(blocked.unknownSizeCount == 1 && !blocked.canStart)
    }

    @Test func overflowingSelectionNeverWrapsToEnoughSpace() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = backupAsset(resources: [.init(id: "a", filename: "one.mov", byteCount: .max),
                                           .init(id: "b", filename: "two.mov", byteCount: 1)])
        await #expect(throws: BackupEngineError.invalidResourceSize) {
            try await BackupStoragePreview.prepare(assets: [asset], sessionID: UUID(), destination: root,
                                                    records: [], capacity: .init(availableBytes: { _ in .max }))
        }
    }
}
