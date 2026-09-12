import Foundation
import Testing
@testable import ThumbnailPipeline

@Suite("Thumbnail sessions and source failures")
struct ThumbnailSessionTests {
    @Test func retiredLoadsRetainSlotsAndTheirLateResultsNeverEnterCaches() async throws {
        let firstSession = UUID()
        let secondSession = UUID()
        let pipeline = ThumbnailPipeline(configuration: .init(maximumActiveLoads: 1))
        let source = ControlledThumbnailSource()
        await pipeline.setSession(firstSession)
        let old = request("old", pipeline: pipeline, source: source, session: firstSession)
        try await eventually("old session load starts") { await source.started == ["old"] }
        let oldQueued = request("old-queued", pipeline: pipeline, source: source, session: firstSession)
        try await eventually("old demand queues") { await pipeline.metrics().queued == 1 }
        await pipeline.setSession(secondSession)
        await #expect(throws: ThumbnailPipelineError.staleSession) { try await old.value }
        await #expect(throws: ThumbnailPipelineError.staleSession) { try await oldQueued.value }
        #expect(await pipeline.metrics().active == 1)
        #expect(await pipeline.metrics().queued == 0)
        let current = request("current", pipeline: pipeline, source: source, session: secondSession)
        try await eventually("new demand waits for retired task completion") { await pipeline.metrics().queued == 1 }
        #expect(await source.started == ["old"])
        await source.finish("old", data: Data([9]))
        try await eventually("current task starts after late completion") { await source.started == ["old", "current"] }
        #expect(await pipeline.metrics().memoryItems == 0)
        await source.finish("current", data: Data([8]))
        #expect(try await current.value == Data([8]))
        await pipeline.setSession(firstSession)
        let reconnected = try await pipeline.data(for: key("old", session: firstSession)) { Data([7]) }
        #expect(reconnected == Data([7]))
        #expect(await pipeline.metrics().sourceLoads == 3)
    }

    @Test func retiringAndReusingTheSameSessionUUIDRejectsAnOlderGeneration() async throws {
        let session = UUID()
        let pipeline = ThumbnailPipeline(configuration: .init(maximumActiveLoads: 1))
        let source = ControlledThumbnailSource()
        await pipeline.setSession(session)
        let old = request("same", pipeline: pipeline, source: source, session: session)
        try await eventually("old generation starts") { await source.started.count == 1 }
        await pipeline.setSession(nil)
        await pipeline.setSession(session)
        await #expect(throws: ThumbnailPipelineError.staleSession) { try await old.value }
        let new = Task { try await pipeline.data(for: key("same", session: session)) { Data([7]) } }
        try await eventually("new generation waits independently") { await pipeline.metrics().queued == 1 }
        await source.finish("same", data: Data([9]))
        #expect(try await new.value == Data([7]))
        #expect(await pipeline.metrics().coalesced == 0)
        #expect(await pipeline.metrics().sourceLoads == 2)
    }

    @Test func missingSessionOrMismatchedKeyNeverLoadsSourceData() async {
        let pipeline = ThumbnailPipeline()
        let session = UUID()
        await #expect(throws: ThumbnailPipelineError.staleSession) {
            try await pipeline.data(for: key("first", session: session)) { Data([1]) }
        }
        await pipeline.setSession(UUID())
        await #expect(throws: ThumbnailPipelineError.staleSession) {
            try await pipeline.data(for: key("first", session: session)) { Data([1]) }
        }
        #expect(await pipeline.metrics().sourceLoads == 0)
    }

    @Test func failedEmptyAndOversizedResponsesRemainRetryableAndNeverEnterCaches() async throws {
        let session = UUID()
        let pipeline = ThumbnailPipeline(configuration: .init(maximumDataBytes: 3))
        await pipeline.setSession(session)
        let resource = key("retry", session: session)
        await #expect(throws: PipelineTestError.sourceFailure) {
            try await pipeline.data(for: resource) { throw PipelineTestError.sourceFailure }
        }
        await #expect(throws: ThumbnailPipelineError.emptyData) {
            try await pipeline.data(for: resource) { Data() }
        }
        await #expect(throws: ThumbnailPipelineError.oversizedData) {
            try await pipeline.data(for: resource) { Data([1, 2, 3, 4]) }
        }
        #expect(await pipeline.metrics().memoryItems == 0)
        #expect(await pipeline.metrics().failed == 3)
        #expect(try await pipeline.data(for: resource) { Data([1, 2, 3]) } == Data([1, 2, 3]))
        #expect(await pipeline.metrics().sourceLoads == 4)
    }

    @Test func cancellingPromotedVisibleDemandRestoresQueuedPrefetchOrder() async throws {
        let session = UUID()
        let pipeline = ThumbnailPipeline(configuration: .init(maximumActiveLoads: 1))
        let source = ControlledThumbnailSource()
        await pipeline.setSession(session)
        let blocker = request("blocker", pipeline: pipeline, source: source, session: session)
        try await eventually("blocker starts") { await source.started == ["blocker"] }
        let older = request("older", pipeline: pipeline, source: source, session: session, priority: .prefetch)
        try await eventually("older prefetch queues") { await pipeline.metrics().queued == 1 }
        let later = request("later", pipeline: pipeline, source: source, session: session, priority: .prefetch)
        try await eventually("later prefetch queues") { await pipeline.metrics().queued == 2 }
        let visible = request("later", pipeline: pipeline, source: source, session: session)
        try await eventually("later demand is promoted") { await pipeline.metrics().coalesced == 1 }
        visible.cancel()
        await #expect(throws: CancellationError.self) { try await visible.value }
        await source.finish("blocker")
        _ = try await blocker.value
        try await eventually("older prefetch starts first again") { await source.started.count == 2 }
        #expect(await source.started == ["blocker", "older"])
        await source.finish("older")
        _ = try await older.value
        try await eventually("later prefetch starts after older") { await source.started.count == 3 }
        await source.finish("later")
        _ = try await later.value
    }
}
