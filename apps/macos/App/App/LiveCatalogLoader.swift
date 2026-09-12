import Foundation
import MediaCatalog
import MediaModels

struct PreparedDeviceCatalog: Sendable {
    let source: DeviceMediaSnapshot
    let assets: [MediaAsset]
    let lookup: [String: MediaAsset]
    let thumbnailReuseIDs: [String: String]
}

/// Serializes background assembly while retaining only the latest pending full catalog. USB
/// callbacks never wait for sorting/grouping, and obsolete work cannot replace a newer session.
@MainActor
final class LiveCatalogLoader {
    private var consumer: Task<Void, Never>?
    private var preparation: Task<Void, Never>?
    private var pending: DeviceMediaSnapshot?
    private var sessionID: UUID?
    private var retiredSessions: Set<UUID> = []
    private var latestRevision: UInt64?
    private var isStopped = false
    private let onReceive: (DeviceMediaSnapshot) -> Void
    private let onPrepared: (PreparedDeviceCatalog) -> Void

    init(
        source: any DeviceMediaSource,
        onReceive: @escaping (DeviceMediaSnapshot) -> Void,
        onPrepared: @escaping (PreparedDeviceCatalog) -> Void
    ) {
        self.onReceive = onReceive
        self.onPrepared = onPrepared
        let catalogs = source.catalogs
        consumer = Task { [weak self] in
            for await catalog in catalogs {
                guard !Task.isCancelled else { return }
                self?.receive(catalog)
            }
        }
    }

    func stop() {
        isStopped = true
        consumer?.cancel()
        consumer = nil
        preparation?.cancel()
        preparation = nil
        pending = nil
    }

    private func receive(_ catalog: DeviceMediaSnapshot) {
        guard !isStopped, !retiredSessions.contains(catalog.sessionID) else { return }
        if sessionID != catalog.sessionID {
            if let sessionID { retiredSessions.insert(sessionID) }
            sessionID = catalog.sessionID
            latestRevision = nil
        }
        if let latestRevision, catalog.revision <= latestRevision { return }
        latestRevision = catalog.revision
        pending = catalog
        onReceive(catalog)
        guard preparation == nil else { return }
        preparation = Task { [weak self] in await self?.preparePending() }
    }

    private func preparePending() async {
        while !Task.isCancelled, !isStopped, let source = pending {
            pending = nil
            let prepared = await Task.detached(priority: .userInitiated) {
                let assets = CatalogAssembler.assemble(records: source.records)
                let lookup = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
                let reuseIDs = source.state == .complete ? ThumbnailReuseIndex.make(records: source.records) : [:]
                return PreparedDeviceCatalog(source: source, assets: assets, lookup: lookup, thumbnailReuseIDs: reuseIDs)
            }.value
            guard !Task.isCancelled, !isStopped else { return }
            if source.sessionID == sessionID, source.revision == latestRevision {
                onPrepared(prepared)
            }
        }
        preparation = nil
    }
}
