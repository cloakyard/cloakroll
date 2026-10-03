import BackupEngine
@testable import BackupPersistence
import Foundation
import GRDB
import MediaModels
import Testing

@Suite("Backup preparation cancellation")
struct BackupRegistrationCancellationTests {
    @Test(arguments: [false, true])
    func anAlreadyCancelledPreparationCreatesNoRowsOrSourceWork(emptySelection: Bool) async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = HistoryFixture()
        let identity = try fixture.identity()
        let source = PreparationSourceProbe()
        let error = await Task { () -> (any Error)? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await store.beginSession(
                    device: fixture.device, destinationID: fixture.destinationID, sourceSessionID: fixture.sourceSessionID,
                    assets: emptySelection ? [] : fixture.assets, identity: identity
                )
                _ = try await BackupEngine().run(
                    assets: fixture.assets, sessionID: fixture.sourceSessionID, destination: directory.url
                ) { _, _ in
                    await source.started()
                    throw CancellationError()
                }
                return nil
            } catch { return error }
        }.value
        #expect(error is CancellationError)
        #expect(await source.starts == 0)
        #expect(try await store.recentSessions().isEmpty)
        try await directory.database().read { db in
            for table in ["device", "destination", "asset", "resource", "backup_session", "session_resource",
                          "backup_record", "backup_journal"] {
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)")
                #expect(count == 0)
            }
        }
    }

    @Test(arguments: [PreparationShape.catalog, .assets, .resources])
    func cancellationDuringPreparationStopsAtTheNextCheckpoint(shape: PreparationShape) async throws {
        let fixture = RegistrationFixture(shape: shape)
        // The internal check seam cancels the real task after work has started, without sleeps
        // or a public production hook. It covers a large catalog with a small selection, many
        // selected assets, and a single asset with many original companions independently.
        let cancelled = await Task {
            var checkpoints = 0
            do {
                _ = try BackupRegistration(
                    device: fixture.device, sourceSessionID: fixture.sessionID,
                    assets: fixture.assets, identity: fixture.identity
                ) {
                    checkpoints += 1
                    if checkpoints == fixture.cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
                    try Task.checkCancellation()
                }
                return false
            } catch is CancellationError {
                return checkpoints == fixture.cancelAt
            } catch { return false }
        }.value
        #expect(cancelled)
    }

    @Test func aNonCancelledPreparationStillRegistersEveryComponent() async throws {
        let directory = HistoryDirectory()
        defer { directory.remove() }
        let store = try await BackupStore(databaseURL: directory.databaseURL)
        let fixture = RegistrationFixture(shape: .resources)
        let id = try await store.beginSession(
            device: fixture.device, destinationID: UUID(), sourceSessionID: fixture.sessionID,
            assets: fixture.assets, identity: fixture.identity
        )
        let session = try #require(try await store.recentSessions().first)
        #expect(session.id == id)
        #expect(session.totalAssets == 1)
        #expect(session.totalResources == 100)
        #expect(session.verifiedResources == 0)
        #expect(session.status == .running)
    }
}

private actor PreparationSourceProbe {
    private(set) var starts = 0
    func started() { starts += 1 }
}

enum PreparationShape: Sendable { case catalog, assets, resources }

private struct RegistrationFixture: Sendable {
    let device = ConnectedDevice(identity: DeviceIdentity(kind: .persistent, value: "fixture-device"), name: "iPhone")
    let sessionID = UUID()
    let assets: [MediaAsset]
    let identity: BackupCatalogIdentity
    let cancelAt: Int

    init(shape: PreparationShape) {
        let assetCount = shape == .resources ? 1 : 100
        let resourceCount = shape == .resources ? 100 : 1
        var assets: [MediaAsset] = []
        var identities: [String: BackupAssetIdentity] = [:]
        for index in 0..<assetCount {
            let assetID = "asset-\(index)"
            var resources: [MediaResource] = []
            var resourceIdentities: [String: BackupResourceIdentity] = [:]
            for component in 0..<resourceCount {
                let resourceID = "resource-\(index)-\(component)"
                resources.append(MediaResource(id: resourceID, filename: "\(resourceID).HEIC", byteCount: 3))
                resourceIdentities[resourceID] = BackupResourceIdentity(
                    resourceID: resourceID, canonical: resourceID,
                    digest: HistoryFixture.digest(Data(resourceID.utf8)), isReusableAcrossConnections: true
                )
            }
            assets.append(MediaAsset(id: assetID, deviceID: device.id, resources: resources, kind: .photo, createdAt: nil))
            identities[assetID] = BackupAssetIdentity(
                assetID: assetID, canonical: assetID, digest: HistoryFixture.digest(Data(assetID.utf8)),
                isReusableAcrossConnections: true, resources: resourceIdentities
            )
        }
        self.assets = shape == .catalog ? Array(assets.prefix(1)) : assets
        identity = BackupCatalogIdentity(deviceKey: device.id, sessionID: sessionID, assets: identities)
        cancelAt = shape == .assets ? assetCount + 20 : 20
    }
}
