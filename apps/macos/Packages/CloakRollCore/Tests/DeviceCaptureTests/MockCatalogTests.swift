import Foundation
import MediaModels
import Testing
@testable import DeviceCapture

@Suite("Mock catalog contract", .timeLimit(.minutes(1)))
@MainActor
struct MockCatalogTests {
    @Test("A slow consumer receives the latest complete envelope rather than lossy deltas")
    func newestSnapshotIsReplaceable() async throws {
        let source = MockDeviceBrowserService()
        let session = UUID()
        source.start()
        for revision in 1...100 {
            source.sendCatalog(DeviceMediaSnapshot(
                sessionID: session, deviceID: "phone", revision: UInt64(revision),
                records: (0..<revision).map {
                    SourceMediaRecord(id: "\($0)", deviceID: "phone", filename: "SAME.JPG", byteCount: 12)
                }, state: .scanning
            ))
        }
        var iterator = source.catalogs.makeAsyncIterator()
        let latest = try #require(await iterator.next())
        #expect(latest.revision == 100)
        #expect(latest.records.count == 100)
        source.stop()
    }

    @Test("A snapshot injected before start is available to a newly started consumer")
    func initialSnapshot() async throws {
        let source = MockDeviceBrowserService()
        let expected = DeviceMediaSnapshot(sessionID: UUID(), deviceID: "phone", revision: 3,
                                           records: [], state: .complete)
        source.sendCatalog(expected)
        source.start()
        var iterator = source.catalogs.makeAsyncIterator()
        #expect(await iterator.next() == expected)
        source.stop()
    }
}
