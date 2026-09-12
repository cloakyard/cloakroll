import BackupEngine
import Foundation
import MediaModels

/// Phase 5 evidence is deliberately scoped to the current connection and chosen destination.
/// Preview cache identities never participate in original-file matching.
struct LibraryBackupHistory {
    struct Scope: Hashable {
        let sessionID: UUID
        let destinationID: UUID
    }

    private struct Entry {
        var records: [VerifiedBackupResource] = []
        var completed: [String: MediaAsset] = [:]
        var dates: [String: Date] = [:]
    }

    private struct ResourceKey: Hashable {
        let assetID: String
        let resourceID: String
    }

    private var entries: [Scope: Entry] = [:]

    func records(in scope: Scope) -> [VerifiedBackupResource] { entries[scope]?.records ?? [] }

    mutating func retainAssets(_ identifiers: Set<String>, in scope: Scope) {
        guard var entry = entries[scope] else { return }
        entry.records.removeAll { !identifiers.contains($0.assetID) }
        entry.completed = entry.completed.filter { identifiers.contains($0.key) }
        entry.dates = entry.dates.filter { identifiers.contains($0.key) }
        entries[scope] = entry
    }

    mutating func apply(_ result: BackupResult, assets: [MediaAsset], scope: Scope) {
        var entry = entries[scope] ?? Entry()
        // Keep earlier candidates if a retry stops before visiting them. The engine must freshly
        // verify their full source signature, destination identity, size and digest before reuse.
        let finalized = Set(result.records.map { ResourceKey(assetID: $0.assetID, resourceID: $0.resourceID) })
        entry.records.removeAll { finalized.contains(ResourceKey(assetID: $0.assetID, resourceID: $0.resourceID)) }
        entry.records.append(contentsOf: result.records)
        let verificationDates = result.records.reduce(into: [String: Date]()) { dates, record in
            dates[record.assetID] = max(dates[record.assetID] ?? .distantPast, record.verifiedAt)
        }
        for asset in assets {
            entry.completed[asset.id] = nil
            entry.dates[asset.id] = nil
            if result.snapshot.completedAssetIDs.contains(asset.id) {
                entry.completed[asset.id] = asset
                entry.dates[asset.id] = verificationDates[asset.id]
            }
        }
        entries[scope] = entry
    }

    func projection(assets: [MediaAsset], scope: Scope) -> (statuses: [String: BackupStatus], dates: [String: Date]) {
        guard let entry = entries[scope] else { return ([:], [:]) }
        var statuses: [String: BackupStatus] = [:]
        var dates: [String: Date] = [:]
        for asset in assets where entry.completed[asset.id] == asset {
            statuses[asset.id] = .backedUp
            dates[asset.id] = entry.dates[asset.id]
        }
        return (statuses, dates)
    }
}
