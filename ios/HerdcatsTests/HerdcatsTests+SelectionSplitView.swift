import SwiftUI
import Testing
@testable import Herdcats

@Suite("Selection split view")
struct SelectionSplitViewTests {
    @Test func columnVisibilityRoundTripsThroughSceneStorage() {
        for visibility in [NavigationSplitViewVisibility.all, .doubleColumn, .detailOnly, .automatic] {
            #expect(NavigationSplitViewVisibility(storageValue: visibility.storageValue) == visibility)
        }
    }

    @Test func unknownStoredVisibilityShowsBothColumns() {
        #expect(NavigationSplitViewVisibility(storageValue: "garbage") == .all)
    }

    @Test func openPaneMemoryKeepsTheSiblingOfTheSelectedItem() {
        let memory = OpenPaneMemory()
        let slot = OpenPaneSlot(memory: memory, selection: "a")
        #expect(slot.paneID == nil)
        slot.remember("b")
        #expect(slot.paneID == "b")
        // Another selection doesn't see it, and keeps its own without touching it.
        #expect(OpenPaneSlot(memory: memory, selection: "c").paneID == nil)
        OpenPaneSlot(memory: memory, selection: "c").remember("d")
        #expect(slot.paneID == "b")
        #expect(OpenPaneSlot(memory: memory, selection: "c").paneID == "d")
    }

    @Test func openPaneMemoryFollowsItsRefWhenTheSlotsSwap() {
        let memory = OpenPaneMemory()
        var layout = PaneLayout(left: ref("a"), right: ref("b"))
        OpenPaneSlot(memory: memory, selection: ref("a").memoryKey).remember("sibling")
        layout.swap()
        let rightSlot = OpenPaneSlot(memory: memory, selection: layout.right!.memoryKey)
        #expect(layout.right == ref("a"))
        #expect(rightSlot.paneID == "sibling")
    }

    @Test func openPaneMemoryDropsEntriesForRefsThatAreNoLongerOpen() {
        let memory = OpenPaneMemory()
        OpenPaneSlot(memory: memory, selection: ref("a").memoryKey).remember("x")
        OpenPaneSlot(memory: memory, selection: ref("b").memoryKey).remember("y")
        memory.retain([ref("b").memoryKey])
        #expect(OpenPaneSlot(memory: memory, selection: ref("a").memoryKey).paneID == nil)
        #expect(OpenPaneSlot(memory: memory, selection: ref("b").memoryKey).paneID == "y")
    }

    @Test func openPaneMemoryIsClearedWhenBackingOut() {
        let memory = OpenPaneMemory()
        let slot = OpenPaneSlot(memory: memory, selection: "a")
        slot.remember("b")
        memory.forget()
        #expect(slot.paneID == nil)
    }

    @Test func closeDetailClosesOnlyItsSlot() {
        let box = LayoutBox(PaneLayout(left: ref("a"), right: ref("b")))
        CloseDetailAction(layout: box.binding, slot: .left, ref: ref("a"))()
        #expect(box.value.left == ref("b"))
        #expect(box.value.right == nil)
    }

    @Test func closeDetailLeavesANewerPaneInTheSlotOpen() {
        // A's close finishing after the user opened C in A's slot must not close C.
        let box = LayoutBox(PaneLayout(left: ref("c"), right: ref("b")))
        CloseDetailAction(layout: box.binding, slot: .left, ref: ref("a"))()
        #expect(box.value == PaneLayout(left: ref("c"), right: ref("b")))
    }

    @Test func compactCloseAlsoPopsTheStack() {
        var layout = PaneLayout(left: ref("a"), right: ref("b"))
        layout.compactDetailVisible = true
        let box = LayoutBox(layout)
        CloseDetailAction(layout: box.binding, slot: .left, ref: ref("a"), popsCompactStack: true)()
        #expect(box.value.left == ref("b"))
        #expect(!box.value.compactDetailVisible)
    }

    private func ref(_ id: String) -> PaneRef { PaneRef(spaceID: id, paneID: nil) }
}

private final class LayoutBox {
    var value: PaneLayout
    init(_ value: PaneLayout) { self.value = value }
    var binding: Binding<PaneLayout> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}
