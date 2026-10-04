import Foundation
import MediaModels

/// One speculative consumer at a time warms the next rows without retaining offscreen cell images.
/// Visible requests still enter the shared pipeline independently with its higher priority.
@MainActor
final class GridThumbnailPrefetcher {
    typealias Prefetch = @MainActor (MediaAsset) async throws -> Void

    private var plan: GridThumbnailPrefetchPlan?
    private var visibleIDs: Set<String> = []
    private var attempted: Set<String> = []
    private var desired: [MediaAsset] = []
    private var activeID: String?
    private var prefetch: Prefetch?
    private var worker: Task<Void, Never>?
    private var update: Task<Void, Never>?
    private var generation = UUID()

    func prepare(sections: [MediaSection], columns: Int, prefetch: @escaping Prefetch) async {
        guard !Task.isCancelled else { return }
        reset(keepVisibility: true)
        let generation = generation
        let preparation = Task.detached(priority: .userInitiated) {
            try GridThumbnailPrefetchPlan(sections: sections, columns: columns)
        }
        do {
            let plan = try await withTaskCancellationHandler {
                try await preparation.value
            } onCancel: { preparation.cancel() }
            try Task.checkCancellation()
            guard self.generation == generation else { return }
            self.plan = plan
            self.prefetch = prefetch
            visibleIDs = visibleIDs.filter { plan.contains($0) }
            reconcile()
        } catch {
            // A newer catalog/layout owns the next plan. Never publish partial indexing.
        }
    }

    func setVisible(_ visible: Bool, assetID: String) {
        let changed = visible ? visibleIDs.insert(assetID).inserted : visibleIDs.remove(assetID) != nil
        guard changed else { return }
        // Coalesce one layout turn's cell callbacks before selecting nearby rows.
        update?.cancel()
        update = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    func pause() { reset(keepVisibility: true) }
    func stop() { reset(keepVisibility: false) }

    private func reset(keepVisibility: Bool) {
        generation = UUID()
        update?.cancel()
        update = nil
        worker?.cancel()
        worker = nil
        activeID = nil
        plan = nil
        prefetch = nil
        desired = []
        attempted = []
        if !keepVisibility { visibleIDs = [] }
    }

    private func reconcile() {
        guard let plan else { return }
        desired = plan.candidates(visibleIDs: visibleIDs)
        let desiredIDs = Set(desired.map(\.id))
        attempted.formIntersection(desiredIDs)
        if let activeID, !desiredIDs.contains(activeID), !visibleIDs.contains(activeID) {
            // Cancellation releases our consumer promptly; it never frees an actual USB slot.
            worker?.cancel()
            worker = nil
            self.activeID = nil
        }
        startNext()
    }

    private func startNext() {
        guard worker == nil, let prefetch, let asset = desired.first(where: { !attempted.contains($0.id) }) else { return }
        let generation = generation
        activeID = asset.id
        worker = Task { [weak self] in
            do { try await prefetch(asset) } catch { }
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            self.attempted.insert(asset.id)
            self.activeID = nil
            self.worker = nil
            self.startNext()
        }
    }
}
