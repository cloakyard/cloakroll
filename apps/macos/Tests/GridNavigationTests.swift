import AppKit
import DeviceCapture
import Foundation
import MediaModels
import Testing
@testable import CloakRoll

@Suite("Grouped grid keyboard navigation")
struct GridNavigationTests {
    @Test func incompleteMonthRowKeepsTheSameVisualColumn() {
        var nav = GridNavigation()
        #expect(nav.target(from: 18, direction: .down, sectionCounts: [19, 185], columns: 2, revision: 1) == 19)
        #expect(nav.target(from: 19, direction: .up, sectionCounts: [19, 185], columns: 2, revision: 1) == 18)
    }

    @Test func shortRowsKeepTheIntendedColumnInBothDirections() {
        var nav = GridNavigation()
        #expect(nav.target(from: 3, direction: .down, sectionCounts: [5, 0, 8], columns: 4, revision: 1) == 4)
        #expect(nav.target(from: 4, direction: .down, sectionCounts: [5, 0, 8], columns: 4, revision: 1) == 8)
        #expect(nav.target(from: 8, direction: .up, sectionCounts: [5, 0, 8], columns: 4, revision: 1) == 4)
        #expect(nav.target(from: 4, direction: .up, sectionCounts: [5, 0, 8], columns: 4, revision: 1) == 3)
    }

    @Test func clicksHorizontalMovementResizeAndNewProjectionResetColumnPreference() {
        for reset in 0...4 {
            var nav = GridNavigation()
            #expect(nav.target(from: 3, direction: .down, sectionCounts: [5, 8], columns: 4, revision: 1) == 4)
            switch reset {
            case 0: nav.reset()
            case 1:
                _ = nav.target(from: 4, direction: .left, sectionCounts: [5, 8], columns: 4, revision: 1)
                _ = nav.target(from: 3, direction: .right, sectionCounts: [5, 8], columns: 4, revision: 1)
            default: break
            }
            #expect(nav.target(from: 4, direction: .up, sectionCounts: reset == 4 ? [6, 7] : [5, 8], columns: reset == 2 ? 3 : 4,
                               revision: reset == 3 ? 2 : 1) == (reset == 2 ? 1 : 0))
        }
    }

    @Test func verticalEdgesDoNotJumpSidewaysAndEmptyViewsHaveNoTarget() {
        var nav = GridNavigation()
        #expect(nav.target(from: 2, direction: .up, sectionCounts: [8], columns: 4, revision: 1) == 2)
        #expect(nav.target(from: 6, direction: .down, sectionCounts: [8], columns: 4, revision: 1) == 6)
        #expect(nav.target(from: nil, direction: .up, sectionCounts: [8], columns: 4, revision: 1) == 0)
        #expect(nav.target(from: 0, direction: .left, sectionCounts: [8], columns: 4, revision: 1) == 0)
        #expect(nav.target(from: 7, direction: .right, sectionCounts: [8], columns: 4, revision: 1) == 7)
        #expect(nav.target(from: nil, direction: .down, sectionCounts: [0], columns: 0, revision: 1) == nil)
    }

    @Test func targetsStayWithinTheCatalogAcrossRowAndSectionSizes() throws {
        for columns in 1...5 {
            for first in 1...7 {
                for second in 1...7 {
                    for index in 0..<(first + second) {
                        for direction in GridDirection.allCases {
                            var nav = GridNavigation()
                            let result = nav.target(from: index, direction: direction,
                                                    sectionCounts: [first, second], columns: columns, revision: 1)
                            let target = try #require(result)
                            #expect((0..<(first + second)).contains(target))
                        }
                    }
                }
            }
        }
    }

    @MainActor @Test func shiftRangeCanExtendAndRetractAcrossAShortDateRow() async throws {
        let model = AppModel(makeBrowser: { MockDeviceBrowserService() })
        await model.loadSample(count: 20)
        let assets = Array(model.snapshot.sections.flatMap(\.assets).prefix(13))
        model.snapshot = CatalogSnapshot(sections: [
            MediaSection(id: "one", date: nil, assets: Array(assets.prefix(5))),
            MediaSection(id: "two", date: nil, assets: Array(assets.dropFirst(5)))
        ], counts: [:], orderedIDs: assets.map(\.id), totalCount: 13, newCount: 13, newBytes: 0, totalBytes: 0)
        model.select(assets[3], extendingRange: false, toggling: false)
        model.moveSelection(.down, columns: 4, extending: true)
        #expect(model.activeID == assets[4].id && model.selection.selectedIDs.count == 2)
        model.moveSelection(.down, columns: 4, extending: true)
        #expect(model.activeID == assets[8].id && model.selection.selectedIDs == Set(assets[3...8].map(\.id)))
        model.moveSelection(.up, columns: 4, extending: true)
        #expect(model.activeID == assets[4].id && model.selection.selectedIDs.count == 2)
        model.select(assets[4], extendingRange: false, toggling: false)
        model.moveSelection(.up, columns: 4, extending: false)
        #expect(model.selection.selectedIDs == [assets[0].id])
        model.showSelectedInfo()
        model.moveSelection(.right, columns: 4, extending: false)
        #expect(model.activeID == assets[0].id)
    }

    @MainActor @Test func modifiedArrowsAndVoiceOverChordsRemainInTheResponderChain() throws {
        func event(_ key: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                         windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                         isARepeat: false, keyCode: key))
        }
        #expect(GridKeyAction(event: try event(125, [.numericPad, .function])) == .move(.down, extending: false))
        #expect(GridKeyAction(event: try event(126, [.shift, .numericPad, .function])) == .move(.up, extending: true))
        for flags: NSEvent.ModifierFlags in [.option, .command, .control, [.control, .option], [.command, .shift]] {
            for key: UInt16 in [123, 124, 125, 126, 49, 53] {
                #expect(GridKeyAction(event: try event(key, flags)) == nil)
            }
        }
        #expect(GridKeyAction(event: try event(49, [])) == .preview)
        #expect(GridKeyAction(event: try event(53, [])) == .clear)
        #expect(GridKeyAction(event: try event(49, .shift)) == nil)
    }
}
