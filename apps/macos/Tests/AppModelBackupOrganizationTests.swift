import BackupEngine
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Backup organization app wiring", .timeLimit(.minutes(1)))
@MainActor
struct AppModelBackupOrganizationTests {
    @Test func activeRunKeepsCapturedOrganizationAndNextRunUsesChangedPreference() async throws {
        let fixture = try BackupControllerFixture()
        let source = OrganizationLibrarySource()
        let model = AppModel(
            makeBrowser: { source }, preferences: LibraryPreferences(defaults: nil), backup: fixture.controller
        )
        model.startLive()
        defer { model.shutdown() }
        try await organizationWait { model.assets.count == 1 && model.backupSourceAvailable }
        let first = try #require(model.assets.first)

        model.backupOrganization = .singleFolder
        model.startBackup(assets: [first])
        try await organizationWait { source.isWaiting }
        #expect(fixture.controller.isBusy)
        // Exercise capture even if the preference changes programmatically while Settings is disabled.
        model.backupOrganization = .byDate
        source.finishFirstTransfer()
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == .completed)
        #expect(fixture.controller.snapshot?.completedAssets == 1)
        let deviceFolder = try BackupFolderLayout.deviceFolderName(for: source.device.id)
        let flatFile = fixture.folder.appendingPathComponent(deviceFolder + "/first.HEIC")
        #expect(try Data(contentsOf: flatFile) == OrganizationLibrarySource.firstBytes)
        #expect(try fixture.regularFiles().count == 1)

        source.addSecondAsset()
        try await organizationWait { model.assets.count == 2 && model.backupSourceAvailable }
        let second = try #require(model.assets.first { $0.filename == "second.HEIC" })
        model.startBackup(assets: [second])
        try #require(fixture.controller.isBusy)
        await fixture.controller.waitUntilStopped()
        #expect(fixture.controller.snapshot?.phase == .completed)
        #expect(fixture.controller.snapshot?.completedAssets == 1)
        let datedFile = fixture.folder.appendingPathComponent(deviceFolder + "/2023/11/second.HEIC")
        #expect(try Data(contentsOf: datedFile) == OrganizationLibrarySource.secondBytes)
        #expect(try Data(contentsOf: flatFile) == OrganizationLibrarySource.firstBytes)
        #expect(try fixture.regularFiles().count == 2)
        #expect(source.calls == ["first", "second"])
        #expect(fixture.scope.counts.active == 0)
    }
}

@MainActor
private final class OrganizationLibrarySource: DeviceMediaSource, OriginalMediaDownloading {
    static let firstBytes = Data([1, 2, 3])
    static let secondBytes = Data([4, 5, 6])
    let device = ConnectedDevice(id: "organization-phone", displayName: "Fixture iPhone")
    let session = UUID()
    let events: AsyncStream<DeviceEvent>
    let catalogs: AsyncStream<DeviceMediaSnapshot>
    private(set) var calls: [String] = []
    var isWaiting: Bool { firstTransfer != nil }
    private let eventContinuation: AsyncStream<DeviceEvent>.Continuation
    private let catalogContinuation: AsyncStream<DeviceMediaSnapshot>.Continuation
    private var firstTransfer: CheckedContinuation<Void, Never>?

    init() {
        let events = AsyncStream<DeviceEvent>.makeStream()
        self.events = events.stream
        eventContinuation = events.continuation
        let catalogs = AsyncStream<DeviceMediaSnapshot>.makeStream()
        self.catalogs = catalogs.stream
        catalogContinuation = catalogs.continuation
    }

    func start() {
        eventContinuation.yield(.stateChanged(DeviceConnection(device: device, state: .ready)))
        publish(ids: ["first"], revision: 1)
    }

    func stop() { finishFirstTransfer() }
    func retry() {}
    func addSecondAsset() { publish(ids: ["first", "second"], revision: 2) }

    func finishFirstTransfer() {
        let pending = firstTransfer
        firstTransfer = nil
        pending?.resume()
    }

    func downloadOriginal(
        resourceID: String, sessionID: UUID, to directory: URL, filename: String,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadedOriginal {
        guard sessionID == session else { throw MediaSourceError.staleSession }
        guard ["first", "second"].contains(resourceID) else { throw MediaSourceError.missingResource }
        calls.append(resourceID)
        if calls.count == 1 { await withCheckedContinuation { firstTransfer = $0 } }
        try Task.checkCancellation()
        let bytes = resourceID == "first" ? Self.firstBytes : Self.secondBytes
        let url = directory.appendingPathComponent(filename)
        try bytes.write(to: url)
        let count = Int64(bytes.count)
        progress(DownloadProgress(downloadedBytes: count, totalBytes: count))
        return DownloadedOriginal(url: url, expectedByteCount: count)
    }

    private func publish(ids: [String], revision: UInt64) {
        let records = ids.map { id in
            SourceMediaRecord(
                id: id, deviceID: device.id, filename: id + ".HEIC", uti: "public.heic", byteCount: 3,
                createdAt: BackupLibraryFixture.date, modifiedAt: BackupLibraryFixture.date
            )
        }
        catalogContinuation.yield(DeviceMediaSnapshot(
            sessionID: session, deviceID: device.id, revision: revision, records: records, state: .complete
        ))
    }
}

@MainActor
private func organizationWait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !condition() && ContinuousClock.now < deadline { await Task.yield() }
    try #require(condition(), "The controlled backup source did not reach the expected state")
}
