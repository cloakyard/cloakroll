import Foundation
import Testing
@testable import ThumbnailPipeline

@Suite("Encoded thumbnail caches")
struct ThumbnailCacheTests {
    @Test func memoryEvictsLeastRecentlyUsedEntriesAtExactByteAndItemLimits() async throws {
        let session = UUID()
        let pipeline = ThumbnailPipeline(configuration: .init(memoryByteLimit: 6, memoryItemLimit: 2))
        await pipeline.setSession(session)
        let data = Data([1, 2, 3])
        _ = try await pipeline.data(for: key("a", session: session)) { data }
        _ = try await pipeline.data(for: key("b", session: session)) { data }
        _ = try await pipeline.data(for: key("a", session: session)) { throw PipelineTestError.unexpectedLoad }
        _ = try await pipeline.data(for: key("c", session: session)) { data }
        #expect(await pipeline.metrics().memoryBytes == 6)
        #expect(await pipeline.metrics().memoryItems == 2)
        _ = try await pipeline.data(for: key("a", session: session)) { throw PipelineTestError.unexpectedLoad }
        _ = try await pipeline.data(for: key("b", session: session)) { data }
        #expect(await pipeline.metrics().sourceLoads == 4)
        #expect(await pipeline.metrics().memoryBytes == 6)
    }

    @Test func resourceVersionAndPixelSizeAreSeparateCacheIdentities() async throws {
        let session = UUID()
        let pipeline = ThumbnailPipeline()
        await pipeline.setSession(session)
        let first = key("same", session: session, version: "old", pixels: 256)
        let changed = key("same", session: session, version: "new", pixels: 256)
        let larger = key("same", session: session, version: "new", pixels: 512)
        #expect(try JSONDecoder().decode(ThumbnailKey.self, from: JSONEncoder().encode(first)) == first)
        #expect(try await pipeline.data(for: first) { Data([1]) } == Data([1]))
        #expect(try await pipeline.data(for: changed) { Data([2]) } == Data([2]))
        #expect(try await pipeline.data(for: larger) { Data([3]) } == Data([3]))
        #expect(await pipeline.metrics().sourceLoads == 3)
        #expect(await pipeline.metrics().memoryItems == 3)
    }

    @Test func diskHitsSurviveMemoryEvictionAndDiskUsesExactFileCosts() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = UUID()
        let pipeline = ThumbnailPipeline(cacheDirectory: directory, configuration: .init(memoryByteLimit: 3, memoryItemLimit: 1))
        await pipeline.setSession(session)
        let data = Data([1, 2, 3])
        let first = key("a", session: session)
        let second = key("b", session: session)
        _ = try await pipeline.data(for: first) { data }
        _ = try await pipeline.data(for: second) { data }
        #expect(try await pipeline.data(for: first) { throw PipelineTestError.unexpectedLoad } == data)
        let firstSize = try #require(diskFile(first, directory: directory).resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let secondSize = try #require(diskFile(second, directory: directory).resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(await pipeline.metrics().diskHits == 1)
        #expect(await pipeline.metrics().diskBytes == firstSize + secondSize)
        #expect(await pipeline.metrics().memoryBytes == 3)
    }

    @Test func diskEvictionUsesReadRecencyAndItsItemLimit() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = UUID()
        let pipeline = ThumbnailPipeline(cacheDirectory: directory, configuration: .init(memoryByteLimit: 0, diskItemLimit: 2))
        await pipeline.setSession(session)
        let data = Data([1])
        let first = key("a", session: session)
        let second = key("b", session: session)
        let third = key("c", session: session)
        _ = try await pipeline.data(for: first) { data }
        _ = try await pipeline.data(for: second) { data }
        _ = try await pipeline.data(for: first) { throw PipelineTestError.unexpectedLoad }
        _ = try await pipeline.data(for: third) { data }
        #expect(FileManager.default.fileExists(atPath: try diskFile(first, directory: directory).path))
        #expect(FileManager.default.fileExists(atPath: try diskFile(second, directory: directory).path) == false)
        #expect(await pipeline.metrics().diskItems == 2)
        _ = try await pipeline.data(for: second) { data }
        #expect(await pipeline.metrics().sourceLoads == 4)
    }

    @Test func diskByteLimitIncludesHeaderAndPayload() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = UUID()
        let first = key("a", session: session)
        let second = key("b", session: session)
        let data = Data(repeating: 9, count: 100)
        let cost = try #require(ThumbnailDiskCodec.encode(data, key: first)).count
        let pipeline = ThumbnailPipeline(
            cacheDirectory: directory, configuration: .init(memoryByteLimit: 0, diskByteLimit: cost * 2 - 1)
        )
        await pipeline.setSession(session)
        _ = try await pipeline.data(for: first) { data }
        _ = try await pipeline.data(for: second) { data }
        #expect(await pipeline.metrics().diskItems == 1)
        #expect(await pipeline.metrics().diskBytes == cost)
        #expect(FileManager.default.fileExists(atPath: try diskFile(first, directory: directory).path) == false)
    }

    @Test func corruptAndMissingFilesBecomeMissesAndAreReplacedWithFreshSourceData() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = UUID()
        let pipeline = ThumbnailPipeline(cacheDirectory: directory, configuration: .init(memoryByteLimit: 0))
        await pipeline.setSession(session)
        let resource = key("source", session: session)
        _ = try await pipeline.data(for: resource) { Data([1, 2, 3]) }
        let file = try diskFile(resource, directory: directory)
        var corrupted = try Data(contentsOf: file)
        corrupted[corrupted.count - 1] ^= 0xff
        try corrupted.write(to: file)
        #expect(try await pipeline.data(for: resource) { Data([4]) } == Data([4]))
        #expect(await pipeline.metrics().sourceLoads == 2)
        #expect(try await pipeline.data(for: resource) { throw PipelineTestError.unexpectedLoad } == Data([4]))
        try FileManager.default.removeItem(at: file)
        #expect(try await pipeline.data(for: resource) { Data([5]) } == Data([5]))
        #expect(await pipeline.metrics().sourceLoads == 3)
        #expect(await pipeline.metrics().diskHits == 1)
    }

    @Test func filesLargerThanRecordedCostsAreRejectedWithoutUnboundedReads() async throws {
        let directory = try temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = UUID()
        let pipeline = ThumbnailPipeline(cacheDirectory: directory, configuration: .init(memoryByteLimit: 0, maximumDataBytes: 8))
        await pipeline.setSession(session)
        let resource = key("source", session: session)
        _ = try await pipeline.data(for: resource) { Data([1]) }
        try Data(repeating: 9, count: 128 * 1_024).write(to: diskFile(resource, directory: directory))
        #expect(try await pipeline.data(for: resource) { Data([2]) } == Data([2]))
        #expect(await pipeline.metrics().sourceLoads == 2)
    }
}
