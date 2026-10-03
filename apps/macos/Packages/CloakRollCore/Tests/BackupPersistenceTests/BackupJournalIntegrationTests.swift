import BackupEngine
import BackupPersistence
import Foundation
import GRDB
import MediaModels
import Testing

@Suite("Publication recovery and persistent incremental evidence")
struct BackupJournalIntegrationTests {
    private enum Interruption: Error { case beforeRename, afterRename }

    private actor Requests {
        var values: [String] = []
        func record(_ value: String) { values.append(value) }
    }

    @Test func publishedOriginalSurvivesInterruptedRecordAndIsReusedOnlyAfterFreshValidation() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let destination = directory.url.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let previous = HistoryFixture()
        var interruptedID: UUID?
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            let id = try await previous.begin(store)
            interruptedID = id
            let result = try await BackupEngine(timeZone: .gmt).run(
                assets: previous.assets, sessionID: previous.sourceSessionID, destination: destination,
                onStaged: { try await store.recordStaging(sessionID: id, intent: $0) },
                onPublication: { try await store.recordPublication(sessionID: id, intent: $0) },
                onVerified: { _ in throw Interruption.afterRename }
            ) { request, _ in
                // The persisted stage must exist before the source may produce any bytes.
                #expect(try await directory.journalCounts().pending == 1)
                let url = request.directory.appendingPathComponent(request.filename)
                try Data(repeating: 1, count: Int(request.resource.byteCount)).write(to: url)
                return DownloadedOriginal(url: url, expectedByteCount: request.resource.byteCount)
            }
            #expect(result.snapshot.phase == .failed && result.snapshot.completedAssets == 0)
            #expect(result.records.count == 1)
            #expect(try await previous.candidates(store).isEmpty)
            // Deliberately leave the running database session unfinished to model process exit.
        }
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        let pending = try #require(try await reopened.pendingJournal(destinationID: previous.destinationID).first)
        let intent = try #require(pending.publication)
        guard case let .published(record) = try await BackupRecovery.inspect(destination: destination, intent: intent) else {
            Issue.record("The exact published file must be recovered after a missing record transaction.")
            return
        }
        try await reopened.reconcilePublication(sessionID: pending.sessionID, intent: intent, record: record)
        let oldSession = try #require(try await reopened.recentSessions().first { $0.id == interruptedID })
        #expect(oldSession.status == .interrupted && oldSession.verifiedResources == 1 && oldSession.completedAssets == 0)
        #expect(try await reopened.pendingJournal(destinationID: previous.destinationID).isEmpty)

        let current = HistoryFixture(destinationID: previous.destinationID, prefix: "current")
        let candidates = try await current.candidates(reopened)
        #expect(candidates.count == 1)
        let records = try candidates.map { candidate in
            let asset = try #require(current.assets.first { $0.id == candidate.assetID })
            let resource = try #require(asset.resources.first { $0.id == candidate.resourceID })
            return try BackupEngine.rebase(candidate.record, asset: asset, resource: resource, sessionID: current.sourceSessionID)
        }
        let verified = try await BackupVerification.validateExisting(
            assets: current.assets, sessionID: current.sourceSessionID, destination: destination, records: records
        )
        #expect(verified.snapshot.verifiedResources == 1 && verified.snapshot.completedAssetIDs.isEmpty)
        let currentID = try await current.begin(reopened)
        let requests = Requests()
        let result = try await BackupEngine(timeZone: .gmt, previousRecords: verified.records).run(
            assets: current.assets, sessionID: current.sourceSessionID, destination: destination,
            onStaged: { try await reopened.recordStaging(sessionID: currentID, intent: $0) },
            onPublication: { try await reopened.recordPublication(sessionID: currentID, intent: $0) },
            onVerified: { try await reopened.recordVerified(sessionID: currentID, record: $0) }
        ) { request, _ in
            await requests.record(request.resource.id)
            let url = request.directory.appendingPathComponent(request.filename)
            try Data(repeating: 1, count: Int(request.resource.byteCount)).write(to: url)
            return DownloadedOriginal(url: url, expectedByteCount: request.resource.byteCount)
        }
        #expect(result.snapshot.phase == .completed && result.snapshot.completedAssets == 1)
        #expect(await requests.values == ["current-motion"])
        try await reopened.finishSession(id: currentID, result: result.snapshot)
        #expect(try await reopened.recentSessions().first { $0.id == interruptedID }?.status == .interrupted)
    }

    @Test func journalBeforeRenameCannotAdoptUnrelatedIdenticalCollisionFile() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let destination = directory.url.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let fixture = HistoryFixture()
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            let id = try await fixture.begin(store)
            let result = try await BackupEngine(timeZone: .gmt).run(
                assets: fixture.assets, sessionID: fixture.sourceSessionID, destination: destination,
                onStaged: { try await store.recordStaging(sessionID: id, intent: $0) },
                onPublication: { intent in
                    try await store.recordPublication(sessionID: id, intent: intent)
                    let final = destination.appendingPathComponent(intent.relativePath)
                    try FileManager.default.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
                    // Equal content and the proposed name are insufficient evidence of publication.
                    try Data(repeating: 1, count: Int(intent.byteCount)).write(to: final, options: .withoutOverwriting)
                    throw Interruption.beforeRename
                },
                onVerified: { try await store.recordVerified(sessionID: id, record: $0) }
            ) { request, _ in
                let url = request.directory.appendingPathComponent(request.filename)
                try Data(repeating: 1, count: Int(request.resource.byteCount)).write(to: url)
                return DownloadedOriginal(url: url, expectedByteCount: request.resource.byteCount)
            }
            #expect(result.snapshot.phase == .failed && result.records.isEmpty)
        }
        let reopened = try await BackupStore(databaseURL: directory.databaseURL)
        let pending = try #require(try await reopened.pendingJournal(destinationID: fixture.destinationID).first)
        let intent = try #require(pending.publication)
        let outcome = try await BackupRecovery.inspect(destination: destination, intent: intent)
        #expect(outcome == .staged || outcome == .unavailable)
        #expect(try await fixture.candidates(reopened).isEmpty)
        #expect(try await reopened.recentSessions().first?.verifiedResources == 0)
        #expect(try Data(contentsOf: destination.appendingPathComponent(intent.relativePath)) == Data(repeating: 1, count: 3))
        #expect(try await reopened.pendingJournal(destinationID: fixture.destinationID).count == 1)
    }
}
