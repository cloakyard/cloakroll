import DeviceCapture
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@MainActor
struct AppModelCatalogTests {
    @Test func liveMetadataUsesTheLatestQueryAndRevision() async throws {
        let browser = MockDeviceBrowserService()
        let model = AppModel(makeBrowser: { browser })
        model.startLive()
        defer { model.shutdown() }
        let device = ConnectedDevice(id: "phone", displayName: "Test iPhone")
        browser.send(DeviceConnection(device: device, state: .ready))
        let session = UUID()
        for revision in 1...40 {
            let records = (0..<revision).map { record("photo-\($0)") }
            browser.sendCatalog(snapshot(session, revision: UInt64(revision), records: records))
        }
        model.search = "photo-39"
        try await waitUntil { model.assets.count == 40 && !model.isProjecting && !model.isCatalogPreparing }
        #expect(model.snapshot.filteredCount == 1)
        #expect(model.snapshot.sections.first?.assets.first?.filename == "photo-39.HEIC")
        #expect(model.mediaScanState == .complete)
        #expect(!model.isSample)
    }

    @Test func retiredCatalogSessionsAndRevisionsCannotReplaceCurrentMedia() async throws {
        let browser = MockDeviceBrowserService()
        let model = AppModel(makeBrowser: { browser })
        model.startLive()
        defer { model.shutdown() }
        let oldSession = UUID()
        let newSession = UUID()
        browser.sendCatalog(snapshot(oldSession, records: [record("old")]))
        try await waitUntil { model.assets.first?.filename == "old.HEIC" }
        browser.sendCatalog(snapshot(newSession, revision: 2, records: [record("new")]))
        try await waitUntil { model.assets.first?.filename == "new.HEIC" }
        browser.sendCatalog(snapshot(oldSession, revision: 99, records: [record("late-old")]))
        await Task.yield()
        browser.sendCatalog(snapshot(newSession, revision: 1, records: [record("out-of-order")]))
        // A later accepted revision gives a deterministic barrier after the rejected envelopes.
        browser.sendCatalog(snapshot(newSession, revision: 3, records: [record("new"), record("newer")]))
        try await waitUntil { model.assets.count == 2 && !model.isProjecting }
        #expect(Set(model.assets.map(\.filename)) == ["new.HEIC", "newer.HEIC"])
        #expect(model.catalogSessionID == newSession)
    }

    @Test func disconnectKeepsMetadataAndCompleteEmptyCatalogReplacesIt() async throws {
        let browser = MockDeviceBrowserService()
        let model = AppModel(makeBrowser: { browser })
        model.startLive()
        defer { model.shutdown() }
        let session = UUID()
        browser.sendCatalog(snapshot(session, records: [record("kept")]))
        try await waitUntil { model.assets.count == 1 && !model.isProjecting }
        browser.send(DeviceConnection(state: .disconnected))
        browser.sendCatalog(DeviceMediaSnapshot(
            sessionID: session, deviceID: "phone", revision: 2, records: [], state: .interrupted
        ))
        try await waitUntil { model.mediaScanState == .interrupted && !model.isCatalogPreparing }
        #expect(model.assets.first?.filename == "kept.HEIC")
        browser.sendCatalog(snapshot(UUID(), records: []))
        try await waitUntil { model.assets.isEmpty && !model.isProjecting }
        #expect(model.snapshot.filteredCount == 0)
        #expect(model.mediaScanState == .complete)
    }

    @Test func switchingToSamplesRetiresLivePreparation() async throws {
        let browser = MockDeviceBrowserService()
        let model = AppModel(makeBrowser: { browser })
        model.startLive()
        browser.sendCatalog(snapshot(UUID(), records: (0..<10_000).map { record("live-\($0)") }))
        await model.loadSample(count: 20)
        browser.sendCatalog(snapshot(UUID(), records: [record("late")]))
        await Task.yield()
        #expect(model.isSample)
        #expect(model.assets.count == 20)
        #expect(model.assets.allSatisfy { $0.id.hasPrefix("fixture-") })
        #expect(model.catalogSessionID == nil)
    }

    @Test func incomingCatalogsDoNotResetScrollingButQueryChangesDo() async throws {
        let browser = MockDeviceBrowserService()
        let model = AppModel(makeBrowser: { browser })
        model.startLive()
        defer { model.shutdown() }
        let session = UUID()
        browser.sendCatalog(snapshot(session, records: [record("first")]))
        try await waitUntil { model.assets.count == 1 && !model.isProjecting }
        let initialReset = model.scrollReset
        browser.sendCatalog(snapshot(session, revision: 2, records: [record("earlier"), record("first")]))
        try await waitUntil { model.assets.count == 2 && !model.isProjecting }
        #expect(model.scrollReset == initialReset)
        model.sort = .oldestFirst
        try await waitUntil { !model.isProjecting }
        #expect(model.scrollReset == initialReset + 1)
    }

    private func record(_ id: String) -> SourceMediaRecord {
        SourceMediaRecord(id: id, deviceID: "phone", filename: "\(id).HEIC", uti: "public.heic", byteCount: 128)
    }

    private func snapshot(
        _ session: UUID, revision: UInt64 = 1, records: [SourceMediaRecord]
    ) -> DeviceMediaSnapshot {
        DeviceMediaSnapshot(sessionID: session, deviceID: "phone", revision: revision, records: records, state: .complete)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !condition() && clock.now < deadline { await Task.yield() }
        try #require(condition(), "The catalog did not reach the expected presentation state")
    }
}
