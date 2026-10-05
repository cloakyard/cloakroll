import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Offline saved original checks")
struct SavedBackupCheckTests {
    @Test func readsOriginalsWithoutSourceOrDestinationWrites() async throws {
        let fixture = try await SavedCheckFixture.make()
        defer { fixture.remove() }
        let before = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.root.path)
        let result = try await SavedBackupCheck.run(destination: fixture.root, records: fixture.records)
        #expect(result.totalFiles == 2 && result.checkedFiles == 2 && result.matchingFiles == 2)
        #expect(result.unverifiedPaths.isEmpty && result.unverifiedFiles == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == before)
    }

    @Test(arguments: ["missing", "size", "digest", "symlink", "parent-symlink", "unsafe"])
    func untrustedOrChangedFilesAreReportedWithoutRepair(change: String) async throws {
        let fixture = try await SavedCheckFixture.make()
        defer { fixture.remove() }
        let first = fixture.records[0]
        let file = fixture.root.appendingPathComponent(first.relativePath)
        var records = fixture.records
        switch change {
        case "missing": try FileManager.default.removeItem(at: file)
        case "size": try Data([9]).write(to: file)
        case "digest": try Data([9, 9, 9]).write(to: file)
        case "symlink":
            try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("link"), withDestinationURL: file)
            records[0] = first.replacing(path: "link")
        case "parent-symlink":
            try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("parent"),
                                                       withDestinationURL: file.deletingLastPathComponent())
            records[0] = first.replacing(path: "parent/" + file.lastPathComponent)
        case "unsafe": records[0] = first.replacing(path: "../" + first.relativePath)
        default: Issue.record("Unknown scenario")
        }
        let result = try await SavedBackupCheck.run(destination: fixture.root, records: records)
        #expect(result.checkedFiles == 2 && result.matchingFiles == 1 && result.unverifiedFiles == 1)
        #expect(result.unverifiedPaths == [records[0].relativePath])
        if change == "missing" { #expect(!FileManager.default.fileExists(atPath: file.path)) }
        if change == "digest" { #expect(try Data(contentsOf: file) == Data([9, 9, 9])) }
    }

    @Test func copiedFolderIsNotMistakenForTheOriginalDestination() async throws {
        let fixture = try await SavedCheckFixture.make()
        let other = try backupDirectory()
        defer { fixture.remove(); try? FileManager.default.removeItem(at: other) }
        for record in fixture.records {
            let copy = other.appendingPathComponent(record.relativePath)
            try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixture.root.appendingPathComponent(record.relativePath), to: copy)
        }
        await #expect(throws: SavedBackupCheckError.differentFolder) {
            try await SavedBackupCheck.run(destination: other, records: fixture.records)
        }
    }

    @Test func duplicateOrMalformedEvidenceCannotProduceSuccess() async throws {
        let fixture = try await SavedCheckFixture.make()
        defer { fixture.remove() }
        for records in [fixture.records + [fixture.records[0]], [fixture.records[0].replacing(digest: "invalid")]] {
            await #expect(throws: SavedBackupCheckError.invalidRecords) {
                try await SavedBackupCheck.run(destination: fixture.root, records: records)
            }
        }
    }

    @Test func issueListIsBoundedWithoutTruncatingTheCounts() async throws {
        let fixture = try await SavedCheckFixture.make()
        defer { fixture.remove() }
        let records = (0..<150).map { fixture.records[0].replacing(path: "missing-\($0)") }
        let result = try await SavedBackupCheck.run(destination: fixture.root, records: records)
        #expect(result.totalFiles == 150 && result.checkedFiles == 150 && result.unverifiedFiles == 150)
        #expect(result.unverifiedPaths.count == 100 && result.matchingFiles == 0)
    }

    @Test(arguments: [0, 2])
    func cancellationBeforeReadsOrAfterLastProgressNeverReturnsSuccess(checkedCount: Int) async throws {
        let fixture = try await SavedCheckFixture.make()
        defer { fixture.remove() }
        let gate = SavedCheckProgressGate()
        let check = Task {
            try await SavedBackupCheck.run(destination: fixture.root, records: fixture.records) { progress in
                if progress.checkedFiles == checkedCount { await gate.hold() }
            }
        }
        try await gate.waitUntilHeld()
        check.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await check.value }
        #expect(try await SavedBackupCheck.run(destination: fixture.root, records: fixture.records).matchingFiles == 2)
    }

    @Test func emptyRecordsRemainAnEmptyCheck() async throws {
        let result = try await SavedBackupCheck.run(destination: URL(fileURLWithPath: "/unused-no-files"), records: [])
        #expect(result.totalFiles == 0 && result.checkedFiles == 0 && result.matchingFiles == 0)
    }
}

private struct SavedCheckFixture {
    let root: URL
    let records: [VerifiedBackupResource]

    static func make() async throws -> Self {
        let root = try backupDirectory()
        let asset = backupAsset(resources: [MediaResource(id: "photo", filename: "IMG.HEIC", byteCount: 3),
                                           MediaResource(id: "motion", filename: "IMG.MOV", byteCount: 3)])
        let result = try await BackupEngine().run(assets: [asset], sessionID: UUID(), destination: root) { request, _ in
            try writeOriginal(request, data: Data([1, 2, 3]))
        }
        try #require(result.records.count == 2)
        return Self(root: root, records: result.records)
    }

    func remove() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }
}

private extension VerifiedBackupResource {
    func replacing(path: String? = nil, digest: String? = nil) -> Self {
        Self(assetID: assetID, resourceID: resourceID, deviceID: deviceID, sourceSessionID: sourceSessionID,
             filename: filename, relativePath: path ?? relativePath, byteCount: byteCount, sha256: digest ?? sha256,
             verifiedAt: verifiedAt, sourceModifiedAt: sourceModifiedAt, destinationIdentity: destinationIdentity,
             sourceMetadataSignature: sourceMetadataSignature)
    }
}

private actor SavedCheckProgressGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func hold() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
    func waitUntilHeld() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while continuation == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(continuation != nil)
    }
}
