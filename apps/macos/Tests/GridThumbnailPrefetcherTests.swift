import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@MainActor
struct GridThumbnailPrefetcherTests {
    @Test func oneWorkerWarmsTheTwoUncreatedRowsAndStopsAtTheirBoundary() async {
        let prefetcher = GridThumbnailPrefetcher()
        let source = PrefetchProbe()
        await prefetcher.prepare(sections: sections(), columns: 2) { try await source.load($0.id) }
        prefetcher.setVisible(true, assetID: "0")
        prefetcher.setVisible(true, assetID: "1")
        for id in ["2", "3", "4", "5"] {
            await source.waitForStart(id)
            #expect(await source.maximumActive == 1)
            await source.finish(id)
        }
        prefetcher.stop()
        #expect(await source.started == ["2", "3", "4", "5"])
    }

    @Test func visibleArrivalKeepsItsSharedPrefetchAlive() async {
        let prefetcher = GridThumbnailPrefetcher()
        let source = PrefetchProbe()
        await prefetcher.prepare(sections: sections(), columns: 2) { try await source.load($0.id) }
        prefetcher.setVisible(true, assetID: "0")
        await source.waitForStart("2")
        prefetcher.setVisible(true, assetID: "2")
        prefetcher.setVisible(false, assetID: "0")
        await source.finish("2")
        await source.waitForStart("4")
        #expect(await source.cancelled.contains("2") == false)
        prefetcher.stop()
        await source.waitForCancellation("4")
    }

    @Test func movingFarAwayCancelsObsoleteWorkAndStartsTheNewNeighbors() async {
        let prefetcher = GridThumbnailPrefetcher()
        let source = PrefetchProbe()
        await prefetcher.prepare(sections: sections(), columns: 2) { try await source.load($0.id) }
        prefetcher.setVisible(true, assetID: "0")
        await source.waitForStart("2")
        prefetcher.setVisible(false, assetID: "0")
        prefetcher.setVisible(true, assetID: "10")
        await source.waitForCancellation("2")
        await source.waitForStart("12")
        prefetcher.stop()
        await source.waitForCancellation("12")
    }

    @Test func pauseAndResumePreserveGeometryWithoutNewVisibilityCallbacks() async {
        let prefetcher = GridThumbnailPrefetcher()
        let first = PrefetchProbe()
        await prefetcher.prepare(sections: sections(), columns: 2) { try await first.load($0.id) }
        prefetcher.setVisible(true, assetID: "0")
        await first.waitForStart("2")
        prefetcher.pause()
        await first.waitForCancellation("2")
        let resumed = PrefetchProbe()
        await prefetcher.prepare(sections: sections(), columns: 2) { try await resumed.load($0.id) }
        await resumed.waitForStart("2")
        prefetcher.stop()
        await resumed.waitForCancellation("2")
    }

    @Test func changedCatalogAndColumnsRetireOldConsumerAndUseTheNewPlan() async {
        let prefetcher = GridThumbnailPrefetcher()
        let old = PrefetchProbe()
        await prefetcher.prepare(sections: sections(), columns: 2) { try await old.load($0.id) }
        prefetcher.setVisible(true, assetID: "0")
        await old.waitForStart("2")
        let current = PrefetchProbe()
        let filtered = [MediaSection(id: "filtered", date: nil, assets: (0..<8).map { prefetchAsset(String($0 * 2)) })]
        await prefetcher.prepare(sections: filtered, columns: 3) { try await current.load($0.id) }
        await old.waitForCancellation("2")
        await current.waitForStart("6")
        prefetcher.stop()
        await current.waitForCancellation("6")
    }

    @Test func alreadyCancelledPreparationCannotResetCurrentWorker() async {
        let prefetcher = GridThumbnailPrefetcher()
        let source = PrefetchProbe()
        await prefetcher.prepare(sections: sections(), columns: 2) { try await source.load($0.id) }
        prefetcher.setVisible(true, assetID: "0")
        await source.waitForStart("2")
        let cancelled = Task {
            await prefetcher.prepare(sections: [], columns: 1) { _ in Issue.record("Cancelled preparation ran") }
        }
        cancelled.cancel()
        await cancelled.value
        await source.finish("2")
        await source.waitForStart("3")
        #expect(await source.cancelled.isEmpty)
        prefetcher.stop()
        await source.waitForCancellation("3")
    }

    @Test func cancelledOldWorkCompletingLateCannotClearItsReplacement() async {
        let prefetcher = GridThumbnailPrefetcher()
        let old = PrefetchProbe(honorsCancellation: false)
        await prefetcher.prepare(sections: sections(), columns: 2) { try await old.load($0.id) }
        prefetcher.setVisible(true, assetID: "0")
        await old.waitForStart("2")
        let current = PrefetchProbe()
        await prefetcher.prepare(sections: sections(), columns: 3) { try await current.load($0.id) }
        await current.waitForStart("3")
        await old.finish("2")
        await current.finish("3")
        await current.waitForStart("4")
        #expect(await current.started == ["3", "4"])
        prefetcher.stop()
        await current.waitForCancellation("4")
    }

    private func sections() -> [MediaSection] {
        [MediaSection(id: "section", date: nil, assets: (0..<20).map { prefetchAsset(String($0)) })]
    }
}

private actor PrefetchProbe {
    private let honorsCancellation: Bool
    private(set) var started: [String] = []
    private(set) var cancelled: Set<String> = []
    private(set) var maximumActive = 0
    private var pending: [String: CheckedContinuation<Void, Error>] = [:]
    private var starts: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var cancellations: [String: [CheckedContinuation<Void, Never>]] = [:]

    init(honorsCancellation: Bool = true) { self.honorsCancellation = honorsCancellation }

    func load(_ id: String) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                started.append(id)
                maximumActive = max(maximumActive, pending.count)
                starts.removeValue(forKey: id)?.forEach { $0.resume() }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }

    func finish(_ id: String) { pending.removeValue(forKey: id)?.resume() }

    func waitForStart(_ id: String) async {
        guard !started.contains(id) else { return }
        await withCheckedContinuation { starts[id, default: []].append($0) }
    }

    func waitForCancellation(_ id: String) async {
        guard !cancelled.contains(id) else { return }
        await withCheckedContinuation { cancellations[id, default: []].append($0) }
    }

    private func cancel(_ id: String) {
        cancelled.insert(id)
        if honorsCancellation { pending.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
        cancellations.removeValue(forKey: id)?.forEach { $0.resume() }
    }
}
