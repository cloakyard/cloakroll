import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Photo metadata app bridge", .timeLimit(.minutes(1)))
@MainActor
struct AppModelPhotoMetadataTests {
    @Test func livePhotoRequestsThePrimaryStillResourceAndCurrentSession() async throws {
        let fixture = try PhotoMetadataAppFixture()
        defer { fixture.stop() }
        let asset = try await fixture.open()
        #expect(asset.kind == .livePhoto)
        #expect(asset.resources.count == 2)
        #expect(asset.primaryResourceID == "z-still")

        let result = try await fixture.model.photoMetadata(for: asset, sessionID: fixture.session)
        #expect(result == fixture.source.response)
        #expect(fixture.source.calls == [PhotoMetadataCall(resourceID: "z-still", sessionID: fixture.session)])
    }

    @Test func unavailableSessionAndChangedAssetNeverReachTheProvider() async throws {
        let fixture = try PhotoMetadataAppFixture()
        defer { fixture.stop() }
        let asset = try await fixture.open()
        await #expect(throws: MediaSourceError.unavailable) {
            try await fixture.model.photoMetadata(for: asset, sessionID: UUID())
        }
        for state in [DeviceConnectionState.opening, .restricted, .unavailable, .disconnected] {
            fixture.source.send(state: state)
            try await metadataAppWait { fixture.model.deviceState == state }
            await #expect(throws: MediaSourceError.unavailable) {
                try await fixture.model.photoMetadata(for: asset, sessionID: fixture.session)
            }
        }
        fixture.source.send(state: .ready)
        fixture.source.send(session: fixture.session, revision: 2, filename: "renamed.HEIC")
        try await metadataAppWait { fixture.model.deviceState == .ready && fixture.model.assets.first?.filename == "renamed.HEIC" }
        #expect(fixture.model.assets.first?.id == asset.id)
        await #expect(throws: MediaSourceError.unavailable) {
            try await fixture.model.photoMetadata(for: asset, sessionID: fixture.session)
        }
        #expect(fixture.source.calls.isEmpty)
    }

    @Test func sampleMediaDoesNotRequestDeviceMetadata() async throws {
        let fixture = try PhotoMetadataAppFixture()
        defer { fixture.stop() }
        _ = try await fixture.open()
        await fixture.model.loadSample(count: 1)
        let sample = try #require(fixture.model.assets.first)
        await #expect(throws: MediaSourceError.unavailable) {
            try await fixture.model.photoMetadata(for: sample, sessionID: fixture.session)
        }
        #expect(fixture.source.calls.isEmpty)
    }

    @Test func disconnectDuringAwaitRejectsLateSuccessfulMetadata() async throws {
        let fixture = try PhotoMetadataAppFixture()
        defer { fixture.stop() }
        let asset = try await fixture.open()
        fixture.source.holdsRequests = true
        let request = Task { try await fixture.model.photoMetadata(for: asset, sessionID: fixture.session) }
        try await metadataAppWait { fixture.source.calls.count == 1 }
        fixture.source.send(state: .disconnected)
        try await metadataAppWait { fixture.model.deviceState == .disconnected }
        // The metadata provider intentionally ignores source retirement and returns success.
        fixture.source.finish()
        await #expect(throws: MediaSourceError.staleSession) { try await request.value }
        #expect(fixture.source.calls.count == 1)
    }

    @Test func equalAssetInANewSessionCannotAcceptThePreviousSessionsResult() async throws {
        let fixture = try PhotoMetadataAppFixture()
        defer { fixture.stop() }
        let asset = try await fixture.open()
        fixture.source.holdsRequests = true
        let old = Task { try await fixture.model.photoMetadata(for: asset, sessionID: fixture.session) }
        try await metadataAppWait { fixture.source.calls.count == 1 }
        let replacementSession = UUID()
        fixture.source.send(session: replacementSession)
        try await metadataAppWait {
            fixture.model.catalogSessionID == replacementSession && !fixture.model.isCatalogPreparing
        }
        // Identical resource handles and metadata do not make different sessions interchangeable.
        #expect(fixture.model.assets.first == asset)
        fixture.source.finish()
        await #expect(throws: MediaSourceError.staleSession) { try await old.value }

        fixture.source.holdsRequests = false
        let current = try await fixture.model.photoMetadata(for: asset, sessionID: replacementSession)
        #expect(current == fixture.source.response)
        #expect(fixture.source.calls.last == PhotoMetadataCall(resourceID: "z-still", sessionID: replacementSession))
    }

    @Test func sameSessionAssetChangeDuringAwaitRejectsTheOldMetadata() async throws {
        let fixture = try PhotoMetadataAppFixture()
        defer { fixture.stop() }
        let asset = try await fixture.open()
        fixture.source.holdsRequests = true
        let request = Task { try await fixture.model.photoMetadata(for: asset, sessionID: fixture.session) }
        try await metadataAppWait { fixture.source.calls.count == 1 }
        fixture.source.send(session: fixture.session, revision: 2, filename: "renamed.HEIC")
        try await metadataAppWait { fixture.model.assets.first?.filename == "renamed.HEIC" }
        #expect(fixture.model.catalogSessionID == fixture.session)
        #expect(fixture.model.assets.first?.id == asset.id)
        fixture.source.finish()
        await #expect(throws: MediaSourceError.staleSession) { try await request.value }
    }

    @Test func cancellationBeforeAndDuringRequestCannotReturnMetadata() async throws {
        let fixture = try PhotoMetadataAppFixture()
        defer { fixture.stop() }
        let asset = try await fixture.open()
        // Both operations are main-actor isolated, so cancellation happens before this task starts.
        let cancelled = Task { try await fixture.model.photoMetadata(for: asset, sessionID: fixture.session) }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(fixture.source.calls.isEmpty)

        fixture.source.holdsRequests = true
        let pending = Task { try await fixture.model.photoMetadata(for: asset, sessionID: fixture.session) }
        try await metadataAppWait { fixture.source.calls.count == 1 }
        pending.cancel()
        fixture.source.finish()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(fixture.source.calls.count == 1)
    }
}

@MainActor
private final class PhotoMetadataAppFixture {
    let backup: BackupControllerFixture
    let source = AppPhotoMetadataSource()
    let session = UUID()
    let model: AppModel

    init() throws {
        backup = try BackupControllerFixture(hasSelection: false)
        let source = source
        model = AppModel(makeBrowser: { source }, backup: backup.controller)
    }

    func open() async throws -> MediaAsset {
        model.startLive()
        source.send(state: .ready)
        source.send(session: session)
        try await metadataAppWait {
            model.deviceState == .ready && model.catalogSessionID == session && model.assets.count == 1
                && !model.isCatalogPreparing && !model.isProjecting
        }
        return try #require(model.assets.first)
    }

    func stop() {
        model.shutdown()
        source.finish()
    }
}

private struct PhotoMetadataCall: Equatable {
    let resourceID: String
    let sessionID: UUID
}

/// Deliberately retains pending calls across stop and ignores cancellation. The bridge must
/// reject stale success itself; no framework, original download, or persistent database is used.
@MainActor
private final class AppPhotoMetadataSource: DeviceMediaSource, PhotoMetadataProviding {
    let events: AsyncStream<DeviceEvent>
    let catalogs: AsyncStream<DeviceMediaSnapshot>
    let response = PhotoCameraMetadata(cameraMake: "Apple", cameraModel: "Fixture phone", iso: 80, exposureBias: 0)
    var holdsRequests = false
    private(set) var calls: [PhotoMetadataCall] = []
    private let eventContinuation: AsyncStream<DeviceEvent>.Continuation
    private let catalogContinuation: AsyncStream<DeviceMediaSnapshot>.Continuation
    private var pending: [CheckedContinuation<PhotoCameraMetadata, Never>] = []

    init() {
        let events = AsyncStream<DeviceEvent>.makeStream()
        self.events = events.stream
        eventContinuation = events.continuation
        let catalogs = AsyncStream<DeviceMediaSnapshot>.makeStream()
        self.catalogs = catalogs.stream
        catalogContinuation = catalogs.continuation
    }

    func start() {}
    func stop() {}
    func retry() {}

    func photoMetadata(for resourceID: String, sessionID: UUID) async throws -> PhotoCameraMetadata {
        calls.append(PhotoMetadataCall(resourceID: resourceID, sessionID: sessionID))
        if holdsRequests { return await withCheckedContinuation { pending.append($0) } }
        return response
    }

    func finish() {
        let completed = pending
        pending.removeAll()
        completed.forEach { $0.resume(returning: response) }
    }

    func send(state: DeviceConnectionState) {
        let device = state == .disconnected ? nil : ConnectedDevice(id: "metadata-phone", displayName: "Fixture phone")
        eventContinuation.yield(.stateChanged(DeviceConnection(device: device, state: state)))
    }

    func send(session: UUID, revision: UInt64 = 1, filename: String = "primary.HEIC") {
        let records = [
            SourceMediaRecord(
                id: "a-motion", deviceID: "metadata-phone", filename: "companion.MOV",
                uti: "com.apple.quicktime-movie", byteCount: 10, duration: 3
            ),
            SourceMediaRecord(
                id: "z-still", deviceID: "metadata-phone", filename: filename,
                uti: "public.heic", byteCount: 20, sidecarIDs: ["a-motion"]
            )
        ]
        catalogContinuation.yield(DeviceMediaSnapshot(
            sessionID: session, deviceID: "metadata-phone", revision: revision, records: records, state: .complete
        ))
    }
}

@MainActor
private func metadataAppWait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !condition() && ContinuousClock.now < deadline { await Task.yield() }
    try #require(condition(), "The controlled metadata source did not reach the expected state")
}
