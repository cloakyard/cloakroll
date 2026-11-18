import Foundation
import Testing
@testable import CloakRoll

@Suite("Generated-preview isolation", .timeLimit(.minutes(1)))
@MainActor
struct FeaturePreviewTests {
    @Test func independentWindowsDoNotShareSourcesOrHistory() async throws {
        let first = FeaturePreview.makeModel()
        let second = FeaturePreview.makeModel()
        defer { first.shutdown(); second.shutdown() }
        await FeaturePreview.prepare(first)
        await FeaturePreview.prepare(second)
        let firstFolder = try #require(first.backup.destination.selection?.lastKnownPath)
        let secondFolder = try #require(second.backup.destination.selection?.lastKnownPath)
        defer {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: firstFolder).deletingLastPathComponent())
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: secondFolder).deletingLastPathComponent())
        }
        #expect(firstFolder != secondFolder && first.catalogSessionID != second.catalogSessionID)
        for model in [first, second] {
            let sessions = try await model.backup.persistence?.store().recentSessions() ?? []
            #expect(sessions.count == 2)
            #expect(sessions.filter { $0.status == .failed && $0.verifiedResources == 2 }.count == 1)
            #expect(sessions.filter { $0.status == .completed && $0.verifiedResources == 1 }.count == 1)
            #expect(model.assets.count == 3 && model.navigation == .backupHealth)
        }
    }

    @Test func stoppingAClosedPreviewFinishesBothStreams() async {
        let source = FeaturePreviewSource()
        var events = source.events.makeAsyncIterator()
        var catalogs = source.catalogs.makeAsyncIterator()
        source.stop()
        #expect(await events.next() == nil)
        #expect(await catalogs.next() == nil)
    }
}
