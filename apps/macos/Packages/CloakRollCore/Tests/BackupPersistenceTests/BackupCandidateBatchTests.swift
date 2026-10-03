import BackupEngine
import Foundation
import GRDB
import MediaModels
import Testing
@testable import BackupPersistence

@Suite("Bounded candidate lookup")
struct BackupCandidateBatchTests {
    @Test(arguments: [0, 1, 63, 64, 65])
    func emptySingleAndBatchBoundariesReturnAllRequestedOriginals(count: Int) async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixtures = try await seed(store, count: count)
        let identity = try combinedIdentity(fixtures)
        let destinationID = fixtures.first?.destinationID ?? UUID()
        let result = try await store.candidates(deviceKey: identity.deviceKey, destinationID: destinationID, identity: identity)
        #expect(result.count == count)
        #expect(result.map(\.assetID) == fixtures.map { $0.assets[0].id }.sorted())
        #expect(result.allSatisfy { $0.resourceID.hasSuffix("-still") })
    }

    @Test func duplicateCurrentCanonicalsOnOppositeBatchEndsAreRejectedGlobally() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixtures = try await seed(store, count: 65)
        let original = try combinedIdentity(fixtures)
        var assets = original.assets
        let order = Array(assets.keys)
        let firstID = try #require(order.first)
        let lastID = try #require(order.last)
        let first = try #require(assets[firstID])
        let last = try #require(assets[lastID])
        assets[last.assetID] = BackupAssetIdentity(
            assetID: last.assetID, canonical: first.canonical, digest: first.digest,
            isReusableAcrossConnections: true, resources: last.resources
        )
        #expect(Array(assets.keys) == order)
        let ambiguous = BackupCatalogIdentity(deviceKey: original.deviceKey, sessionID: original.sessionID, assets: assets)
        let result = try await store.candidates(
            deviceKey: original.deviceKey, destinationID: fixtures[0].destinationID, identity: ambiguous
        )
        #expect(result.count == 63)
        #expect(!result.contains { $0.assetID == first.assetID || $0.assetID == last.assetID })
    }

    @Test(arguments: ["hash", "root"])
    func anOldConflictRemainsAmbiguousAcrossManyNewerIdenticalCopies(conflict: String) async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let old = HistoryFixture()
        let oldID = try await old.begin(store)
        try await store.recordVerified(sessionID: oldID, record: old.record(byte: conflict == "hash" ? 2 : 1))
        if conflict == "root" {
            try await directory.database().write {
                try $0.execute(sql: "UPDATE backup_record SET destination_identity = ? WHERE session_id = ?",
                               arguments: ["different-root", oldID.uuidString])
            }
        }
        for index in 0..<70 {
            let fixture = HistoryFixture(destinationID: old.destinationID, prefix: "copy-\(index)")
            let id = try await fixture.begin(store)
            try await store.recordVerified(sessionID: id, record: fixture.record(
                path: "2026/09/copy-\(index).HEIC", verifiedAt: Date(timeIntervalSince1970: Double(300 + index))
            ))
        }
        #expect(try await old.candidates(store).isEmpty)
    }

    @Test(arguments: [true, false])
    func nonreusableEvidenceUsesItsExactSessionAndIgnoresOtherSessionConflicts(persistent: Bool) async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let same = HistoryFixture(persistent: persistent)
        let firstID = try await same.begin(store, reusable: false)
        try await store.recordVerified(sessionID: firstID, record: same.record())
        let other = HistoryFixture(destinationID: same.destinationID, prefix: "other", persistent: persistent)
        let secondID = try await other.begin(store, reusable: false)
        try await store.recordVerified(sessionID: secondID, record: other.record(byte: 2))
        #expect(try await same.candidates(store, reusable: false).first?.record == same.record())
        let reconnected = HistoryFixture(destinationID: same.destinationID, prefix: "reconnected", persistent: persistent)
        #expect(try await reconnected.candidates(store, reusable: false).isEmpty)
    }

    @Test func oneReconnectedIdentityFindsItsRecordAmongUnrelatedHistory() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixtures = try await seed(store, count: 65)
        let prior = fixtures[64]
        let date = try #require(prior.assets[0].createdAt)
        let current = HistoryFixture(destinationID: prior.destinationID, prefix: "reconnected", date: date)
        let result = try await current.candidates(store)
        #expect(result.count == 1)
        #expect(result.first?.assetID == "reconnected-asset")
        #expect(result.first?.resourceID == "reconnected-still")
        #expect(try result.first?.record == prior.record())
    }

    @Test func newestTimestampThenHighestRowIDWinsForIdenticalContent() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let destinationID = UUID()
        let dates: [TimeInterval] = [300, 100, 300]
        for (index, date) in dates.enumerated() {
            let fixture = HistoryFixture(destinationID: destinationID, prefix: "copy-\(index)")
            let id = try await fixture.begin(store)
            try await store.recordVerified(sessionID: id, record: fixture.record(
                path: "2026/09/copy-\(index).HEIC", verifiedAt: Date(timeIntervalSince1970: date)
            ))
        }
        let current = HistoryFixture(destinationID: destinationID, prefix: "current")
        #expect(try await current.candidates(store).first?.record.relativePath == "2026/09/copy-2.HEIC")
    }

    @Test func damagedOlderMatchingRecordIsNotHiddenByANewerValidOne() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let old = HistoryFixture()
        let firstID = try await old.begin(store)
        try await store.recordVerified(sessionID: firstID, record: old.record())
        let newer = HistoryFixture(destinationID: old.destinationID, prefix: "newer")
        let secondID = try await newer.begin(store)
        try await store.recordVerified(sessionID: secondID, record: newer.record(verifiedAt: Date(timeIntervalSince1970: 300)))
        try await directory.database().write {
            try $0.execute(sql: "UPDATE backup_record SET source_session_id = ? WHERE session_id = ?",
                           arguments: ["malformed-session", firstID.uuidString])
        }
        await #expect(throws: BackupStoreError.invalidRecord) { _ = try await newer.candidates(store) }
    }

    @Test func digestSeekRetainsSwiftCanonicalUnicodeEquality() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let original = try fixture.identity()
        let asset = try #require(original.assets.values.first)
        let canonical = asset.canonical + " caf\u{00e9}"
        let resources = asset.resources.mapValues { resource in
            let canonical = resource.canonical + " r\u{00e9}source"
            return BackupResourceIdentity(
                resourceID: resource.resourceID, canonical: canonical, digest: HistoryFixture.digest(Data(canonical.utf8)),
                isReusableAcrossConnections: true
            )
        }
        let storedAsset = BackupAssetIdentity(
            assetID: asset.assetID, canonical: canonical, digest: HistoryFixture.digest(Data(canonical.utf8)),
            isReusableAcrossConnections: true, resources: resources
        )
        let stored = BackupCatalogIdentity(deviceKey: original.deviceKey, sessionID: original.sessionID,
                                          assets: [asset.assetID: storedAsset])
        let id = try await store.beginSession(
            device: fixture.device, destinationID: fixture.destinationID, sourceSessionID: fixture.sourceSessionID,
            assets: fixture.assets, identity: stored
        )
        try await store.recordVerified(sessionID: id, record: fixture.record())
        let resource = try #require(resources["old-still"])
        // Stored identities pass normal digest validation. Only the constructed current identity
        // uses equivalent NFD strings with the stored NFC digests to exercise comparison parity.
        for difference in ["none", "asset", "resource"] {
            let currentResource = BackupResourceIdentity(
                resourceID: resource.resourceID,
                canonical: resource.canonical.decomposedStringWithCanonicalMapping + (difference == "resource" ? "different" : ""),
                digest: resource.digest, isReusableAcrossConnections: true
            )
            let currentAsset = BackupAssetIdentity(
                assetID: asset.assetID,
                canonical: storedAsset.canonical.decomposedStringWithCanonicalMapping + (difference == "asset" ? "different" : ""),
                digest: storedAsset.digest, isReusableAcrossConnections: true, resources: [resource.resourceID: currentResource]
            )
            let current = BackupCatalogIdentity(deviceKey: original.deviceKey, sessionID: UUID(), assets: [asset.assetID: currentAsset])
            let candidates = try await store.candidates(deviceKey: current.deviceKey, destinationID: fixture.destinationID, identity: current)
            #expect(candidates.count == (difference == "none" ? 1 : 0))
        }
    }

    @Test func queryPlanSeeksIndexedIdentityAndResourceRowsWithoutHistorySort() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        _ = try await BackupStore(databaseURL: directory.databaseURL)
        let details = try await directory.database().read { db in
            try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + BackupStoreReading.candidateQuery(batchSize: 1),
                             arguments: ["asset-digest", "resource-digest", "device", "destination"]).map { $0["detail"] as String }
        }
        #expect(details.contains { $0.contains("SEARCH a USING INDEX asset_lookup") })
        #expect(details.contains { $0.contains("SEARCH r USING INDEX resource_lookup") })
        #expect(details.contains { $0.contains("SEARCH b USING INDEX record_destination") })
        #expect(!details.contains { $0.contains("SCAN b") || $0.contains("USE TEMP B-TREE") })
    }

    private func seed(_ store: BackupStore, count: Int) async throws -> [HistoryFixture] {
        let destinationID = UUID()
        var fixtures: [HistoryFixture] = []
        for index in 0..<count {
            let fixture = HistoryFixture(destinationID: destinationID, prefix: "item-\(index)",
                                         date: Date(timeIntervalSince1970: Double(100 + index)))
            let id = try await fixture.begin(store)
            try await store.recordVerified(sessionID: id, record: fixture.record())
            fixtures.append(fixture)
        }
        return fixtures
    }

    private func combinedIdentity(_ fixtures: [HistoryFixture]) throws -> BackupCatalogIdentity {
        var assets: [String: BackupAssetIdentity] = [:]
        for fixture in fixtures {
            let identity = try fixture.identity()
            let asset = try #require(identity.assets.values.first)
            let resource = try #require(asset.resources[fixture.assets[0].resources[0].id])
            assets[asset.assetID] = BackupAssetIdentity(
                assetID: asset.assetID, canonical: asset.canonical, digest: asset.digest,
                isReusableAcrossConnections: true, resources: [resource.resourceID: resource]
            )
        }
        return BackupCatalogIdentity(deviceKey: fixtures.first?.device.id ?? HistoryFixture().device.id,
                                     sessionID: UUID(), assets: assets)
    }
}
