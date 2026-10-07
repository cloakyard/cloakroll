import DeviceCapture
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@MainActor
struct CaptureDateFilterTests {
    @Test func dateFilterReconcilesSelectionAndScopesBackupCandidates() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 80)
        let asset = try #require(model.snapshot.sections.first?.assets.first)
        let date = try #require(asset.createdAt)
        let fullCount = model.snapshot.filteredCount
        let fullCounts = model.snapshot.counts
        let reset = model.scrollReset
        model.selectAll()
        model.captureDateRange = CaptureDateRange(from: date, through: date)
        try await waitForPersistentState { !model.isProjecting }
        let range = try #require(model.captureDateRange)
        let expected = Set(model.assets.filter { range.contains($0.createdAt) }.map(\.id))
        #expect(!expected.isEmpty && expected.count < fullCount)
        #expect(model.selection.selectedIDs == expected)
        #expect(Set(model.backupCandidates(context: nil).map(\.id)) == expected)
        #expect(model.snapshot.counts == fullCounts)
        #expect(model.scrollReset == reset + 1)
        model.clearSelection()
        #expect(model.backupCandidates(context: nil).allSatisfy { range.contains($0.createdAt) })
        model.captureDateRange = nil
        try await waitForPersistentState { !model.isProjecting }
        #expect(model.snapshot.filteredCount == fullCount)
        #expect(model.selection.selectedIDs.isEmpty)
    }

    @Test func rapidChangesPublishOnlyTheLatestDateQuery() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 80)
        let asset = try #require(model.snapshot.sections.first?.assets.first)
        let date = try #require(asset.createdAt)
        let originalCount = model.snapshot.filteredCount
        model.captureDateRange = CaptureDateRange(from: .distantPast, through: .distantPast)
        model.captureDateRange = CaptureDateRange(from: date, through: date)
        model.search = asset.filename
        try await waitForPersistentState { !model.isProjecting }
        #expect(model.snapshot.orderedIDs == [asset.id])
        model.captureDateRange = nil
        model.search = ""
        try await waitForPersistentState { !model.isProjecting }
        #expect(model.snapshot.filteredCount == originalCount)
    }
}
