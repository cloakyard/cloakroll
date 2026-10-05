import BackupEngine
import BackupPersistence
import Foundation
import MediaModels
import Testing

@Suite("USB verification of media-only folders")
struct BackupLegacyRecoveryTests {
    @Test(arguments: [false, true]) func bytesDecideRecoveryEvenWhenNamesDisagree(matching: Bool) async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let fixture = HistoryFixture()
        let original = directory.url.appendingPathComponent(matching ? "Renamed Photo.heic" : "IMG_0001.HEIC")
        let content = Data(repeating: matching ? 1 : 9, count: 3)
        try content.write(to: original)
        let before = try FileManager.default.attributesOfItem(atPath: original.path)[.systemFileNumber] as? NSNumber
        let existing = try BackupRecoveryIndex.scan(destination: directory.url)
        let scan = try await BackupLegacyRecovery.run(
            assets: fixture.assets, device: fixture.device, identity: fixture.identity(), destination: directory.url, existing: existing
        ) { request, _ in
            #expect(request.resource.byteCount == 3)
            let url = request.directory.appendingPathComponent(request.filename)
            try Data(repeating: 1, count: 3).write(to: url)
            return DownloadedOriginal(url: url, expectedByteCount: 3)
        }
        #expect(scan.entries.count == (matching ? 1 : 0))
        #expect(try Data(contentsOf: original) == content)
        #expect(try FileManager.default.attributesOfItem(atPath: original.path)[.systemFileNumber] as? NSNumber == before)
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)
        #expect(!contents.contains { $0.hasPrefix(".cloakroll-staging-") })
        #expect(contents.filter { !$0.hasPrefix(".") } == [original.lastPathComponent])
        if matching {
            let fresh = try await BackupStore(databaseURL: directory.databaseURL)
            #expect(try await fresh.importRecovery(scan, destinationID: fixture.destinationID) == 1)
            #expect(try await fresh.recentSessions().first?.completedAssets == 0)
            let repeated = try await BackupLegacyRecovery.run(
                assets: fixture.assets, device: fixture.device, identity: fixture.identity(), destination: directory.url,
                existing: BackupRecoveryIndex.scan(destination: directory.url)
            ) { _, _ in
                Issue.record("An indexed and verified original should not be read over USB twice")
                throw BackupEngineError.invalidSelection
            }
            #expect(repeated.entries.count == 1)
        }
    }

    @Test func cancellationWaitsForLatePhysicalCompletionAndCreatesNoReceipt() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        try Data([1, 1, 1]).write(to: directory.url.appendingPathComponent("Photo.heic"))
        let fixture = HistoryFixture()
        let gate = RecoveryDownloadGate()
        let task = Task {
            try await BackupLegacyRecovery.run(
                assets: fixture.assets, device: fixture.device, identity: fixture.identity(), destination: directory.url,
                existing: BackupRecoveryIndex.scan(destination: directory.url)
            ) { request, _ in
                await gate.wait()
                let url = request.directory.appendingPathComponent(request.filename)
                try Data([1, 1, 1]).write(to: url)
                return DownloadedOriginal(url: url, expectedByteCount: 3)
            }
        }
        await gate.waitUntilEntered()
        task.cancel()
        #expect(try BackupRecoveryIndex.scan(destination: directory.url).entries.isEmpty)
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try BackupRecoveryIndex.scan(destination: directory.url).entries.isEmpty)
        #expect(try Data(contentsOf: directory.url.appendingPathComponent("Photo.heic")) == Data([1, 1, 1]))
    }

    @Test func cancelledImportDoesNotCreateHistory() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let root = directory.url.appendingPathComponent("Originals")
        _ = try await BackupFolderRecoveryTests().seed(directory: directory, fixture: HistoryFixture(), destination: root)
        let store = try await BackupStore(databaseURL: directory.url.appendingPathComponent("Fresh.sqlite"))
        let scan = try BackupRecoveryIndex.scan(destination: root)
        let gate = RecoveryDownloadGate()
        let task = Task {
            await gate.wait()
            return try await store.importRecovery(scan, destinationID: UUID())
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await store.recentSessions().isEmpty)
    }
}

private actor RecoveryDownloadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered?.resume()
            entered = nil
        }
    }
    func waitUntilEntered() async {
        if continuation != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
