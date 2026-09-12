import Foundation
import Testing
@testable import ThumbnailPipeline

@Suite("Thumbnail demand scheduling")
struct ThumbnailSchedulingTests {
    @Test func sharedFetchHasIndependentConsumerCancellation() async throws {
        let session = UUID()
        let pipeline = ThumbnailPipeline()
        let source = ControlledThumbnailSource()
        await pipeline.setSession(session)
        let first = request("same", pipeline: pipeline, source: source, session: session)
        try await eventually("first source starts") { await source.started == ["same"] }
        let second = request("same", pipeline: pipeline, source: source, session: session)
        try await eventually("second demand coalesces") { await pipeline.metrics().coalesced == 1 }
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await pipeline.metrics().active == 1)
        await source.finish("same")
        #expect(try await second.value == Data([1, 2, 3]))
        let cached = try await pipeline.data(for: key("same", session: session)) { throw PipelineTestError.unexpectedLoad }
        #expect(cached == Data([1, 2, 3]))
        #expect(await pipeline.metrics().memoryHits == 1)
        #expect(await pipeline.metrics().sourceLoads == 1)
    }

    @Test func queuedDemandIsBoundedAndCancelledDemandNeverLaunches() async throws {
        let session = UUID()
        let pipeline = ThumbnailPipeline(configuration: .init(maximumQueuedRequests: 2))
        let source = ControlledThumbnailSource()
        await pipeline.setSession(session)
        let first = request("first", pipeline: pipeline, source: source, session: session)
        let second = request("second", pipeline: pipeline, source: source, session: session)
        try await eventually("two source loads start") { await source.started.count == 2 }
        let cancelled = request("cancelled", pipeline: pipeline, source: source, session: session)
        let queued = request("queued", pipeline: pipeline, source: source, session: session)
        try await eventually("queue reaches its bound") { await pipeline.metrics().queued == 2 }
        await #expect(throws: ThumbnailPipelineError.queueFull) {
            try await pipeline.data(for: key("overflow", session: session)) { Data([9]) }
        }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await pipeline.metrics().queued == 1)
        await source.finish("first")
        _ = try await first.value
        try await eventually("remaining queued source starts") { await source.started.contains("queued") }
        #expect(await source.started.contains("cancelled") == false)
        await source.finish("second")
        await source.finish("queued")
        _ = try await second.value
        _ = try await queued.value
        #expect(await pipeline.metrics().active == 0)
    }

    @Test func visibleDemandPromotesSharedQueuedPrefetch() async throws {
        let session = UUID()
        let pipeline = ThumbnailPipeline(configuration: .init(maximumActiveLoads: 1))
        let source = ControlledThumbnailSource()
        await pipeline.setSession(session)
        let blocker = request("blocker", pipeline: pipeline, source: source, session: session)
        try await eventually("blocker starts") { await source.started == ["blocker"] }
        let older = request("older", pipeline: pipeline, source: source, session: session, priority: .prefetch)
        try await eventually("older prefetch queues") { await pipeline.metrics().queued == 1 }
        let promoted = request("promoted", pipeline: pipeline, source: source, session: session, priority: .prefetch)
        try await eventually("second prefetch queues") { await pipeline.metrics().queued == 2 }
        let visible = request("promoted", pipeline: pipeline, source: source, session: session)
        try await eventually("visible demand promotes existing request") { await pipeline.metrics().coalesced == 1 }
        await source.finish("blocker")
        _ = try await blocker.value
        try await eventually("promoted item starts before older prefetch") { await source.started.count == 2 }
        #expect(await source.started == ["blocker", "promoted"])
        await source.finish("promoted")
        _ = try await promoted.value
        _ = try await visible.value
        try await eventually("older prefetch starts afterward") { await source.started.count == 3 }
        await source.finish("older")
        _ = try await older.value
    }

    @Test func atMostOnePrefetchStartsWhileVisibleWorkUsesTheOtherSlot() async throws {
        let session = UUID()
        let pipeline = ThumbnailPipeline()
        let source = ControlledThumbnailSource()
        await pipeline.setSession(session)
        let first = request("prefetch1", pipeline: pipeline, source: source, session: session, priority: .prefetch)
        try await eventually("first prefetch starts") { await source.started == ["prefetch1"] }
        let second = request("prefetch2", pipeline: pipeline, source: source, session: session, priority: .prefetch)
        try await eventually("second prefetch waits") { await pipeline.metrics().queued == 1 }
        let visible = request("visible", pipeline: pipeline, source: source, session: session)
        try await eventually("visible work takes reserved slot") { await source.started.count == 2 }
        #expect(await source.started == ["prefetch1", "visible"])
        await source.finish("visible")
        _ = try await visible.value
        #expect(await pipeline.metrics().active == 1)
        #expect(await pipeline.metrics().queued == 1)
        await source.finish("prefetch1")
        _ = try await first.value
        try await eventually("second prefetch starts after actual first completion") { await source.started.count == 3 }
        await source.finish("prefetch2")
        _ = try await second.value
    }

    @Test func activeWorkRetainsItsSlotAndCachesWhenEveryConsumerCancels() async throws {
        let session = UUID()
        let pipeline = ThumbnailPipeline(configuration: .init(maximumActiveLoads: 1))
        let source = ControlledThumbnailSource()
        await pipeline.setSession(session)
        let abandoned = request("abandoned", pipeline: pipeline, source: source, session: session)
        try await eventually("abandoned request starts") { await source.started.count == 1 }
        abandoned.cancel()
        await #expect(throws: CancellationError.self) { try await abandoned.value }
        let next = request("next", pipeline: pipeline, source: source, session: session)
        try await eventually("next waits for real completion") { await pipeline.metrics().queued == 1 }
        #expect(await pipeline.metrics().active == 1)
        #expect(await source.started == ["abandoned"])
        await source.finish("abandoned")
        try await eventually("next starts after completion") { await source.started.count == 2 }
        await source.finish("next")
        _ = try await next.value
        let data = try await pipeline.data(for: key("abandoned", session: session)) { throw PipelineTestError.unexpectedLoad }
        #expect(data == Data([1, 2, 3]))
        #expect(await pipeline.metrics().memoryHits == 1)
    }

    @Test func cancellationBeforeEnqueueNeverStartsSourceWork() async {
        let session = UUID()
        let pipeline = ThumbnailPipeline()
        await pipeline.setSession(session)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pipeline.data(for: key("cancelled", session: session)) { throw PipelineTestError.unexpectedLoad }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await pipeline.metrics().sourceLoads == 0)
        #expect(await pipeline.metrics().queued == 0)
    }
}
