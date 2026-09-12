import Foundation
import Testing
@testable import ThumbnailPipeline

@Suite("Conservative preview reuse across connections")
struct ThumbnailReconnectTests {
    @Test(arguments: [false, true])
    func onlyExplicitReusableIdentitiesSurviveReconnect(diskOnly: Bool) async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstSession = UUID()
        let secondSession = UUID()
        let configuration = ThumbnailPipelineConfiguration(memoryByteLimit: diskOnly ? 0 : 1_024)
        let pipeline = ThumbnailPipeline(cacheDirectory: directory, configuration: configuration)
        await pipeline.setSession(firstSession)
        let reusable = reusableKey("handle-old", session: firstSession, identity: "device-a:unique-complete-metadata")
        let scoped = key("session-only", session: firstSession)
        _ = try await pipeline.data(for: reusable) { Data([1]) }
        _ = try await pipeline.data(for: scoped) { Data([2]) }
        await pipeline.setSession(nil)
        #expect(await pipeline.metrics().diskItems == 1)
        #expect(await pipeline.metrics().memoryItems == (diskOnly ? 0 : 1))
        #expect(FileManager.default.fileExists(atPath: try diskFile(scoped, directory: directory).path) == false)
        await #expect(throws: ThumbnailPipelineError.staleSession) {
            try await pipeline.data(for: reusable) { throw PipelineTestError.unexpectedLoad }
        }
        await pipeline.setSession(secondSession)
        let reconnected = reusableKey("handle-new", session: secondSession, identity: "device-a:unique-complete-metadata")
        #expect(try await pipeline.data(for: reconnected) { throw PipelineTestError.unexpectedLoad } == Data([1]))
        #expect(await pipeline.metrics().sourceLoads == 2)
        #expect(await pipeline.metrics().diskHits == (diskOnly ? 1 : 0))
        #expect(await pipeline.metrics().memoryHits == (diskOnly ? 0 : 1))
        #expect(try await pipeline.data(for: key("session-only", session: secondSession)) { Data([3]) } == Data([3]))
        #expect(await pipeline.metrics().sourceLoads == 3)
    }

    @Test func changedMetadataDifferentDevicesAndChangedVersionsDoNotReusePreviews() async throws {
        let pipeline = ThumbnailPipeline()
        let examples = [
            ("device-a:metadata-one", "version-one"),
            ("device-a:metadata-two", "version-one"),
            ("device-b:metadata-one", "version-one"),
            ("device-a:metadata-one", "version-two")
        ]
        for (index, example) in examples.enumerated() {
            let session = UUID()
            await pipeline.setSession(session)
            let resource = reusableKey("handle-\(index)", session: session, identity: example.0, version: example.1)
            let expected = Data([UInt8(index)])
            #expect(try await pipeline.data(for: resource) { expected } == expected)
        }
        #expect(await pipeline.metrics().sourceLoads == 4)
        #expect(await pipeline.metrics().memoryHits == 0)
    }

    @Test func aLateRetiredReusableResultCannotSatisfyTheNewConnection() async throws {
        let firstSession = UUID()
        let secondSession = UUID()
        let pipeline = ThumbnailPipeline(configuration: .init(maximumActiveLoads: 1))
        let source = ControlledThumbnailSource()
        await pipeline.setSession(firstSession)
        let oldKey = reusableKey("old-handle", session: firstSession, identity: "same-preview")
        let old = Task { try await pipeline.data(for: oldKey) { try await source.load("old") } }
        try await eventually("old reusable source starts") { await source.started == ["old"] }
        await pipeline.setSession(secondSession)
        await #expect(throws: ThumbnailPipelineError.staleSession) { try await old.value }
        let newKey = reusableKey("new-handle", session: secondSession, identity: "same-preview")
        let current = Task { try await pipeline.data(for: newKey) { Data([7]) } }
        try await eventually("new request waits for retained slot") { await pipeline.metrics().queued == 1 }
        await source.finish("old", data: Data([9]))
        #expect(try await current.value == Data([7]))
        #expect(await pipeline.metrics().sourceLoads == 2)
        #expect(await pipeline.metrics().memoryItems == 1)
    }

    @Test func reusableEntriesShareTheSameBudgetWithSessionOnlyEntries() async throws {
        let pipeline = ThumbnailPipeline(configuration: .init(memoryByteLimit: 2, memoryItemLimit: 2))
        let firstSession = UUID()
        await pipeline.setSession(firstSession)
        let first = reusableKey("first", session: firstSession, identity: "reusable-one")
        let second = reusableKey("second", session: firstSession, identity: "reusable-two")
        _ = try await pipeline.data(for: first) { Data([1]) }
        _ = try await pipeline.data(for: second) { Data([2]) }
        let nextSession = UUID()
        await pipeline.setSession(nextSession)
        _ = try await pipeline.data(for: key("scoped", session: nextSession)) { Data([3]) }
        #expect(await pipeline.metrics().memoryBytes == 2)
        #expect(await pipeline.metrics().memoryItems == 2)
        let firstAgain = reusableKey("first-again", session: nextSession, identity: "reusable-one")
        #expect(try await pipeline.data(for: firstAgain) { Data([4]) } == Data([4]))
        #expect(await pipeline.metrics().sourceLoads == 4)
    }

    @Test func restartPurgesEvenExplicitlyReusableEntries() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = UUID()
        let original = ThumbnailPipeline(cacheDirectory: directory, configuration: .init(memoryByteLimit: 0))
        await original.setSession(session)
        let resource = reusableKey("first", session: session, identity: "device-a:metadata")
        _ = try await original.data(for: resource) { Data([1]) }
        let oldFile = directory.appendingPathComponent("CloakRollThumbnails-v1")
            .appendingPathComponent("s-" + session.uuidString.lowercased())
            .appendingPathComponent(try #require(ThumbnailDiskCodec.filename(for: resource.storageKey)))
        #expect(FileManager.default.fileExists(atPath: oldFile.path))
        let restarted = ThumbnailPipeline(cacheDirectory: directory, configuration: .init(memoryByteLimit: 0))
        await restarted.setSession(nil)
        #expect(FileManager.default.fileExists(atPath: oldFile.path) == false)
        let next = UUID()
        await restarted.setSession(next)
        #expect(try await restarted.data(for: reusableKey("new", session: next, identity: "device-a:metadata")) { Data([2]) } == Data([2]))
        #expect(await restarted.metrics().sourceLoads == 1)
        #expect(await restarted.metrics().diskHits == 0)
    }

    private func reusableKey(_ name: String, session: UUID, identity: String, version: String = "1") -> ThumbnailKey {
        ThumbnailKey(sessionID: session, resourceID: name, version: version, maximumPixelSize: 512, reusableIdentity: identity)
    }
}
