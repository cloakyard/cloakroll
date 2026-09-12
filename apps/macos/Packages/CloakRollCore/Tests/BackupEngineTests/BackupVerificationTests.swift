import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Read-only persistent backup candidate verification")
struct BackupVerificationTests {
    @Test func completeAssetRequiresEveryComponentAndReadOnlyDestinationIsNotModified() async throws {
        let fixture = try await VerificationFixture.make()
        defer { fixture.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.destination.path)
        let before = try FileManager.default.attributesOfItem(atPath: fixture.destination.path)[.modificationDate] as? Date
        let result = try await fixture.validate()
        #expect(result.snapshot.phase == .completed)
        #expect(result.snapshot.completedAssetIDs == [fixture.asset.id])
        #expect(result.snapshot.verifiedResources == 2)
        #expect(result.snapshot.transferredBytes == 0)
        #expect(result.records == fixture.records)
        let after = try FileManager.default.attributesOfItem(atPath: fixture.destination.path)[.modificationDate] as? Date
        #expect(before == after)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path).allSatisfy { !$0.hasPrefix(".cloakroll-staging-") })
    }

    @Test(arguments: ["missing", "corrupt", "missing-record", "duplicate-record", "unsafe-path", "symlink"])
    func partialOrUntrustedCandidatesNeverCompleteAnAsset(change: String) async throws {
        let fixture = try await VerificationFixture.make()
        defer { fixture.remove() }
        var records = fixture.records
        let first = try #require(records.first)
        let path = fixture.destination.appendingPathComponent(first.relativePath)
        switch change {
        case "missing": try FileManager.default.removeItem(at: path)
        case "corrupt": try Data([9, 9, 9]).write(to: path)
        case "missing-record": records.removeFirst()
        case "duplicate-record": records.append(first)
        case "unsafe-path": records[0] = copiedRecord(first, relativePath: "../" + first.relativePath)
        case "symlink":
            let link = fixture.destination.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: path)
            records[0] = copiedRecord(first, relativePath: "link")
        default: Issue.record("Unexpected scenario")
        }
        let result = try await fixture.validate(records: records)
        #expect(result.snapshot.completedAssetIDs.isEmpty)
        #expect(result.snapshot.verifiedResources == 1)
        #expect(result.records == [fixture.records[1]])
    }

    @Test(arguments: ["session", "device", "metadata", "destination"])
    func evidenceIsIsolatedByFullSourceAndDestinationScope(change: String) async throws {
        let fixture = try await VerificationFixture.make()
        let otherDestination = try backupDirectory()
        defer { fixture.remove(); try? FileManager.default.removeItem(at: otherDestination) }
        for record in fixture.records {
            let copied = otherDestination.appendingPathComponent(record.relativePath)
            try FileManager.default.createDirectory(at: copied.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixture.destination.appendingPathComponent(record.relativePath), to: copied)
        }
        let asset = MediaAsset(
            id: fixture.asset.id, deviceID: change == "device" ? "another-device" : fixture.asset.deviceID,
            resources: fixture.asset.resources, kind: fixture.asset.kind,
            createdAt: change == "metadata" ? Date(timeIntervalSince1970: 1) : fixture.asset.createdAt
        )
        let result = try await BackupVerification.validateExisting(
            assets: [asset], sessionID: change == "session" ? UUID() : fixture.session,
            destination: change == "destination" ? otherDestination : fixture.destination, records: fixture.records
        )
        #expect(result.snapshot.completedAssetIDs.isEmpty)
        #expect(result.records.isEmpty)
    }

    @Test func rebasingUpdatesCurrentScopeButDoesNotVerifyDestinationBytes() async throws {
        let fixture = try await VerificationFixture.make()
        defer { fixture.remove() }
        let newSession = UUID()
        let resources = fixture.asset.resources.map {
            MediaResource(id: "reconnected-" + $0.id, filename: $0.filename, byteCount: $0.byteCount, modifiedAt: $0.modifiedAt)
        }
        let asset = MediaAsset(
            id: "reconnected-asset", deviceID: fixture.asset.deviceID, resources: resources,
            kind: fixture.asset.kind, createdAt: fixture.asset.createdAt
        )
        let rebased = try zip(fixture.records, resources).map {
            try BackupEngine.rebase($0.0, asset: asset, resource: $0.1, sessionID: newSession)
        }
        #expect(rebased.map(\.sourceSessionID) == [newSession, newSession])
        #expect(rebased.map(\.resourceID) == resources.map(\.id))
        #expect(rebased.map(\.relativePath) == fixture.records.map(\.relativePath))
        #expect(rebased.map(\.sha256) == fixture.records.map(\.sha256))
        #expect(rebased.map(\.verifiedAt) == fixture.records.map(\.verifiedAt))
        #expect(try rebased[0].sourceMetadataSignature == BackupEngine.sourceSignature(asset: asset, resource: resources[0]))
        let valid = try await BackupVerification.validateExisting(
            assets: [asset], sessionID: newSession, destination: fixture.destination, records: rebased
        )
        #expect(valid.snapshot.completedAssetIDs == [asset.id])
        try Data([9, 9, 9]).write(to: fixture.destination.appendingPathComponent(rebased[0].relativePath))
        let corrupt = try await BackupVerification.validateExisting(
            assets: [asset], sessionID: newSession, destination: fixture.destination, records: rebased
        )
        #expect(corrupt.snapshot.completedAssetIDs.isEmpty)
        #expect(throws: BackupEngineError.sourceSizeChanged) {
            try BackupEngine.rebase(fixture.records[0], asset: asset,
                                    resource: MediaResource(id: resources[0].id, filename: resources[0].filename, byteCount: 4), sessionID: newSession)
        }
        #expect(throws: BackupEngineError.invalidSelection) {
            try BackupEngine.rebase(fixture.records[0], asset: asset,
                                    resource: MediaResource(id: "not-in-asset", filename: "IMG.HEIC", byteCount: 3), sessionID: newSession)
        }
    }
}

private struct VerificationFixture: Sendable {
    let destination: URL
    let session: UUID
    let asset: MediaAsset
    let records: [VerifiedBackupResource]

    static func make() async throws -> VerificationFixture {
        let destination = try backupDirectory()
        let session = UUID()
        let asset = backupAsset(resources: [
            MediaResource(id: "photo", filename: "IMG.HEIC", byteCount: 3),
            MediaResource(id: "motion", filename: "IMG.MOV", byteCount: 3)
        ])
        let result = try await BackupEngine().run(assets: [asset], sessionID: session, destination: destination) { request, _ in
            try writeOriginal(request, data: Data([1, 2, 3]))
        }
        try #require(result.snapshot.phase == .completed)
        return VerificationFixture(destination: destination, session: session, asset: asset, records: result.records)
    }

    func validate(records: [VerifiedBackupResource]? = nil) async throws -> BackupResult {
        try await BackupVerification.validateExisting(assets: [asset], sessionID: session, destination: destination, records: records ?? self.records)
    }

    func remove() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path)
        try? FileManager.default.removeItem(at: destination)
    }
}

private func copiedRecord(_ record: VerifiedBackupResource, relativePath: String) -> VerifiedBackupResource {
    VerifiedBackupResource(
        assetID: record.assetID, resourceID: record.resourceID, deviceID: record.deviceID, sourceSessionID: record.sourceSessionID,
        filename: record.filename, relativePath: relativePath, byteCount: record.byteCount, sha256: record.sha256,
        verifiedAt: record.verifiedAt, sourceModifiedAt: record.sourceModifiedAt,
        destinationIdentity: record.destinationIdentity, sourceMetadataSignature: record.sourceMetadataSignature
    )
}
