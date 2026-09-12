import BackupPersistence
import Foundation
import MediaModels
import Testing

@Suite("Conservative persisted candidates")
struct BackupCandidateTests {
    @Test func reconnectReturnsCurrentAddressesAndUnmodifiedHistoricalEvidence() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let previous = HistoryFixture()
        do {
            let store = try await BackupStore(databaseURL: directory.databaseURL)
            let id = try await previous.begin(store)
            try await store.recordVerified(sessionID: id, record: previous.record())
        }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let current = HistoryFixture(destinationID: previous.destinationID, prefix: "current")
        let candidate = try #require(try await current.candidates(store).first)
        #expect(candidate.assetID == "current-asset")
        #expect(candidate.resourceID == "current-still")
        #expect(candidate.record == (try previous.record()))
        #expect(candidate.record.sourceSessionID != current.sourceSessionID)
    }

    @Test(arguments: ["device", "destination", "companion"])
    func changedSourceOrDestinationNeverProducesACandidate(change: String) async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let previous = HistoryFixture()
        let id = try await previous.begin(store)
        try await store.recordVerified(sessionID: id, record: previous.record())
        let current = HistoryFixture(
            deviceValue: change == "device" ? "device-two" : "device-one",
            destinationID: change == "destination" ? UUID() : previous.destinationID,
            prefix: "current", motionBytes: change == "companion" ? 6 : 5
        )
        #expect(try await current.candidates(store).isEmpty)
    }

    @Test func matchingDigestStillRequiresExactCanonicalEvidence() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        try await store.recordVerified(sessionID: id, record: fixture.record())
        let identity = try fixture.identity()
        let asset = try #require(identity.assets.values.first)
        let resource = try #require(asset.resources["old-still"])
        let colliding = BackupResourceIdentity(
            resourceID: resource.resourceID, canonical: resource.canonical + "changed", digest: resource.digest,
            isReusableAcrossConnections: true
        )
        let altered = BackupCatalogIdentity(deviceKey: identity.deviceKey, sessionID: UUID(), assets: [asset.assetID: BackupAssetIdentity(
            assetID: asset.assetID, canonical: asset.canonical, digest: asset.digest, isReusableAcrossConnections: true,
            resources: [colliding.resourceID: colliding]
        )])
        #expect(try await store.candidates(deviceKey: fixture.device.id, destinationID: fixture.destinationID, identity: altered).isEmpty)
    }

    @Test(arguments: [true, false])
    func sessionOnlyEvidenceRequiresTheExactSourceSession(persistentDevice: Bool) async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let previous = HistoryFixture(persistent: persistentDevice)
        let id = try await previous.begin(store, reusable: false)
        try await store.recordVerified(sessionID: id, record: previous.record())
        #expect(try await previous.candidates(store, reusable: false).count == 1)
        let current = HistoryFixture(destinationID: previous.destinationID, prefix: "current", persistent: persistentDevice)
        #expect(try await current.candidates(store, reusable: false).isEmpty)
    }

    @Test func conflictingHistoricalBytesAreAmbiguousEvenWithIdenticalMetadata() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let first = HistoryFixture()
        let firstID = try await first.begin(store)
        try await store.recordVerified(sessionID: firstID, record: first.record())
        let second = HistoryFixture(destinationID: first.destinationID, prefix: "second")
        let secondID = try await second.begin(store)
        try await store.recordVerified(sessionID: secondID, record: second.record(byte: 2, path: "2026/09/IMG_0001 (1).HEIC"))
        #expect(try await second.candidates(store).isEmpty)
    }

    @Test func duplicateCurrentAssetsNeverBorrowOneHistoricalOriginal() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        try await store.recordVerified(sessionID: id, record: fixture.record())
        let original = try fixture.identity()
        let first = try #require(original.assets.values.first)
        let duplicate = BackupAssetIdentity(assetID: "duplicate", canonical: first.canonical, digest: first.digest,
                                            isReusableAcrossConnections: true, resources: first.resources)
        let ambiguous = BackupCatalogIdentity(deviceKey: original.deviceKey, sessionID: UUID(),
                                              assets: [first.assetID: first, duplicate.assetID: duplicate])
        #expect(try await store.candidates(deviceKey: fixture.device.id, destinationID: fixture.destinationID, identity: ambiguous).isEmpty)
    }
}
