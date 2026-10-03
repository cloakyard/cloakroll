import Foundation
import Testing
@testable import BackupEngine

@Suite("Exact journal recovery")
struct BackupRecoveryTests {
    @Test func publishedOriginalSurvivesARecordFailureAndRecoversWithoutSourceAccess() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (intent, result) = try await interruptedPublication(root)
        #expect(result.snapshot.phase == .failed)
        #expect(result.snapshot.completedAssets == 0)
        #expect(try await BackupRecovery.inspect(destination: root, intent: intent) == .published(result.records[0]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".cloakroll-staging-") })
    }

    @Test(arguments: [false, true])
    func identicalBytesInAnotherFileOrSameFileMutationAreNeverRecovered(replace: Bool) async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (intent, _) = try await interruptedPublication(root)
        let file = root.appendingPathComponent(intent.relativePath)
        if replace {
            try FileManager.default.moveItem(at: file, to: file.appendingPathExtension("preserved"))
            try Data([1, 2, 3]).write(to: file)
        } else {
            let handle = try FileHandle(forWritingTo: file)
            try handle.write(contentsOf: Data([3, 2, 1]))
            try handle.close()
        }
        #expect(try await BackupRecovery.inspect(destination: root, intent: intent) == .unavailable)
        #expect(try Data(contentsOf: file) == (replace ? Data([1, 2, 3]) : Data([3, 2, 1])))
    }

    @Test(arguments: [false, true])
    func movedOrReplacedFolderNeverRedirectsARecoveredRecord(replace: Bool) async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (intent, _) = try await interruptedPublication(root)
        let file = root.appendingPathComponent(intent.relativePath)
        let folder = file.deletingLastPathComponent()
        let preserved = root.appendingPathComponent("Preserved")
        try FileManager.default.moveItem(at: folder, to: preserved)
        if replace {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data([1, 2, 3]).write(to: file)
        }
        #expect(try await BackupRecovery.inspect(destination: root, intent: intent) == .unavailable)
        #expect(try Data(contentsOf: preserved.appendingPathComponent(file.lastPathComponent)) == Data([1, 2, 3]))
    }

    @Test func destinationIdentityCannotBeReplacedByAnEqualContentFolder() async throws {
        let root = try backupDirectory()
        let other = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: other) }
        let (intent, _) = try await interruptedPublication(root)
        let copy = other.appendingPathComponent(intent.relativePath)
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: copy)
        #expect(try await BackupRecovery.inspect(destination: other, intent: intent) == .unavailable)
        #expect(try Data(contentsOf: copy) == Data([1, 2, 3]))
    }

    @Test func aMissingOrChangedOwnershipMarkerPreventsStagedRecovery() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = JournalCapture()
        _ = try await BackupEngine().run(
            assets: [backupAsset()], sessionID: UUID(), destination: root,
            onPublication: { intent in await capture.publication(intent); throw BackupTestError.source }
        ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        let intent = try #require(await capture.publications.first)
        let stage = root.appendingPathComponent(intent.staging.stagingRelativePath)
        let marker = stage.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".owner")
        try Data("Unrelated marker".utf8).write(to: marker)
        #expect(try await BackupRecovery.inspect(destination: root, intent: intent) == .unavailable)
        #expect(try Data(contentsOf: stage) == Data([1, 2, 3]))
    }

    private func interruptedPublication(_ root: URL) async throws -> (BackupPublicationIntent, BackupResult) {
        let capture = JournalCapture()
        let result = try await BackupEngine().run(
            assets: [backupAsset()], sessionID: UUID(), destination: root,
            onPublication: { await capture.publication($0) },
            onVerified: { _ in throw BackupTestError.source }
        ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        return try ( #require(await capture.publications.first), result)
    }
}
