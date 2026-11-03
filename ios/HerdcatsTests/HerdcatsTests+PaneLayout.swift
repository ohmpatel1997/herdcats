import CoreGraphics
import Testing
@testable import Herdcats

@Suite("Pane layout")
struct PaneLayoutTests {
    private let a = PaneRef(spaceID: "a", paneID: nil)
    private let b = PaneRef(spaceID: "b", paneID: nil)
    private let c = PaneRef(spaceID: "c", paneID: "p1")

    private func split(_ left: PaneRef, _ right: PaneRef, focused: PaneLayout.Slot = .left) -> PaneLayout {
        var layout = PaneLayout(left: left, right: right)
        layout.focused = focused
        return layout
    }

    // MARK: derived state

    @Test func emptyLayoutHasNoFocusedRefAndIsNotSplit() {
        let layout = PaneLayout()
        #expect(layout.focusedRef == nil)
        #expect(!layout.isSplit)
    }

    @Test func singlePaneFocusedRefIsLeftEvenIfFocusPointsRight() {
        var layout = PaneLayout(left: a)
        layout.focused = .right
        #expect(layout.focusedRef == a)
        #expect(!layout.isSplit)
    }

    @Test func splitFocusedRefFollowsTheFocusedSlot() {
        #expect(split(a, b, focused: .left).focusedRef == a)
        #expect(split(a, b, focused: .right).focusedRef == b)
        #expect(split(a, b).isSplit)
    }

    // MARK: open

    @Test func openPutsRefInSlotAndFocusesIt() {
        var layout = PaneLayout(left: a)
        layout.open(b, in: .right)
        #expect(layout.left == a)
        #expect(layout.right == b)
        #expect(layout.focused == .right)
    }

    @Test func openReplacesTheTargetSlot() {
        var layout = split(a, b)
        layout.open(c, in: .left)
        #expect(layout.left == c)
        #expect(layout.right == b)
        #expect(layout.focused == .left)
    }

    @Test func openingARefAlreadyInTheOtherSlotSwaps() {
        var layout = split(a, b, focused: .left)
        layout.open(b, in: .left)
        #expect(layout.left == b)
        #expect(layout.right == a)
        #expect(layout.focused == .left)
    }

    @Test func openingARefAlreadyInTheSameSlotJustFocusesIt() {
        var layout = split(a, b, focused: .left)
        layout.open(b, in: .right)
        #expect(layout.left == a)
        #expect(layout.right == b)
        #expect(layout.focused == .right)
    }

    @Test func openRightWhileLeftIsEmptyUsesLeft() {
        var layout = PaneLayout()
        layout.open(a, in: .right)
        #expect(layout.left == a)
        #expect(layout.right == nil)
        #expect(layout.focused == .left)
    }

    @Test func openingTheOnlyPaneOnTheRightDoesNotMoveItOutOfLeft() {
        var layout = PaneLayout(left: a)
        layout.open(a, in: .right)
        #expect(layout.left == a)
        #expect(layout.right == nil)
        #expect(layout.focused == .left)
    }

    @Test func openInFocusedReplacesTheFocusedSlotWhenSplit() {
        var layout = split(a, b, focused: .right)
        layout.openInFocused(c)
        #expect(layout.left == a)
        #expect(layout.right == c)
        #expect(layout.focused == .right)
    }

    @Test func openInFocusedUsesLeftWhenNotSplit() {
        var layout = PaneLayout(left: a)
        layout.focused = .right
        layout.openInFocused(b)
        #expect(layout.left == b)
        #expect(layout.right == nil)
        #expect(layout.focused == .left)
    }

    @Test func openInFocusedSwapsWhenRefIsInTheOtherSlot() {
        var layout = split(a, b, focused: .left)
        layout.openInFocused(b)
        #expect(layout.left == b)
        #expect(layout.right == a)
        #expect(layout.focused == .left)
    }

    // MARK: close

    @Test func closingLeftMovesRightIntoLeft() {
        var layout = split(a, b, focused: .right)
        layout.ratio = 0.7
        layout.close(.left)
        #expect(layout.left == b)
        #expect(layout.right == nil)
        #expect(layout.focused == .left)
        #expect(layout.ratio == 0.5)
    }

    @Test func closingRightKeepsLeft() {
        var layout = split(a, b, focused: .right)
        layout.ratio = 0.3
        layout.close(.right)
        #expect(layout.left == a)
        #expect(layout.right == nil)
        #expect(layout.focused == .left)
        #expect(layout.ratio == 0.5)
    }

    @Test func closingTheOnlyPaneLeavesAnEmptyLayout() {
        var layout = PaneLayout(left: a)
        layout.compactDetailVisible = true
        layout.close(.left)
        #expect(layout.left == nil)
        #expect(layout.right == nil)
        #expect(!layout.compactDetailVisible)
    }

    // MARK: swap / fullWidth / focus

    @Test func swapFlipsSlotsAndFocusStaysWithThePane() {
        var layout = split(a, b, focused: .left)
        layout.swap()
        #expect(layout.left == b)
        #expect(layout.right == a)
        #expect(layout.focused == .right)
        #expect(layout.focusedRef == a)
    }

    @Test func swapDoesNothingWithoutASplit() {
        var layout = PaneLayout(left: a)
        layout.swap()
        #expect(layout == PaneLayout(left: a))
    }

    @Test func fullWidthKeepsOnlyThatSlotInLeft() {
        var layout = split(a, b, focused: .left)
        layout.ratio = 0.3
        layout.fullWidth(.right)
        #expect(layout.left == b)
        #expect(layout.right == nil)
        #expect(layout.focused == .left)
        #expect(layout.ratio == 0.5)
    }

    @Test func focusMovesOnlyToAnOccupiedSlot() {
        var layout = PaneLayout(left: a)
        layout.focus(.right)
        #expect(layout.focused == .left)
        layout.open(b, in: .right)
        layout.focus(.left)
        #expect(layout.focused == .left)
        layout.focus(.right)
        #expect(layout.focused == .right)
    }

    // MARK: ratio

    @Test func snappedRatioClampsToTheAllowedRange() {
        #expect(PaneLayout.snappedRatio(0.0) == 0.25)
        #expect(PaneLayout.snappedRatio(0.20) == 0.25)
        #expect(PaneLayout.snappedRatio(0.9) == 0.75)
    }

    @Test func snappedRatioSnapsToThirdsAndHalfWithinTolerance() {
        #expect(PaneLayout.snappedRatio(0.30) == 1.0 / 3.0)
        #expect(PaneLayout.snappedRatio(0.36) == 1.0 / 3.0)
        #expect(PaneLayout.snappedRatio(0.47) == 0.5)
        #expect(PaneLayout.snappedRatio(0.53) == 0.5)
        #expect(PaneLayout.snappedRatio(0.70) == 2.0 / 3.0)
    }

    @Test func snappedRatioLeavesValuesOutsideTheToleranceAlone() {
        #expect(PaneLayout.snappedRatio(0.40) == 0.40)
        #expect(PaneLayout.snappedRatio(0.60) == 0.60)
    }

    // MARK: list fit

    @Test func listFitsIsAlwaysTrueForASinglePane() {
        #expect(PaneLayout.listFits(totalWidth: 300, listWidth: 220, isSplit: false))
    }

    @Test func listDoesNotFitOnTheDuoInnerScreen() {
        #expect(!PaneLayout.listFits(totalWidth: 626, listWidth: 220, isSplit: true))
    }

    @Test func listFitsOnIPad11Landscape() {
        #expect(PaneLayout.listFits(totalWidth: 1210, listWidth: 340, isSplit: true))
    }

    @Test func listDoesNotFitOnIPad11Portrait() {
        #expect(!PaneLayout.listFits(totalWidth: 834, listWidth: 320, isSplit: true))
    }

    @Test func listFitsAtExactlyTheMinimumPaneWidth() {
        // (532 - 12) / 2 == 260 is still fine; one point less is not.
        #expect(PaneLayout.listFits(totalWidth: 532, listWidth: 0, isSplit: true))
        #expect(!PaneLayout.listFits(totalWidth: 531, listWidth: 0, isSplit: true))
    }

    // MARK: pruned

    @Test func prunedKeepsEverythingWhenAllRefsSurvive() {
        let layout = split(a, b, focused: .right)
        #expect(layout.pruned { _ in true } == layout)
    }

    @Test func prunedMovesTheSurvivorToLeftWhenLeftIsGone() {
        let pruned = split(a, b, focused: .right).pruned { $0 != a }
        #expect(pruned.left == b)
        #expect(pruned.right == nil)
        #expect(pruned.focused == .left)
    }

    @Test func prunedDropsOnlyTheRightWhenRightIsGone() {
        let pruned = split(a, b, focused: .right).pruned { $0 != b }
        #expect(pruned.left == a)
        #expect(pruned.right == nil)
        #expect(pruned.focused == .left)
    }

    @Test func prunedEmptiesTheLayoutWhenNothingSurvives() {
        let pruned = split(a, b).pruned { _ in false }
        #expect(pruned.left == nil)
        #expect(pruned.right == nil)
    }

    // MARK: scene storage

    @Test func storageValueRoundTrips() {
        var layout = split(a, c, focused: .right)
        layout.ratio = 2.0 / 3.0
        layout.compactDetailVisible = true
        #expect(PaneLayout(storageValue: layout.storageValue) == layout)
    }

    @Test func garbageStorageDecodesToAnEmptyLayout() {
        #expect(PaneLayout(storageValue: "") == PaneLayout())
        #expect(PaneLayout(storageValue: "garbage") == PaneLayout())
        #expect(PaneLayout(storageValue: "{\"left\": 3}") == PaneLayout())
    }

    // MARK: compact stack

    @Test func compactPathIsEmptyUntilTheDetailIsPushed() {
        var layout = split(a, b, focused: .right)
        #expect(layout.compactPath.isEmpty)
        layout.compactDetailVisible = true
        #expect(layout.compactPath == [b])
    }

    @Test func compactPathIsEmptyForAnEmptyLayout() {
        var layout = PaneLayout()
        layout.compactDetailVisible = true
        #expect(layout.compactPath.isEmpty)
    }

    @Test func backingOutOfTheCompactStackKeepsTheSlots() {
        var layout = split(a, b, focused: .right)
        layout.compactDetailVisible = true
        layout.setCompactPath([])
        #expect(!layout.compactDetailVisible)
        #expect(layout.left == a)
        #expect(layout.right == b)
        #expect(layout.focused == .right)
    }

    @Test func pushingARefOpensItInTheFocusedSlot() {
        var layout = split(a, b, focused: .right)
        layout.setCompactPath([c])
        #expect(layout.compactDetailVisible)
        #expect(layout.left == a)
        #expect(layout.right == c)
        #expect(layout.compactPath == [c])
    }

    @Test func pushingAPaneAnotherSlotAlreadyShowsSwapsInsteadOfDuplicating() {
        // The left slot is the whole space `a`, showing its pane p1; the right slot shows b.
        let p1 = PaneRef(spaceID: "a", paneID: "p1")
        let shown: PaneLayout.Resolver = { $0.paneID ?? ($0.spaceID == "a" ? "p1" : nil) }
        var layout = split(a, b, focused: .right)
        layout.setCompactPath([p1], shown: shown)
        #expect(layout.left == b)
        #expect(layout.right == a)
        #expect(layout.compactDetailVisible)
    }

    @Test func pushingTheFocusedRefOnlyShowsTheDetail() {
        var layout = split(a, b, focused: .left)
        layout.setCompactPath([a])
        #expect(layout.compactDetailVisible)
        #expect(layout == { var l = split(a, b); l.compactDetailVisible = true; return l }())
    }

    @Test func foldingToCompactPushesTheFocusedPaneOnlyWhenSomethingIsOpen() {
        var layout = split(a, b)
        layout.enteredCompact()
        #expect(layout.compactDetailVisible)
        var empty = PaneLayout()
        empty.enteredCompact()
        #expect(!empty.compactDetailVisible)
    }

    // MARK: divider steps

    @Test func steppedRatioMovesBetweenThirdsAndHalf() {
        #expect(PaneLayout.steppedRatio(0.5, increment: true) == 2.0 / 3.0)
        #expect(PaneLayout.steppedRatio(0.5, increment: false) == 1.0 / 3.0)
        #expect(PaneLayout.steppedRatio(2.0 / 3.0, increment: true) == 2.0 / 3.0)
        #expect(PaneLayout.steppedRatio(1.0 / 3.0, increment: false) == 1.0 / 3.0)
        #expect(PaneLayout.steppedRatio(0.4, increment: true) == 0.5)
        #expect(PaneLayout.steppedRatio(0.4, increment: false) == 1.0 / 3.0)
    }

    // MARK: Same pane under different refs

    /// `a` (the whole space) is showing its pane p1, as the open detail reports it.
    private let shownP1: PaneLayout.Resolver = { $0.paneID ?? "p1" }

    @Test func openingTheSamePaneByAnotherRefDoesNotOpenItTwice() {
        let named = PaneRef(spaceID: "a", paneID: "p1")
        var layout = PaneLayout(left: a)
        layout.open(named, in: .right, shown: shownP1)
        #expect(layout.left == a)
        #expect(layout.right == nil)
        #expect(layout.focused == .left)
    }

    @Test func aDifferentPaneOfTheSameSpaceStillOpensBeside() {
        var layout = PaneLayout(left: a)
        layout.open(PaneRef(spaceID: "a", paneID: "p2"), in: .right, shown: shownP1)
        #expect(layout.right == PaneRef(spaceID: "a", paneID: "p2"))
    }

    @Test func aDuplicateUnderAnotherRefSwapsLikeAnyOpenPane() {
        let named = PaneRef(spaceID: "a", paneID: "p1")
        var layout = split(a, b)
        layout.open(named, in: .right, shown: shownP1)
        #expect(layout.left == b)
        #expect(layout.right == a)
    }

    @Test func droppingAnOpenPaneUnderAnotherRefDoesNotSplit() {
        var layout = PaneLayout(left: a)
        let payload = PaneDragPayload.encode(PaneRef(spaceID: "a", paneID: "p1"))
        let accepted = layout.drop(payload, onHalf: .left, shown: shownP1)
        #expect(accepted)
        #expect(!layout.isSplit)
    }

    @Test func badgesFollowThePaneEachSlotShows() {
        let layout = split(PaneRef(spaceID: "a", paneID: "p1"), b)
        // The left slot's sibling switcher moved it to p2.
        let shown: PaneLayout.Resolver = { $0.spaceID == "a" ? "p2" : $0.paneID }
        #expect(layout.badgeSlot(paneID: "p2", shown: shown) == .left)
        #expect(layout.badgeSlot(paneID: "p1", shown: shown) == nil)
    }
}
