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
        // Another selection neither sees nor keeps it.
        #expect(OpenPaneSlot(memory: memory, selection: "c").paneID == nil)
        OpenPaneSlot(memory: memory, selection: "c").remember("d")
        #expect(slot.paneID == nil)
    }

    @Test func openPaneMemoryIsClearedWhenBackingOut() {
        let memory = OpenPaneMemory()
        let slot = OpenPaneSlot(memory: memory, selection: "a")
        slot.remember("b")
        memory.forget()
        #expect(slot.paneID == nil)
    }

    @Test func closeDetailClearsItsOwnSelection() {
        let box = SelectionBox("a")
        CloseDetailAction(selection: box.binding, id: "a")()
        #expect(box.value == nil)
    }

    @Test func closeDetailLeavesAnotherSelectionOpen() {
        // A's close finishing after the user opened B must not close B.
        let box = SelectionBox("b")
        CloseDetailAction(selection: box.binding, id: "a")()
        #expect(box.value == "b")
    }
}

private final class SelectionBox {
    var value: String?
    init(_ value: String?) { self.value = value }
    var binding: Binding<String?> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}
