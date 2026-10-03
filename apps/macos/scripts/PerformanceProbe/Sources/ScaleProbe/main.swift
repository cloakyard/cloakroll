import BackupEngine
import BackupPersistence
import Darwin
import Foundation
import GRDB
import MediaCatalog
import MediaModels

func rss() -> Int64 {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Int64(usage.ru_maxrss)
}
func log(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}
func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let d = start.duration(to: .now).components
    return Double(d.seconds) * 1_000 + Double(d.attoseconds) / 1e15
}
struct Fixture: Sendable {
    let device = ConnectedDevice(identity: DeviceIdentity(kind: .persistent, value: "generated-scale-device"), name: "Generated fixture")
    let session = UUID()
    var assets: [MediaAsset] = []
    var records: [SourceMediaRecord] = []
    init(count: Int, prefix: String) {
        assets.reserveCapacity(count)
        records.reserveCapacity(count + count / 4)
        for i in 0..<count {
            let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(i * 61))
            let live = i.isMultiple(of: 4)
            let stillID = "\(prefix)-\(i)-still"
            let motionID = "\(prefix)-\(i)-motion"
            let filename = String(format: "IMG_%07d.HEIC", i)
            var resources = [MediaResource(id: stillID, filename: filename, byteCount: 4_000_000, modifiedAt: date)]
            records.append(SourceMediaRecord(
                id: stillID, deviceID: device.id, filename: filename, contextPath: ["DCIM", "100APPLE"],
                uti: "public.heic", byteCount: 4_000_000, createdAt: date, modifiedAt: date,
                pixelWidth: 4032, pixelHeight: 3024, originatingAssetID: "generated-\(i)",
                sidecarIDs: live ? [motionID] : []
            ))
            if live {
                let filename = String(format: "IMG_%07d.MOV", i)
                resources.append(MediaResource(id: motionID, filename: filename, byteCount: 5_000_000, modifiedAt: date))
                records.append(SourceMediaRecord(
                    id: motionID, deviceID: device.id, filename: filename, contextPath: ["DCIM", "100APPLE"],
                    uti: "com.apple.quicktime-movie", byteCount: 5_000_000, createdAt: date, modifiedAt: date,
                    pixelWidth: 1920, pixelHeight: 1440, duration: 3, originatingAssetID: "generated-\(i)"
                ))
            }
            assets.append(MediaAsset(id: "\(prefix)-\(i)", deviceID: device.id, resources: resources,
                kind: live ? .livePhoto : .photo, createdAt: date, pixelWidth: 4032, pixelHeight: 3024))
        }
    }
    var source: DeviceMediaSnapshot {
        DeviceMediaSnapshot(sessionID: session, deviceID: device.id, revision: 1, records: records, state: .complete)
    }
}

@main struct Main {
    static func main() async throws {
        if CommandLine.arguments.contains("--compatibility") {
            let fixture = Fixture(count: 3, prefix: "first")
            let identity = try BackupIdentityIndex.make(source: fixture.source, assets: fixture.assets, deviceIdentity: fixture.device.identity)
            for key in identity.assets.keys.sorted() {
                let asset = identity.assets[key]!
                log(["asset": key, "digest": asset.digest, "resources": asset.resources.mapValues(\.digest)])
            }
            log(["thumbnails": ThumbnailReuseIndex.make(records: fixture.records)])
            for asset in fixture.assets {
                for resource in asset.resources { log(["source": resource.id, "digest": try BackupEngine.sourceSignature(asset: asset, resource: resource)]) }
            }
            return
        }
        guard let count = Int(CommandLine.arguments.dropFirst().first ?? "10000"),
              [10_000, 50_000, 100_000].contains(count) else {
            throw ProbeError.invalidCount
        }
        let fixture = Fixture(count: count, prefix: "first")
        log(["phase": "fixture", "assets": fixture.assets.count, "resources": fixture.records.count, "peakRSS": rss()])
        let projector = CatalogProjector()
        for run in 0..<3 {
            let start = ContinuousClock.now
            let result = try await projector.project(assets: fixture.assets, statuses: [:], backupDates: [:], query: CatalogQuery())
            precondition(result.totalCount == count)
            log(["phase": "projection", "run": run, "milliseconds": elapsed(start), "peakRSS": rss()])
        }
        var identity: BackupCatalogIdentity?
        for run in 0..<3 {
            identity = nil
            let start = ContinuousClock.now
            identity = try await Task.detached {
                try BackupIdentityIndex.make(source: fixture.source, assets: fixture.assets, deviceIdentity: fixture.device.identity)
            }.value
            precondition(identity!.assets.values.allSatisfy(\.isReusableAcrossConnections))
            log(["phase": "identity", "run": run, "milliseconds": elapsed(start), "peakRSS": rss()])
        }
        let localIdentity = identity!
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloakroll-scale-\(count)-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let dbURL = folder.appendingPathComponent("History.sqlite")
        let destination = UUID()
        let store = try await BackupStore(databaseURL: dbURL)
        let start = ContinuousClock.now
        let session = try await store.beginSession(device: fixture.device, destinationID: destination,
            sourceSessionID: fixture.session, assets: fixture.assets, identity: localIdentity)
        log(["phase": "register", "milliseconds": elapsed(start), "peakRSS": rss()])
        let emptyStart = ContinuousClock.now
        let empty = try await store.candidates(deviceKey: fixture.device.id, destinationID: destination, identity: localIdentity)
        precondition(empty.isEmpty)
        log(["phase": "emptyCandidates", "milliseconds": elapsed(emptyStart), "peakRSS": rss()])
        // Generated metadata only. Seed committed record-shaped rows to measure public read/matching
        // independently of per-original fsync and transfer costs. These are not media-verification tests.
        let queue = try DatabaseQueue(path: dbURL.path)
        try await queue.write { db in
            try db.execute(sql: """
                INSERT INTO backup_record(session_id, resource_id, destination_id, device_id, source_session_id,
                    runtime_asset_id, runtime_resource_id, filename, relative_path, byte_count, sha256,
                    verified_at, source_modified_at, destination_identity, source_signature)
                SELECT s.session_id, s.resource_id, ?, ?, ?, s.runtime_asset_id, s.runtime_resource_id,
                    r.filename, '2026/10/' || r.filename, r.expected_bytes, ?, 1800000000, NULL, 'generated-root', s.source_signature
                FROM session_resource s JOIN resource r ON r.id = s.resource_id WHERE s.session_id = ?
                """, arguments: [destination.uuidString, fixture.device.id, fixture.session.uuidString,
                    String(repeating: "a", count: 64), session.uuidString])
        }
        for run in 0..<3 {
            let start = ContinuousClock.now
            let matches = try await store.candidates(deviceKey: fixture.device.id, destinationID: destination, identity: localIdentity)
            precondition(matches.count == fixture.records.count)
            log(["phase": "allCandidates", "run": run, "milliseconds": elapsed(start), "matches": matches.count, "peakRSS": rss()])
        }
        let singleID = fixture.assets[count / 2].id
        let single = BackupCatalogIdentity(deviceKey: localIdentity.deviceKey, sessionID: localIdentity.sessionID,
                                          assets: [singleID: localIdentity.assets[singleID]!])
        for run in 0..<3 {
            let start = ContinuousClock.now
            let matches = try await store.candidates(deviceKey: fixture.device.id, destinationID: destination, identity: single)
            precondition(matches.count == fixture.assets[count / 2].resources.count)
            log(["phase": "oneAssetCandidates", "run": run, "milliseconds": elapsed(start), "matches": matches.count, "peakRSS": rss()])
        }
        // Explain the per-resource asset completion lookup without changing production schema.
        try await queue.read { db in
            let plan = try Row.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN SELECT COUNT(*) = COUNT(b.id) FROM session_resource r LEFT JOIN backup_record b
                    ON b.session_id = r.session_id AND b.runtime_resource_id = r.runtime_resource_id
                WHERE r.session_id = ? AND r.runtime_asset_id = ?
                """, arguments: [session.uuidString, singleID])
            log(["phase": "completionQueryPlan", "detail": plan.map { $0["detail"] as String }])
        }
        let completionStart = ContinuousClock.now
        for _ in 0..<100 {
            _ = try await queue.read { db in
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) = COUNT(b.id) FROM session_resource r LEFT JOIN backup_record b
                        ON b.session_id = r.session_id AND b.runtime_resource_id = r.runtime_resource_id
                    WHERE r.session_id = ? AND r.runtime_asset_id = ?
                    """, arguments: [session.uuidString, singleID])
            }
        }
        log(["phase": "completionLookup100", "milliseconds": elapsed(completionStart), "peakRSS": rss()])
    }
}

private enum ProbeError: Error { case invalidCount }
