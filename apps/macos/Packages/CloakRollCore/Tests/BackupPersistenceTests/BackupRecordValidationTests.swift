import BackupEngine
import BackupPersistence
import Foundation
import MediaModels
import Testing

@Suite("Persistent evidence boundaries")
struct BackupRecordValidationTests {
    @Test(arguments: ["session", "device", "asset", "path", "size", "digest", "signature", "filename"])
    func recordsMustMatchTheRegisteredOriginal(change: String) async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        let original = try fixture.record()
        let invalid = VerifiedBackupResource(
            assetID: change == "asset" ? "unrelated" : original.assetID, resourceID: original.resourceID,
            deviceID: change == "device" ? "other-device" : original.deviceID,
            sourceSessionID: change == "session" ? UUID() : original.sourceSessionID,
            filename: change == "filename" ? "unrelated.HEIC" : original.filename,
            relativePath: change == "path" ? "../outside.HEIC" : original.relativePath,
            byteCount: change == "size" ? original.byteCount + 1 : original.byteCount,
            sha256: change == "digest" ? "invalid" : original.sha256, verifiedAt: original.verifiedAt,
            sourceModifiedAt: original.sourceModifiedAt, destinationIdentity: original.destinationIdentity,
            sourceMetadataSignature: change == "signature" ? "changed" : original.sourceMetadataSignature
        )
        await #expect(throws: BackupStoreError.invalidRecord) { try await store.recordVerified(sessionID: id, record: invalid) }
        #expect(try await fixture.candidates(store).isEmpty)
        #expect(try await store.recentSessions().first?.verifiedResources == 0)
    }

    @Test func aLaterConflictingCallbackCannotReplaceAnExistingVerifiedRecord() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        let original = try fixture.record()
        try await store.recordVerified(sessionID: id, record: original)
        await #expect(throws: BackupStoreError.invalidRecord) {
            try await store.recordVerified(sessionID: id, record: fixture.record(byte: 2))
        }
        #expect(try await fixture.candidates(store).first?.record == original)
    }

    @Test func anInvalidIdentityDoesNotCreatePartialRegistration() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let identity = try fixture.identity()
        let asset = try #require(identity.assets.values.first)
        let invalid = BackupCatalogIdentity(deviceKey: identity.deviceKey, sessionID: identity.sessionID, assets: [asset.assetID: BackupAssetIdentity(
            assetID: asset.assetID, canonical: asset.canonical + "changed", digest: asset.digest,
            isReusableAcrossConnections: true, resources: asset.resources
        )])
        await #expect(throws: BackupStoreError.invalidIdentity) {
            try await store.beginSession(device: fixture.device, destinationID: fixture.destinationID,
                                         sourceSessionID: fixture.sourceSessionID, assets: fixture.assets, identity: invalid)
        }
        #expect(try await store.recentSessions().isEmpty)
    }

    @Test func aFinishedSessionRejectsLateRecords() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let id = try await fixture.begin(store)
        try await store.finishSession(id: id, result: BackupSnapshot(phase: .cancelled))
        await #expect(throws: BackupStoreError.unknownSession) {
            try await store.recordVerified(sessionID: id, record: fixture.record())
        }
        #expect(try await fixture.candidates(store).isEmpty)
    }
}
