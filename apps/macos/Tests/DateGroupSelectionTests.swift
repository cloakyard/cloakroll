import DeviceCapture
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Date group selection", .timeLimit(.minutes(1)))
@MainActor
struct DateGroupSelectionTests {
    @Test func groupActionsPreserveOtherGroupsAndBackupCandidates() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let sections = model.snapshot.sections
        try #require(sections.count > 1)
        let first = sections[0]
        let other = try #require(sections[1].assets.first)
        model.select(other, extendingRange: false, toggling: false)
        let target = model.dateGroupTarget(sectionID: first.id)
        #expect(model.dateGroupState(for: target)?.canSelect == true)
        #expect(model.dateGroupState(for: target)?.canDeselect == false)
        model.setDateGroupSelected(true, target: target)
        #expect(model.selection.selectedIDs == Set(first.assets.map(\.id) + [other.id]))
        #expect(model.backupCandidates(context: nil) == first.assets + [other])
        #expect(model.activeID == first.assets.first?.id)
        #expect(model.dateGroupState(for: target)?.canSelect == false)
        #expect(model.dateGroupState(for: target)?.selected == first.assets.count)
        model.setDateGroupSelected(false, target: target)
        #expect(model.selection.selectedIDs == [other.id])
        #expect(model.activeID == other.id && model.selection.anchorID == other.id)
        model.showSelectedInfo()
        #expect(model.infoAsset == other)
    }

    @Test func partialSelectionAndLastGroupRemovalLeaveNoStaleFocus() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let section = try #require(model.snapshot.sections.first)
        let first = try #require(section.assets.first)
        model.select(first, extendingRange: false, toggling: false)
        let target = model.activeDateGroupTarget
        #expect(target == model.dateGroupTarget(sectionID: section.id))
        let state = try #require(target.flatMap { model.dateGroupState(for: $0) })
        #expect(state.canSelect && state.canDeselect && state.selected == 1)
        model.setDateGroupSelected(false, target: try #require(target))
        #expect(model.selection == MediaSelection() && model.activeID == nil)
        #expect(model.activeDateGroupTarget == nil)
    }

    @Test func filterAndSearchSelectOnlyTheDisplayedMembers() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 80)
        model.filter = .videos
        try await waitForPersistentState { !model.isProjecting }
        let section = try #require(model.snapshot.sections.first)
        model.setDateGroupSelected(true, target: model.dateGroupTarget(sectionID: section.id))
        #expect(model.backupCandidates(context: nil) == section.assets)
        #expect(model.backupCandidates(context: nil).allSatisfy { $0.kind == .video })
        let asset = try #require(section.assets.first)
        model.search = asset.filename
        try await waitForPersistentState { !model.isProjecting }
        let result = try #require(model.snapshot.sections.first)
        model.clearSelection()
        model.setDateGroupSelected(true, target: model.dateGroupTarget(sectionID: result.id))
        #expect(model.selection.selectedIDs == [asset.id])
    }

    @Test func anOpenMenuCannotActOnAChangedProjectionOrGrouping() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let section = try #require(model.snapshot.sections.first)
        let target = model.dateGroupTarget(sectionID: section.id)
        model.sort = .oldestFirst
        model.setDateGroupSelected(true, target: target)
        #expect(model.selection.selectedIDs.isEmpty)
        try await waitForPersistentState { !model.isProjecting }
        #expect(model.dateGroupState(for: target) == nil)
        model.setDateGroupSelected(true, target: target)
        #expect(model.selection.selectedIDs.isEmpty)
        let current = model.dateGroupTarget(sectionID: section.id)
        model.grouping = .year
        try await waitForPersistentState { !model.isProjecting }
        model.setDateGroupSelected(true, target: current)
        #expect(model.selection.selectedIDs.isEmpty)
        let year = try #require(model.snapshot.sections.first)
        model.setDateGroupSelected(true, target: model.dateGroupTarget(sectionID: year.id))
        #expect(model.selection.selectedIDs == Set(model.snapshot.orderedIDs))
        #expect(model.activeID == model.snapshot.orderedIDs.first)
    }

    @Test func unavailableDeviceAndOtherPresentationsRejectGroupActions() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let section = try #require(model.snapshot.sections.first)
        let target = model.dateGroupTarget(sectionID: section.id)
        for state in [DeviceConnectionState.disconnected, .opening, .restricted, .unavailable] {
            model.deviceState = state
            model.setDateGroupSelected(true, target: target)
            #expect(model.selection.selectedIDs.isEmpty && model.dateGroupState(for: target) == nil)
        }
        model.deviceState = .ready
        model.navigation = .backupHistory
        model.setDateGroupSelected(true, target: target)
        #expect(model.selection.selectedIDs.isEmpty)
        model.navigation = .library(.all)
        model.infoAsset = section.assets.first
        model.setDateGroupSelected(true, target: target)
        #expect(model.selection.selectedIDs.isEmpty)
        model.infoAsset = nil
        model.isSample = false
        model.device = ConnectedDevice(id: "another-phone", displayName: "Another iPhone")
        model.setDateGroupSelected(true, target: target)
        #expect(model.selection.selectedIDs.isEmpty)
    }

    @Test func staleSessionUnknownGroupAndRemovedLibraryAreHarmless() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let section = try #require(model.snapshot.sections.first)
        let target = model.dateGroupTarget(sectionID: section.id)
        let staleSession = DateGroupSelectionTarget(sectionID: target.sectionID, revision: target.revision, sessionID: UUID())
        model.setDateGroupSelected(true, target: staleSession)
        model.setDateGroupSelected(true, target: model.dateGroupTarget(sectionID: "missing"))
        #expect(model.selection.selectedIDs.isEmpty)
        await model.loadSample(count: 0)
        model.setDateGroupSelected(true, target: target)
        #expect(model.selection.selectedIDs.isEmpty && model.activeID == nil)
    }

    @Test func groupSelectionSupportsUnknownDates() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 1_200)
        let unknown = try #require(model.snapshot.sections.first(where: { $0.date == nil }))
        model.setDateGroupSelected(true, target: model.dateGroupTarget(sectionID: unknown.id))
        #expect(model.backupCandidates(context: nil) == unknown.assets)
    }
}
