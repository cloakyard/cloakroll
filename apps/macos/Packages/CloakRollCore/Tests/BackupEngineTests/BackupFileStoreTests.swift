import CryptoKit
import Darwin
import Foundation
import Testing
@testable import BackupEngine

@Suite("Backup filesystem boundaries")
struct BackupFileStoreTests {
    private let date = Date(timeIntervalSince1970: 1_789_214_400)

    @Test func pathsUseCapturedGregorianTimeZoneAndAnExplicitUnknownDateFolder() throws {
        let timestamp = try #require(ISO8601DateFormatter().date(from: "2026-01-01T00:30:00Z"))
        #expect(BackupPathNaming.folders(createdAt: timestamp, timeZone: .gmt) == ["2026", "01"])
        let west = try #require(TimeZone(secondsFromGMT: -3_600))
        #expect(BackupPathNaming.folders(createdAt: timestamp, timeZone: west) == ["2025", "12"])
        #expect(BackupPathNaming.folders(createdAt: nil, timeZone: .gmt) == ["Date Unknown"])
    }

    @Test func filenamesPreserveUnicodeAndExtensionsWithoutTraversalOrOverlongComponents() {
        #expect(BackupPathNaming.filename("Café 📷.HEIC") == "Café 📷.HEIC")
        #expect(BackupPathNaming.filename("Cafe\u{301}.HEIC") == "Café.HEIC")
        #expect(BackupPathNaming.filename("IMG.MOV", collision: 2) == "IMG (2).MOV")
        for name in [".", "..", "../../IMG.HEIC", "folder\\IMG.MOV", "\0\n.AAE", ""] {
            let safe = BackupPathNaming.filename(name)
            #expect(BackupDescriptor.isComponent(safe))
            #expect(!safe.contains("\\"))
            #expect(!safe.contains("\n"))
        }
        let long = BackupPathNaming.filename(String(repeating: "📷é", count: 200) + ".HEIC", collision: 9_999)
        #expect(long.utf8.count <= 255)
        #expect(long.hasSuffix(" (9999).HEIC"))
    }

    @Test func existingFilesAndConcurrentFinalizationAreNeverOverwritten() async throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folders = BackupPathNaming.folders(createdAt: date, timeZone: .gmt)
        let destination = folders.reduce(root) { $0.appendingPathComponent($1) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let original = destination.appendingPathComponent("IMG.HEIC")
        try Data([42]).write(to: original)
        let firstStore = try BackupFileStore(destination: root, runID: UUID(), timeZone: .gmt)
        let secondStore = try BackupFileStore(destination: root, runID: UUID(), timeZone: .gmt)
        let first = try stage(firstStore, name: "IMG.HEIC", data: Data([1]))
        let second = try stage(secondStore, name: "IMG.HEIC", data: Data([2]))
        let date = date
        async let one = Task.detached {
            try firstStore.verifyAndFinalize(first, returnedURL: first.directory.appendingPathComponent(first.filename), expectedByteCount: 1, createdAt: date)
        }.value
        async let two = Task.detached {
            try secondStore.verifyAndFinalize(second, returnedURL: second.directory.appendingPathComponent(second.filename), expectedByteCount: 1, createdAt: date)
        }.value
        let results = try await [one, two]
        #expect(Set(results.map(\.relativePath)).count == 2)
        #expect(try Data(contentsOf: original) == Data([42]))
        #expect(try Data(contentsOf: root.appendingPathComponent(results[0].relativePath)) == Data([1]))
        #expect(try Data(contentsOf: root.appendingPathComponent(results[1].relativePath)) == Data([2]))
        firstStore.closeStaging()
        secondStore.closeStaging()
    }

    @Test func anUnexpectedReturnedURLNeverReadsOrMovesTheExternalFile() throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside.txt")
        try Data([42]).write(to: outside)
        let store = try BackupFileStore(destination: root, runID: UUID(), timeZone: .gmt)
        let staged = try store.prepare(filename: "IMG.HEIC")
        #expect(throws: BackupFileError.unexpectedDownload) {
            try store.verifyAndFinalize(staged, returnedURL: outside, expectedByteCount: 1, createdAt: date)
        }
        store.discard(staged)
        store.closeStaging()
        #expect(try Data(contentsOf: outside) == Data([42]))
    }

    @Test func destinationChildSymlinksNeverRedirectFinalization() throws {
        let root = try backupDirectory()
        let outside = try backupDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let year = try #require(BackupPathNaming.folders(createdAt: date, timeZone: .gmt).first)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(year), withDestinationURL: outside)
        let store = try BackupFileStore(destination: root, runID: UUID(), timeZone: .gmt)
        let staged = try stage(store, name: "IMG.HEIC", data: Data([1]))
        #expect(throws: (any Error).self) {
            try store.verifyAndFinalize(staged, returnedURL: staged.directory.appendingPathComponent(staged.filename), expectedByteCount: 1, createdAt: date)
        }
        store.discard(staged)
        store.closeStaging()
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func symlinkedAndHardLinkedStagedFilesAreRejectedWithoutChangingTheirTargets() throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside.txt")
        try Data([42]).write(to: outside)
        let store = try BackupFileStore(destination: root, runID: UUID(), timeZone: .gmt)
        for hardLink in [false, true] {
            let staged = try store.prepare(filename: "IMG.HEIC")
            let file = staged.directory.appendingPathComponent(staged.filename)
            if hardLink { try FileManager.default.linkItem(at: outside, to: file) }
            else { try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside) }
            #expect(throws: (any Error).self) {
                try store.verifyAndFinalize(staged, returnedURL: file, expectedByteCount: 1, createdAt: date)
            }
            store.discard(staged)
            #expect(try Data(contentsOf: outside) == Data([42]))
        }
        store.closeStaging()
    }

    @Test func fifoCannotBlockVerification() throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BackupFileStore(destination: root, runID: UUID(), timeZone: .gmt)
        let staged = try store.prepare(filename: "IMG.HEIC")
        let file = staged.directory.appendingPathComponent(staged.filename)
        #expect(mkfifo(file.path, 0o600) == 0)
        #expect(throws: BackupFileError.invalidFile) {
            try store.verifyAndFinalize(staged, returnedURL: file, expectedByteCount: 1, createdAt: date)
        }
        store.discard(staged)
        store.closeStaging()
    }

    @Test func cleanupRemovesKnownPartialBytesButPreservesUnexpectedFiles() throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BackupFileStore(destination: root, runID: UUID(), timeZone: .gmt)
        let staged = try stage(store, name: "IMG.HEIC", data: Data([1]))
        let unknown = staged.directory.appendingPathComponent("unknown.txt")
        try Data([42]).write(to: unknown)
        store.discard(staged)
        store.closeStaging()
        #expect(try Data(contentsOf: unknown) == Data([42]))
        #expect(FileManager.default.fileExists(atPath: staged.directory.appendingPathComponent(staged.filename).path) == false)
    }

    @Test func freshStatRejectsSameInodeChangesAfterHashing() throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BackupFileStore(destination: root, runID: UUID(), timeZone: .gmt)
        let staged = try stage(store, name: "IMG.HEIC", data: Data([1, 2, 3]))
        let file = try staged.descriptor.file(staged.filename)
        let evidence = try BackupFileEvidence.inspect(file, expectedBytes: 3)
        #expect(try evidence.matches(file.status()))
        let handle = try FileHandle(forWritingTo: staged.directory.appendingPathComponent(staged.filename))
        try handle.write(contentsOf: Data([3, 2, 1]))
        try handle.close()
        #expect(try evidence.matches(file.status()) == false)
        store.discard(staged)
        store.closeStaging()
    }

    @Test func verificationAndReuseRejectTraversalAndChangedBytes() throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BackupFileStore(destination: root, runID: UUID(), timeZone: .gmt)
        let staged = try stage(store, name: "IMG.HEIC", data: Data([1, 2, 3]))
        let result = try store.verifyAndFinalize(
            staged, returnedURL: staged.directory.appendingPathComponent(staged.filename), expectedByteCount: 3, createdAt: date
        )
        #expect(try store.verifyExisting(relativePath: result.relativePath, expectedByteCount: 3, sha256: result.sha256))
        #expect(try store.verifyExisting(relativePath: "../outside.txt", expectedByteCount: 3, sha256: result.sha256) == false)
        try Data([3, 2, 1]).write(to: root.appendingPathComponent(result.relativePath))
        #expect(try store.verifyExisting(relativePath: result.relativePath, expectedByteCount: 3, sha256: result.sha256) == false)
        store.closeStaging()
    }

    @Test(arguments: [false, true])
    func movedOrReplacedPublicationFolderCannotReturnVerifiedEvidence(replaceFolder: Bool) throws {
        let root = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BackupFileStore(destination: root, runID: UUID(), timeZone: .gmt)
        let staged = try stage(store, name: "IMG.HEIC", data: Data([1, 2, 3]))
        let folders = BackupPathNaming.folders(createdAt: date, timeZone: .gmt)
        let originalFolder = folders.reduce(root) { $0.appendingPathComponent($1) }
        let movedFolder = root.appendingPathComponent("Moved originals")
        let declaredFile = originalFolder.appendingPathComponent(staged.filename)
        var finalized: FinalizedOriginal?
        #expect(throws: BackupFileError.changedDuringVerification) {
            finalized = try store.verifyAndFinalize(
                staged, returnedURL: staged.directory.appendingPathComponent(staged.filename), expectedByteCount: 3, createdAt: date
            ) {
                try FileManager.default.moveItem(at: originalFolder, to: movedFolder)
                if replaceFolder {
                    try FileManager.default.createDirectory(at: originalFolder, withIntermediateDirectories: false)
                    // Even identical bytes in a different inode cannot attest the published path.
                    try Data([1, 2, 3]).write(to: declaredFile)
                }
            }
        }
        #expect(finalized == nil)
        store.discard(staged)
        store.closeStaging()
        #expect(try Data(contentsOf: movedFolder.appendingPathComponent(staged.filename)) == Data([1, 2, 3]))
        if replaceFolder { #expect(try Data(contentsOf: declaredFile) == Data([1, 2, 3])) }
        else { #expect(!FileManager.default.fileExists(atPath: declaredFile.path)) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".cloakroll-staging-") })
    }

    private func stage(_ store: BackupFileStore, name: String, data: Data) throws -> StagedOriginal {
        let staged = try store.prepare(filename: name)
        try data.write(to: staged.directory.appendingPathComponent(staged.filename), options: [.withoutOverwriting])
        return staged
    }
}
