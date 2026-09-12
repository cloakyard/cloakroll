import BackupEngine
import BackupPersistence
import Foundation
import GRDB
import MediaModels
import Testing

@Suite("Original files and persistent evidence")
struct BackupHistoryIntegrationTests {
    @Test func reopenedCandidatesRequireFreshLocalValidationAndPreserveChangedFiles() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let destination = directory.url.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let previous = HistoryFixture()
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            let id = try await previous.begin(store)
            let result = try await BackupEngine(timeZone: .gmt).run(
                assets: previous.assets, sessionID: previous.sourceSessionID, destination: destination,
                onVerified: { try await store.recordVerified(sessionID: id, record: $0) }
            ) { request, _ in
                let url = request.directory.appendingPathComponent(request.filename)
                try Data(repeating: 1, count: Int(request.resource.byteCount)).write(to: url)
                return DownloadedOriginal(url: url, expectedByteCount: request.resource.byteCount)
            }
            #expect(result.snapshot.phase == .completed)
            try await store.finishSession(id: id, result: result.snapshot)
        }
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        let current = HistoryFixture(destinationID: previous.destinationID, prefix: "current")
        let candidates = try await current.candidates(reopened)
        #expect(candidates.count == 2)
        let records = try candidates.map { candidate in
            let asset = try #require(current.assets.first { $0.id == candidate.assetID })
            let resource = try #require(asset.resources.first { $0.id == candidate.resourceID })
            return try BackupEngine.rebase(candidate.record, asset: asset, resource: resource, sessionID: current.sourceSessionID)
        }
        let valid = try await BackupVerification.validateExisting(
            assets: current.assets, sessionID: current.sourceSessionID, destination: destination, records: records
        )
        #expect(valid.snapshot.completedAssetIDs == ["current-asset"])
        #expect(valid.snapshot.verifiedBytes == 8)
        let changed = try #require(records.first)
        let changedURL = destination.appendingPathComponent(changed.relativePath)
        let replacement = Data(repeating: 2, count: Int(changed.byteCount))
        try replacement.write(to: changedURL)
        // Database correspondence alone still yields candidates. File verification withdraws asset completion.
        #expect(try await current.candidates(reopened).count == 2)
        let invalid = try await BackupVerification.validateExisting(
            assets: current.assets, sessionID: current.sourceSessionID, destination: destination, records: records
        )
        #expect(invalid.snapshot.completedAssetIDs.isEmpty)
        #expect(invalid.snapshot.verifiedResources == 1)
        #expect(try Data(contentsOf: changedURL) == replacement)
    }

    @Test func finalSessionWriteFailureLeavesVerifiedComponentsWithoutClaimingCompletion() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        try await store.recordVerified(sessionID: id, record: fixture.record(0))
        try await store.recordVerified(sessionID: id, record: fixture.record(1))
        try await directory.database().write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_finish BEFORE UPDATE OF status ON backup_session
                BEGIN SELECT RAISE(ABORT, 'simulated final history failure'); END;
                """
            )
        }
        await #expect(throws: BackupStoreError.unavailable) {
            try await store.finishSession(id: id, result: BackupSnapshot(
                phase: .completed, completedAssets: 1, verifiedResources: 2, verifiedBytes: 8
            ))
        }
        #expect(try await store.recentSessions().first?.status == .running)
        #expect(try await fixture.candidates(store).count == 2)
    }
}
