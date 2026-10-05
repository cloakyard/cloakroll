import Foundation
import MediaModels
import Testing
@testable import BackupEngine

@Suite("Backup destination capacity")
struct BackupCapacityTests {
    @Test(arguments: [Int64(0), 2])
    func insufficientSpaceStopsBeforeSourceOrJournal(available: Int64) async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try await BackupEngine(capacity: .init { _ in available }).run(
            assets: [backupAsset()], sessionID: UUID(), destination: destination,
            onStaged: { _ in Issue.record("Insufficient space must not start a staging journal") }
        ) { _, _ in
            Issue.record("Insufficient space must not download an original")
            throw BackupTestError.unexpectedLoad
        }
        #expect(result.snapshot.phase == .failed)
        #expect(result.snapshot.message == BackupFileError.insufficientSpace.errorDescription)
        #expect(result.snapshot.completedAssets == 0)
        #expect(result.snapshot.transferredBytes == 0)
        #expect(result.records.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    @Test(arguments: [Int64?.none, -1, 3, .max])
    func unknownAndSufficientCapacityPermitTheNormalVerifiedTransfer(available: Int64?) async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try await BackupEngine(capacity: .init { _ in available }).run(
            assets: [backupAsset()], sessionID: UUID(), destination: destination
        ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        #expect(result.snapshot.phase == .completed)
        #expect(result.records.count == 1)
    }

    @Test func unavailableCapacityDoesNotInventAnOutOfSpaceError() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try await BackupEngine(capacity: .init { _ in throw CocoaError(.featureUnsupported) }).run(
            assets: [backupAsset()], sessionID: UUID(), destination: destination
        ) { request, _ in try writeOriginal(request, data: Data([1, 2, 3])) }
        #expect(result.snapshot.phase == .completed)
    }

    @Test func capacityIsRecheckedAndAPartialLivePhotoCanBeRetried() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let probe = CapacitySequence([3, 0])
        let asset = backupAsset(resources: [
            MediaResource(id: "photo", filename: "IMG.HEIC", byteCount: 3),
            MediaResource(id: "motion", filename: "IMG.MOV", byteCount: 3)
        ])
        let session = UUID()
        let first = try await BackupEngine(capacity: .init { probe.next($0) }).run(
            assets: [asset], sessionID: session, destination: destination
        ) { request, _ in
            #expect(request.resource.id == "photo")
            return try writeOriginal(request, data: Data([1, 2, 3]))
        }
        #expect(first.snapshot.phase == .failed)
        #expect(first.snapshot.completedAssets == 0)
        #expect(first.records.count == 1)
        #expect(first.snapshot.verifiedResources == 1)
        #expect(probe.count == 2)
        let saved = try #require(first.records.first)
        let savedURL = destination.appendingPathComponent(saved.relativePath)
        #expect(try Data(contentsOf: savedURL) == Data([1, 2, 3]))

        let retryProbe = CapacitySequence([3])
        let retry = try await BackupEngine(previousRecords: first.records, capacity: .init { retryProbe.next($0) }).run(
            assets: [asset], sessionID: session, destination: destination
        ) { request, _ in
            #expect(request.resource.id == "motion")
            return try writeOriginal(request, data: Data([4, 5, 6]))
        }
        #expect(retry.snapshot.phase == .completed)
        #expect(retry.snapshot.transferredBytes == 3)
        #expect(retry.snapshot.verifiedResources == 2)
        #expect(retryProbe.count == 1)
        #expect(retry.records.first?.relativePath == saved.relativePath)
        #expect(try Data(contentsOf: savedURL) == Data([1, 2, 3]))
    }

    @Test func alreadyVerifiedOriginalsNeedNoAdditionalMediaCapacity() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let asset = backupAsset()
        let session = UUID()
        let first = try await BackupEngine().run(assets: [asset], sessionID: session, destination: destination) { request, _ in
            try writeOriginal(request, data: Data([1, 2, 3]))
        }
        let repeatResult = try await BackupEngine(previousRecords: first.records, capacity: .init { _ in
            Issue.record("Verified reuse must not require the size of another original")
            return 0
        }).run(assets: [asset], sessionID: session, destination: destination) { _, _ in
            throw BackupTestError.unexpectedLoad
        }
        #expect(repeatResult.snapshot.phase == .completed)
        #expect(repeatResult.snapshot.transferredBytes == 0)
    }

    @Test func aLaterWriteFailureStillCannotBecomeSuccess() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try await BackupEngine(capacity: .init { _ in .max }).run(
            assets: [backupAsset()], sessionID: UUID(), destination: destination
        ) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        #expect(result.snapshot.phase == .failed)
        #expect(result.records.isEmpty)
        #expect(result.snapshot.verifiedResources == 0)
    }

    @Test func aMissingSavedOriginalMustPassCapacityBeforeDownloadingAgain() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let asset = backupAsset()
        let session = UUID()
        let first = try await BackupEngine().run(assets: [asset], sessionID: session, destination: destination) { request, _ in
            try writeOriginal(request, data: Data([1, 2, 3]))
        }
        let record = try #require(first.records.first)
        try FileManager.default.removeItem(at: destination.appendingPathComponent(record.relativePath))
        let repeatResult = try await BackupEngine(previousRecords: first.records, capacity: .init { _ in 0 }).run(
            assets: [asset], sessionID: session, destination: destination
        ) { _, _ in
            Issue.record("A missing original must not skip the capacity check")
            throw BackupTestError.unexpectedLoad
        }
        #expect(repeatResult.snapshot.phase == .failed)
        #expect(repeatResult.snapshot.message == BackupFileError.insufficientSpace.errorDescription)
        #expect(repeatResult.records.isEmpty)
    }

    @Test func cancellingDuringTheCapacityProbePreventsTheDownload() async throws {
        let destination = try backupDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let engine = BackupEngine(capacity: .init { _ in
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
            return .max
        })
        let run = Task {
            try await engine.run(assets: [backupAsset()], sessionID: UUID(), destination: destination) { _, _ in
                Issue.record("Cancellation while checking capacity must prevent download")
                throw BackupTestError.unexpectedLoad
            }
        }
        let waitForEntry: @Sendable () -> Bool = { entered.wait(timeout: .now() + 5) == .success }
        let started = await Task.detached(operation: waitForEntry).value
        #expect(started)
        await engine.cancel()
        release.signal()
        let result = try await run.value
        #expect(result.snapshot.phase == .cancelled)
        #expect(result.records.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }
}

private final class CapacitySequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64]
    private var calls = 0

    init(_ values: [Int64]) { self.values = values }
    var count: Int { lock.withLock { calls } }

    func next(_ url: URL) -> Int64? {
        lock.withLock {
            #expect(url.isFileURL)
            calls += 1
            guard !values.isEmpty else { Issue.record("Unexpected capacity query"); return nil }
            return values.removeFirst()
        }
    }
}
