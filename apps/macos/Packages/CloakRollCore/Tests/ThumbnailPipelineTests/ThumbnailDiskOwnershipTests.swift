import Foundation
import Testing
@testable import ThumbnailPipeline

@Suite("Thumbnail disk ownership and failures")
struct ThumbnailDiskOwnershipTests {
    @Test func startupPurgesOnlyOwnedSessionNamespaces() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sentinel = directory.appendingPathComponent("unrelated.txt")
        try Data([42]).write(to: sentinel)
        let session = UUID()
        let first = ThumbnailPipeline(cacheDirectory: directory)
        await first.setSession(session)
        let resource = key("old", session: session)
        _ = try await first.data(for: resource) { Data([1]) }
        let oldFile = try diskFile(resource, directory: directory)
        #expect(FileManager.default.fileExists(atPath: oldFile.path))
        let restarted = ThumbnailPipeline(cacheDirectory: directory)
        await restarted.setSession(nil)
        #expect(FileManager.default.fileExists(atPath: oldFile.path) == false)
        #expect(try Data(contentsOf: sentinel) == Data([42]))
        await restarted.setSession(session)
        #expect(try await restarted.data(for: resource) { Data([2]) } == Data([2]))
        #expect(await restarted.metrics().sourceLoads == 1)
        #expect(await restarted.metrics().diskHits == 0)
    }

    @Test func retiringASessionRemovesItsNamespaceAndEncodedMemory() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = UUID()
        let pipeline = ThumbnailPipeline(cacheDirectory: directory)
        await pipeline.setSession(session)
        let resource = key("old", session: session)
        _ = try await pipeline.data(for: resource) { Data([1]) }
        await pipeline.setSession(UUID())
        #expect(FileManager.default.fileExists(atPath: try diskFile(resource, directory: directory).path) == false)
        #expect(await pipeline.metrics().memoryItems == 0)
        #expect(await pipeline.metrics().diskItems == 0)
        #expect(await pipeline.metrics().diskBytes == 0)
    }

    @Test func anUnmarkedExistingDirectoryIsNeverAdoptedOrDeleted() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let candidate = directory.appendingPathComponent("CloakRollThumbnails-v1")
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
        let sentinel = candidate.appendingPathComponent("unrelated.txt")
        try Data([42]).write(to: sentinel)
        let session = UUID()
        let pipeline = ThumbnailPipeline(cacheDirectory: directory)
        await pipeline.setSession(session)
        #expect(try await pipeline.data(for: key("source", session: session)) { Data([1]) } == Data([1]))
        #expect(try Data(contentsOf: sentinel) == Data([42]))
        #expect(await pipeline.metrics().diskItems == 0)
        #expect(await pipeline.metrics().diskFailures > 0)
        #expect(FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".owner").path) == false)
    }

    @Test func unwritableCacheLocationFallsBackToMemoryAndSourceLoading() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockedDirectory = directory.appendingPathComponent("file-not-directory")
        try Data([42]).write(to: blockedDirectory)
        let session = UUID()
        let pipeline = ThumbnailPipeline(cacheDirectory: blockedDirectory)
        await pipeline.setSession(session)
        let resource = key("source", session: session)
        #expect(try await pipeline.data(for: resource) { Data([1]) } == Data([1]))
        #expect(try await pipeline.data(for: resource) { throw PipelineTestError.unexpectedLoad } == Data([1]))
        #expect(await pipeline.metrics().diskItems == 0)
        #expect(await pipeline.metrics().diskFailures > 0)
        #expect(await pipeline.metrics().memoryHits == 1)
        #expect(try Data(contentsOf: blockedDirectory) == Data([42]))
    }

    @Test func aSymlinkedSchemaDirectoryCannotRedirectCleanupIntoAnotherFolder() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outside = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let sentinel = outside.appendingPathComponent("s-" + UUID().uuidString.lowercased())
        try Data([42]).write(to: sentinel)
        try Data("CloakRoll thumbnail cache schema 1\n".utf8).write(to: outside.appendingPathComponent(".owner"))
        let schema = directory.appendingPathComponent("CloakRollThumbnails-v1")
        try FileManager.default.createSymbolicLink(at: schema, withDestinationURL: outside)
        let pipeline = ThumbnailPipeline(cacheDirectory: directory)
        await pipeline.setSession(UUID())
        #expect(try Data(contentsOf: sentinel) == Data([42]))
        #expect(await pipeline.metrics().diskFailures > 0)
    }

    @Test func aSymlinkedCacheEntryIsRemovedWithoutReadingOrOverwritingItsTarget() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sentinel = directory.appendingPathComponent("outside.txt")
        try Data([42]).write(to: sentinel)
        let session = UUID()
        let pipeline = ThumbnailPipeline(cacheDirectory: directory, configuration: .init(memoryByteLimit: 0))
        await pipeline.setSession(session)
        let resource = key("../../outside.txt", session: session)
        _ = try await pipeline.data(for: resource) { Data([1]) }
        let file = try diskFile(resource, directory: directory)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: sentinel)
        #expect(try await pipeline.data(for: resource) { Data([2]) } == Data([2]))
        #expect(try Data(contentsOf: sentinel) == Data([42]))
        #expect(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
        #expect(await pipeline.metrics().sourceLoads == 2)
    }

    @Test func failedSessionEvictionDoesNotClaimFreedCapacityOrKeepWriting() async throws {
        let directory = try temporaryCache()
        let session = UUID()
        let schema = directory.appendingPathComponent("CloakRollThumbnails-v1")
            .appendingPathComponent("s-" + session.uuidString.lowercased())
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: schema.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let pipeline = ThumbnailPipeline(cacheDirectory: directory, configuration: .init(memoryByteLimit: 0))
        await pipeline.setSession(session)
        _ = try await pipeline.data(for: key("old", session: session)) { Data([1]) }
        let previous = await pipeline.metrics()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: schema.path)
        let next = UUID()
        await pipeline.setSession(next)
        #expect(try await pipeline.data(for: key("new", session: next)) { Data([2]) } == Data([2]))
        let after = await pipeline.metrics()
        #expect(after.diskFailures > previous.diskFailures)
        #expect(after.diskBytes == previous.diskBytes)
        #expect(after.diskItems == previous.diskItems)
        #expect(FileManager.default.fileExists(atPath: try diskFile(key("new", session: next), directory: directory).path) == false)
    }

    @Test func replacingAnActiveNamespaceWithASymlinkCannotRedirectReadsOrWrites() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = UUID()
        let pipeline = ThumbnailPipeline(cacheDirectory: directory, configuration: .init(memoryByteLimit: 0))
        await pipeline.setSession(session)
        let resource = key("source", session: session)
        _ = try await pipeline.data(for: resource) { Data([1]) }
        let file = try diskFile(resource, directory: directory)
        let namespace = file.deletingLastPathComponent()
        try FileManager.default.moveItem(at: namespace, to: directory.appendingPathComponent("original-namespace"))
        let outside = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let externalFile = outside.appendingPathComponent(file.lastPathComponent)
        let externalData = try #require(ThumbnailDiskCodec.encode(Data([42]), key: resource))
        try externalData.write(to: externalFile)
        try FileManager.default.createSymbolicLink(at: namespace, withDestinationURL: outside)
        #expect(try await pipeline.data(for: resource) { Data([2]) } == Data([2]))
        #expect(try Data(contentsOf: externalFile) == externalData)
        #expect(await pipeline.metrics().diskHits == 0)
        #expect(await pipeline.metrics().diskFailures > 0)
    }
}
