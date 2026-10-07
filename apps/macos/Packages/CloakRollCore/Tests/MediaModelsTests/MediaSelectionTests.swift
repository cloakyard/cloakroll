import MediaModels
import Testing

@Suite("Finder-style media selection")
struct MediaSelectionTests {
    private let orderedIDs = ["a", "b", "c", "d", "e", "f"]

    @Test("A normal click replaces the selection and range anchor")
    func normalClickReplacesSelection() {
        var selection = MediaSelection(selectedIDs: ["a", "b"], anchorID: "a")

        selection.select(id: "d", orderedIDs: orderedIDs)

        #expect(selection.selectedIDs == ["d"])
        #expect(selection.anchorID == "d")
    }

    @Test("Command-click adds and removes individual items")
    func commandClickTogglesItems() {
        var selection = MediaSelection()
        selection.select(id: "a", orderedIDs: orderedIDs)
        selection.select(id: "d", orderedIDs: orderedIDs, toggling: true)

        #expect(selection.selectedIDs == ["a", "d"])
        #expect(selection.anchorID == "d")

        selection.select(id: "a", orderedIDs: orderedIDs, toggling: true)

        #expect(selection.selectedIDs == ["d"])
        #expect(selection.anchorID == "a")
    }

    @Test("Shift-click selects the inclusive forward range")
    func shiftClickSelectsForwardRange() {
        var selection = MediaSelection()
        selection.select(id: "b", orderedIDs: orderedIDs)

        selection.select(id: "e", orderedIDs: orderedIDs, extendingRange: true)

        #expect(selection.selectedIDs == ["b", "c", "d", "e"])
        #expect(selection.anchorID == "b")
    }

    @Test("Shift-click selects the inclusive backward range")
    func shiftClickSelectsBackwardRange() {
        var selection = MediaSelection()
        selection.select(id: "e", orderedIDs: orderedIDs)

        selection.select(id: "b", orderedIDs: orderedIDs, extendingRange: true)

        #expect(selection.selectedIDs == ["b", "c", "d", "e"])
        #expect(selection.anchorID == "e")
    }

    @Test("Repeated Shift-click contracts the range around its original anchor")
    func shiftClickKeepsOriginalAnchor() {
        var selection = MediaSelection()
        selection.select(id: "b", orderedIDs: orderedIDs)
        selection.select(id: "f", orderedIDs: orderedIDs, extendingRange: true)

        selection.select(id: "d", orderedIDs: orderedIDs, extendingRange: true)

        #expect(selection.selectedIDs == ["b", "c", "d"])
        #expect(selection.anchorID == "b")
    }

    @Test("Command-Shift-click adds a range to the existing selection")
    func commandShiftClickUnionsRange() {
        var selection = MediaSelection()
        selection.select(id: "a", orderedIDs: orderedIDs)
        selection.select(id: "d", orderedIDs: orderedIDs, toggling: true)

        selection.select(id: "f", orderedIDs: orderedIDs, extendingRange: true, toggling: true)

        #expect(selection.selectedIDs == ["a", "d", "e", "f"])
        #expect(selection.anchorID == "d")
    }

    @Test("Shift-click without an anchor starts a new selection")
    func shiftClickWithoutAnchorSelectsTarget() {
        var selection = MediaSelection()

        selection.select(id: "c", orderedIDs: orderedIDs, extendingRange: true)

        #expect(selection.selectedIDs == ["c"])
        #expect(selection.anchorID == "c")
    }

    @Test("An item outside the visible order cannot change selection")
    func invalidTargetDoesNotChangeSelection() {
        let original = MediaSelection(selectedIDs: ["b", "c"], anchorID: "b")
        var selection = original

        selection.select(id: "missing", orderedIDs: orderedIDs)
        selection.select(id: "missing", orderedIDs: orderedIDs, toggling: true)
        selection.select(id: "missing", orderedIDs: orderedIDs, extendingRange: true)

        #expect(selection == original)
    }

    @Test("Reconciliation removes hidden items while retaining a visible anchor")
    func reconciliationPreservesVisibleSelection() {
        var selection = MediaSelection(selectedIDs: ["a", "b", "d"], anchorID: "b")

        selection.reconcile(with: ["b", "c", "d"])

        #expect(selection.selectedIDs == ["b", "d"])
        #expect(selection.anchorID == "b")
    }

    @Test("Reconciliation clears a hidden anchor before a later range selection")
    func reconciliationClearsHiddenAnchor() {
        var selection = MediaSelection(selectedIDs: ["a", "b", "d"], anchorID: "a")

        selection.reconcile(with: ["b", "c", "d"])

        #expect(selection.selectedIDs == ["b", "d"])
        #expect(selection.anchorID == nil)

        selection.select(id: "c", orderedIDs: ["b", "c", "d"], extendingRange: true)

        #expect(selection.selectedIDs == ["c"])
        #expect(selection.anchorID == "c")
    }

    @Test("An empty projection clears both selection and anchor")
    func reconciliationWithEmptyProjection() {
        var selection = MediaSelection(selectedIDs: ["a", "b"], anchorID: "b")

        selection.reconcile(with: [])

        #expect(selection == MediaSelection())
    }

    @Test("Select all replaces selection with the visible items and clear resets it")
    func selectAllAndClear() {
        var selection = MediaSelection(selectedIDs: ["hidden"], anchorID: "hidden")

        selection.selectAll(orderedIDs)

        #expect(selection.selectedIDs == Set(orderedIDs))
        #expect(selection.anchorID == "a")

        selection.clear()

        #expect(selection == MediaSelection())
    }

    @Test("Select all on an empty projection resets the anchor")
    func selectAllWithNoItems() {
        var selection = MediaSelection(selectedIDs: ["a"], anchorID: "a")

        selection.selectAll([])

        #expect(selection == MediaSelection())
    }

    @Test func addingAGroupPreservesOtherSelectionsAndAnchorsInVisibleOrder() {
        var selection = MediaSelection(selectedIDs: ["f"], anchorID: "f")
        selection.setSelected(true, ids: ["d", "c", "c", "missing"], orderedIDs: orderedIDs)
        #expect(selection.selectedIDs == ["c", "d", "f"])
        #expect(selection.anchorID == "c")
        selection.select(id: "e", orderedIDs: orderedIDs, extendingRange: true)
        #expect(selection.selectedIDs == ["c", "d", "e"])
    }

    @Test func removingAGroupRepairsOnlyAnAffectedAnchor() {
        var selection = MediaSelection(selectedIDs: ["a", "c", "d", "f"], anchorID: "a")
        selection.setSelected(false, ids: ["c", "d"], orderedIDs: orderedIDs)
        #expect(selection.selectedIDs == ["a", "f"] && selection.anchorID == "a")
        selection.setSelected(false, ids: ["a"], orderedIDs: orderedIDs)
        #expect(selection.selectedIDs == ["f"] && selection.anchorID == "f")
        selection.setSelected(false, ids: ["f"], orderedIDs: orderedIDs)
        #expect(selection == MediaSelection())
    }

    @Test func repeatedGroupActionsAreIdempotentAndIgnoreUnknownGroups() {
        var selection = MediaSelection(selectedIDs: ["f"], anchorID: "f")
        for _ in 0..<2 { selection.setSelected(true, ids: ["a", "b"], orderedIDs: orderedIDs) }
        #expect(selection.selectedIDs == ["a", "b", "f"] && selection.anchorID == "a")
        for _ in 0..<2 { selection.setSelected(false, ids: ["a", "b"], orderedIDs: orderedIDs) }
        let original = selection
        selection.setSelected(true, ids: ["missing"], orderedIDs: orderedIDs)
        selection.setSelected(false, ids: [], orderedIDs: orderedIDs)
        #expect(selection == original)
    }

    @Test func aGroupCannotRetainHiddenSelectionOrAnchor() {
        var selection = MediaSelection(selectedIDs: ["hidden", "a"], anchorID: "hidden")
        selection.setSelected(false, ids: ["b"], orderedIDs: orderedIDs)
        #expect(selection.selectedIDs == ["a"] && selection.anchorID == "a")
    }
}
