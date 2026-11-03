import CoreGraphics
import Testing
@testable import Herdcats

@Suite("Pane drag and drop")
struct PaneDragDropTests {
    private let a = PaneRef(spaceID: "a", paneID: nil)
    private let b = PaneRef(spaceID: "b", paneID: "p2")

    // MARK: payload

    @Test func payloadRoundTrips() {
        for ref in [a, b] {
            #expect(PaneDragPayload.decode(PaneDragPayload.encode(ref)) == ref)
        }
    }

    @Test func payloadIsAPrefixedString() {
        #expect(PaneDragPayload.encode(a).hasPrefix("herdcats-pane:"))
    }

    @Test func garbagePayloadsDecodeToNil() {
        #expect(PaneDragPayload.decode("") == nil)
        #expect(PaneDragPayload.decode("hello") == nil)
        #expect(PaneDragPayload.decode("herdcats-pane:") == nil)
        #expect(PaneDragPayload.decode("herdcats-pane:{\"spaceID\": 3}") == nil)
        #expect(PaneDragPayload.decode("other:{\"spaceID\":\"a\"}") == nil)
    }

    // MARK: drop zones

    @Test func theLeftHalfMapsToLeftAndTheRightHalfToRight() {
        #expect(PaneDropZone.slot(atX: 0, width: 1000) == .left)
        #expect(PaneDropZone.slot(atX: 499, width: 1000) == .left)
        #expect(PaneDropZone.slot(atX: 500, width: 1000) == .right)
        #expect(PaneDropZone.slot(atX: 999, width: 1000) == .right)
    }

    @Test func aDegenerateWidthMapsToLeft() {
        #expect(PaneDropZone.slot(atX: 10, width: 0) == .left)
    }

    @Test func droppingOnTheLeftHalfOfASinglePaneSplitsWithTheDroppedPaneOnTheLeft() {
        var layout = PaneLayout(left: a)
        let accepted = layout.drop(PaneDragPayload.encode(b), onHalf: .left)
        #expect(accepted)
        #expect(layout.left == b)
        #expect(layout.right == a)
        #expect(layout.focused == .left)
    }

    @Test func droppingTheOpenPaneOnItsOwnHalfDoesNotSplit() {
        var layout = PaneLayout(left: a)
        layout.drop(PaneDragPayload.encode(a), onHalf: .left)
        #expect(layout == PaneLayout(left: a))
    }

    @Test func droppingOnTheLeftHalfWhileSplitReplacesTheLeftPane() {
        var layout = PaneLayout(left: a, right: b)
        let c = PaneRef(spaceID: "c", paneID: nil)
        layout.drop(PaneDragPayload.encode(c), onHalf: .left)
        #expect(layout.left == c)
        #expect(layout.right == b)
    }

    @Test func droppingOnTheRightHalfOfASinglePaneSplits() {
        var layout = PaneLayout(left: a)
        let accepted = layout.drop(PaneDragPayload.encode(b), onHalf: .right)
        #expect(accepted)
        #expect(layout.left == a)
        #expect(layout.right == b)
        #expect(layout.focused == .right)
    }

    @Test func droppingIntoAnEmptyDetailOpensIt() {
        var layout = PaneLayout()
        let accepted = layout.drop(PaneDragPayload.encode(a), onHalf: .right)
        #expect(accepted)
        #expect(layout.left == a)
    }

    @Test func undecodableDropsAreIgnored() {
        var layout = PaneLayout(left: a)
        let accepted = layout.drop("garbage", onHalf: .right)
        #expect(!accepted)
        #expect(layout == PaneLayout(left: a))
    }

    // MARK: partner title

    @Test func partnerTitlePrefersTheAgentThenTheSpace() {
        let agent = AgentEntry(
            agent: "codex", agentStatus: "idle", stateChangeSeq: nil, cwd: nil,
            paneId: "p2", tabId: "t", workspaceId: "b",
            terminalTitle: "Fix build", terminalTitleStripped: "Fix build", focused: false, revision: nil
        )
        let space = Space(
            workspace: Workspace(
                workspaceId: "b", label: "Beta", number: 1, tabCount: 1, paneCount: 1,
                activeTabId: "t", agentStatus: "idle", focused: false, worktree: nil
            ),
            agents: [agent]
        )
        #expect(b.displayTitle(in: [space]) == "Fix build")
        #expect(PaneRef(spaceID: "b", paneID: nil).displayTitle(in: [space]) == "Beta")
        #expect(PaneRef(spaceID: "b", paneID: "shell").displayTitle(in: [space]) == "Beta")
        #expect(a.displayTitle(in: [space]) == "a")
    }
}
