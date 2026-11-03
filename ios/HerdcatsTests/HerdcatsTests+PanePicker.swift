import Testing
@testable import Herdcats

@Suite("Pane picker")
struct PanePickerTests {
    @Test func aQueryMatchesIgnoringCaseAndSurroundingSpaces() {
        #expect(PanePicker.matches("Fix build", query: "  FIX "))
        #expect(PanePicker.matches("Fix build", query: ""))
        #expect(!PanePicker.matches("Fix build", query: "docs"))
    }

    @Test func theTitleNamesTheSlot() {
        #expect(PanePicker.title(slot: .right, layout: PaneLayout()) == "Open on the Right")
        let layout = PaneLayout(left: PaneRef(spaceID: "w1", paneID: nil), right: PaneRef(spaceID: "w2", paneID: nil))
        #expect(PanePicker.title(slot: .left, layout: layout) == "Replace Left Pane")
        #expect(PanePicker.title(slot: .right, layout: layout) == "Replace Right Pane")
    }

    // MARK: Row badges

    @Test func badgesOnlyShowWhileSplit() {
        let single = PaneLayout(left: PaneRef(spaceID: "w1", paneID: nil))
        #expect(single.badgeSlots(spaceID: "w1").isEmpty)
        let both = PaneLayout(left: PaneRef(spaceID: "w1", paneID: nil), right: PaneRef(spaceID: "w2", paneID: "p2"))
        #expect(both.badgeSlots(spaceID: "w1") == [.left])
        #expect(both.badgeSlots(spaceID: "w2") == [.right])
        #expect(both.badgeSlots(spaceID: "w3").isEmpty)
    }

    @Test func aSpaceOpenInBothSlotsShowsBothBadges() {
        let both = PaneLayout(left: PaneRef(spaceID: "w1", paneID: "p1"), right: PaneRef(spaceID: "w1", paneID: "p2"))
        #expect(both.badgeSlots(spaceID: "w1") == [.left, .right])
    }

    @Test func agentBadgesMatchOnPaneID() {
        let both = PaneLayout(left: PaneRef(spaceID: "w1", paneID: "p1"), right: PaneRef(spaceID: "w2", paneID: "p2"))
        #expect(both.badgeSlot(paneID: "p1") == .left)
        #expect(both.badgeSlot(paneID: "p2") == .right)
        #expect(both.badgeSlot(paneID: "p9") == nil)
    }
}
