import BackupEngine
import BackupPersistence
import Foundation
import GRDB
import MediaModels
import Testing

@Suite("Portable folder recovery")
struct BackupFolderRecoveryTests {
    @Test func emptyDatabaseAndCopiedFolderRecoverThenReconnectWithoutDownloads() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let old = HistoryFixture()
        let original = directory.url.appendingPathComponent("Originals")
        let result = try await seed(directory: directory, fixture: old, destination: original)
        let copy = directory.url.appendingPathComponent("Copied")
        try FileManager.default.copyItem(at: original, to: copy)
        let fresh = try await BackupStore(databaseURL: directory.url.appendingPathComponent("Fresh.sqlite"))
        let current = HistoryFixture(prefix: "new")
        let scan = try BackupRecoveryIndex.scan(destination: copy)
        #expect(scan.entries.count == 2)
        #expect(try await fresh.importRecovery(scan, destinationID: current.destinationID) == 2)
        #expect(try await fresh.importRecovery(scan, destinationID: current.destinationID) == 0)
        let sessions = try await fresh.recentSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].status == .recovered)
        #expect(sessions[0].completedAssets == 1)
        #expect(sessions[0].transferredBytes == 0)
        #expect(sessions[0].startedAt > result.records[0].verifiedAt)
        let records = try await rebased(current, store: fresh)
        let repeated = try await BackupEngine(previousRecords: records).run(
            assets: current.assets, sessionID: current.sourceSessionID, destination: copy
        ) { _, _ in
            Issue.record("Recovered originals must not download again")
            throw BackupEngineError.invalidSelection
        }
        #expect(repeated.snapshot.phase == .completed)
        #expect(repeated.snapshot.transferredBytes == 0)
        #expect(repeated.snapshot.completedAssets == 1)
        #expect(repeated.records.allSatisfy { $0.destinationIdentity == scan.destinationIdentity })
        let reopened = try await BackupStore(databaseURL: directory.url.appendingPathComponent("Fresh.sqlite"))
        #expect(try await current.candidates(reopened).count == 2)
    }

    @Test(arguments: [false, true]) func missingOrChangedCompanionStaysIncompleteAndOnlyMissingBytesTransfer(changed: Bool) async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let old = HistoryFixture()
        let root = directory.url.appendingPathComponent("Originals")
        let result = try await seed(directory: directory, fixture: old, destination: root)
        let motion = result.records[1]
        let url = root.appendingPathComponent(motion.relativePath)
        if changed { try Data(repeating: 9, count: 5).write(to: url) } else { try FileManager.default.removeItem(at: url) }
        let fresh = try await BackupStore(databaseURL: directory.url.appendingPathComponent("Fresh.sqlite"))
        let current = HistoryFixture(prefix: "new")
        let scan = try BackupRecoveryIndex.scan(destination: root)
        #expect(scan.entries.count == 1)
        #expect(scan.unavailable == 1)
        #expect(try await fresh.importRecovery(scan, destinationID: current.destinationID) == 1)
        let sessions = try await fresh.recentSessions(filter: BackupHistoryFilter(outcome: .unfinished))
        #expect(sessions.count == 1)
        #expect(sessions.first?.completedAssets == 0)
        #expect(try await fresh.recentSessions(filter: BackupHistoryFilter(outcome: .completed)).isEmpty)
        let records = try await rebased(current, store: fresh)
        let repeated = try await BackupEngine(previousRecords: records).run(
            assets: current.assets, sessionID: current.sourceSessionID, destination: root
        ) { request, _ in
            #expect(request.resource.filename.hasSuffix("MOV"))
            return try download(request)
        }
        #expect(repeated.snapshot.completedAssets == 1)
        #expect(repeated.snapshot.transferredBytes == 5)
        if changed { #expect(try Data(contentsOf: url) == Data(repeating: 9, count: 5)) }
    }

    @Test func twoPhonesWithRepeatedNamesStaySeparate() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let root = directory.url.appendingPathComponent("Originals")
        let first = HistoryFixture(deviceValue: "one")
        let second = HistoryFixture(deviceValue: "two")
        _ = try await seed(directory: directory, fixture: first, destination: root)
        _ = try await seed(directory: directory, fixture: second, destination: root)
        let fresh = try await BackupStore(databaseURL: directory.url.appendingPathComponent("Fresh.sqlite"))
        let destinationID = UUID()
        #expect(try await fresh.importRecovery(BackupRecoveryIndex.scan(destination: root), destinationID: destinationID) == 4)
        #expect(try await fresh.historyDevices().count == 2)
        for name in ["one", "two"] {
            let current = HistoryFixture(deviceValue: name, destinationID: destinationID, prefix: "reconnected")
            let candidates = try await current.candidates(fresh)
            #expect(candidates.count == 2)
            #expect(candidates.allSatisfy { $0.record.deviceID == current.device.id })
        }
    }

    @Test func olderKnownBackupCanBePreparedOnlyAtItsActualRoot() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let root = directory.url.appendingPathComponent("Originals")
        let result = try await seed(directory: directory, fixture: HistoryFixture(), destination: root, portable: false)
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let entries = try await store.recoveryEntries(destinationIdentity: result.records[0].destinationIdentity)
        #expect(entries.count == 2)
        let copy = directory.url.appendingPathComponent("Copied")
        try FileManager.default.copyItem(at: root, to: copy)
        #expect(try BackupRecoveryIndex.prepare(entries: entries, destination: copy) == 0)
        #expect(try BackupRecoveryIndex.scan(destination: copy).entries.isEmpty)
        #expect(try BackupRecoveryIndex.prepare(entries: entries, destination: root) == 2)
        #expect(try BackupRecoveryIndex.scan(destination: root).entries.count == 2)
    }

    @Test func transactionFailureRollsBackEveryRecoveredRow() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let root = directory.url.appendingPathComponent("Originals")
        _ = try await seed(directory: directory, fixture: HistoryFixture(), destination: root)
        let url = directory.url.appendingPathComponent("Fresh.sqlite")
        let fresh = try await BackupStore(databaseURL: url)
        let database = try DatabaseQueue(path: url.path)
        try await database.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_recovery BEFORE INSERT ON backup_record BEGIN SELECT RAISE(ABORT, 'test'); END;")
        }
        let scan = try BackupRecoveryIndex.scan(destination: root)
        await #expect(throws: (any Error).self) { try await fresh.importRecovery(scan, destinationID: UUID()) }
        #expect(try await fresh.recentSessions().isEmpty)
        #expect(try await fresh.historyDevices().isEmpty)
    }

    @Test func unpublishedIntentAndInvalidReceiptNeverClaimSavedMedia() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let root = directory.url.appendingPathComponent("Originals")
        let result = try await seed(directory: directory, fixture: HistoryFixture(), destination: root)
        for record in result.records { try FileManager.default.removeItem(at: root.appendingPathComponent(record.relativePath)) }
        let index = root.appendingPathComponent(BackupRecoveryIndex.directoryName)
        try Data("{}".utf8).write(to: index.appendingPathComponent("invalid.json"))
        let scan = try BackupRecoveryIndex.scan(destination: root)
        #expect(scan.entries.isEmpty)
        #expect(scan.unavailable == 2)
        #expect(scan.invalid == 1)
    }

    @Test(arguments: [false, true]) func linkedMediaIsNeverRecovered(hardLink: Bool) async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let root = directory.url.appendingPathComponent("Originals")
        let result = try await seed(directory: directory, fixture: HistoryFixture(), destination: root)
        let url = root.appendingPathComponent(result.records[0].relativePath)
        let outside = directory.url.appendingPathComponent("outside")
        if hardLink { try FileManager.default.linkItem(at: url, to: outside) } else {
            try FileManager.default.moveItem(at: url, to: outside)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
        }
        #expect(try BackupRecoveryIndex.scan(destination: root).entries.count == 1)
        #expect(try Data(contentsOf: outside) == Data(repeating: 1, count: 3))
    }
}

extension BackupFolderRecoveryTests {
    func seed(directory: HistoryDirectory, fixture: HistoryFixture, destination: URL, portable: Bool = true) async throws -> BackupResult {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let id = try await fixture.begin(store)
        let result = try await BackupEngine().run(
            assets: fixture.assets, sessionID: fixture.sourceSessionID, destination: destination,
            onPublication: { intent in
                if portable {
                    let entry = try await store.recoveryEntry(sessionID: id, record: intent.verifiedRecord)
                    try BackupRecoveryIndex.write(entry, destination: destination)
                }
            }, onVerified: { try await store.recordVerified(sessionID: id, record: $0) }, download: { request, _ in try download(request) }
        )
        #expect(result.snapshot.phase == .completed)
        try await store.finishSession(id: id, result: result.snapshot)
        return result
    }

    func rebased(_ fixture: HistoryFixture, store: BackupStore) async throws -> [VerifiedBackupResource] {
        try await fixture.candidates(store).map { candidate in
            let asset = fixture.assets[0]
            let resource = try #require(asset.resources.first { $0.id == candidate.resourceID })
            return try BackupEngine.rebase(candidate.record, asset: asset, resource: resource, sessionID: fixture.sourceSessionID)
        }
    }
}

private func download(_ request: BackupDownloadRequest) throws -> DownloadedOriginal {
    let url = request.directory.appendingPathComponent(request.filename)
    try Data(repeating: 1, count: Int(request.resource.byteCount)).write(to: url)
    return DownloadedOriginal(url: url, expectedByteCount: request.resource.byteCount)
}

extension BackupFolderRecoveryTests {
    @Test func missingMembershipAndEscapingPathsAreRejected() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let root = directory.url.appendingPathComponent("Originals")
        _ = try await seed(directory: directory, fixture: HistoryFixture(), destination: root)
        let entry = try #require(BackupRecoveryIndex.scan(destination: root).entries.first)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        json["components"] = Array((json["components"] as! [[String: Any]]).prefix(1))
        let partial = try JSONDecoder().decode(BackupRecoveryEntry.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: (any Error).self) { try partial.validate() }
        json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        var record = try #require(json["record"] as? [String: Any])
        record["relativePath"] = "../outside.heic"
        json["record"] = record
        let escaping = try JSONDecoder().decode(BackupRecoveryEntry.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: (any Error).self) { try escaping.validate() }
    }

    @Test func conflictingValidContentsRemainAmbiguous() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let root = directory.url.appendingPathComponent("Originals")
        _ = try await seed(directory: directory, fixture: HistoryFixture(), destination: root)
        let entry = try #require(BackupRecoveryIndex.scan(destination: root).entries.first)
        let bytes = Data(repeating: 8, count: Int(entry.record.byteCount))
        try bytes.write(to: root.appendingPathComponent("Different.heic"))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        var record = try #require(json["record"] as? [String: Any])
        record["relativePath"] = "Different.heic"
        record["sha256"] = HistoryFixture.digest(bytes)
        json["record"] = record
        let other = try JSONDecoder().decode(BackupRecoveryEntry.self, from: JSONSerialization.data(withJSONObject: json))
        try BackupRecoveryIndex.write(other, destination: root)
        let scan = try BackupRecoveryIndex.scan(destination: root)
        #expect(scan.ambiguous == 2)
        #expect(scan.entries.count == 1)
    }

    @Test func indexSymlinkIsNeverFollowedOrReplaced() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let root = directory.url.appendingPathComponent("Originals")
        _ = try await seed(directory: directory, fixture: HistoryFixture(), destination: root)
        let index = root.appendingPathComponent(BackupRecoveryIndex.directoryName)
        let outside = directory.url.appendingPathComponent("OutsideIndex")
        try FileManager.default.moveItem(at: index, to: outside)
        try FileManager.default.createSymbolicLink(at: index, withDestinationURL: outside)
        #expect(throws: (any Error).self) { try BackupRecoveryIndex.scan(destination: root) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).count == 3)
    }
}
