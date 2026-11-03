import Testing
@testable import Herdcats

@Suite("Space pane tree")
struct SpacePaneTreeTests {
    private func tab(_ id: String, _ label: String, number: Int) -> TabEntry {
        TabEntry(tabId: id, workspaceId: "w", label: label, number: number, paneCount: 1, agentStatus: "idle", focused: false)
    }

    private func pane(_ id: String, tab: String, title: String = "t") -> PaneEntry {
        PaneEntry(
            paneId: id, tabId: tab, workspaceId: "w", label: nil, agent: nil, agentStatus: "idle",
            cwd: nil, terminalTitle: title, terminalTitleStripped: title, focused: false, revision: nil
        )
    }

    // MARK: tabs

    @Test func panesGroupUnderTheirTabInTabOrder() {
        let tabs = [tab("t2", "tests", number: 2), tab("t1", "main", number: 1)]
        let panes = [pane("p1", tab: "t1"), pane("p2", tab: "t2"), pane("p3", tab: "t1")]
        let result = SpacePaneTree.tabs(tabs: tabs, panes: panes)
        #expect(result.map(\.id) == ["t1", "t2"])
        #expect(result[0].panes.map(\.paneId) == ["p1", "p3"])
        #expect(result[1].panes.map(\.paneId) == ["p2"])
    }

    @Test func emptyTabsAreDropped() {
        let result = SpacePaneTree.tabs(
            tabs: [tab("t1", "main", number: 1), tab("t2", "empty", number: 2)],
            panes: [pane("p1", tab: "t1")]
        )
        #expect(result.map(\.id) == ["t1"])
    }

    @Test func panesOfAnUnlistedTabStillAppear() {
        let result = SpacePaneTree.tabs(tabs: [], panes: [pane("p1", tab: "gone")])
        #expect(result.count == 1)
        #expect(result[0].panes.map(\.paneId) == ["p1"])
    }

    @Test func searchKeepsMatchingPanesAndDropsEmptyTabs() {
        let tabs = [
            SpacePaneTab(id: "t1", panes: [pane("p1", tab: "t1", title: "Fix build"), pane("p2", tab: "t1", title: "zsh")]),
            SpacePaneTab(id: "t2", panes: [pane("p3", tab: "t2", title: "Write docs")]),
        ]
        let result = SpacePaneTree.filter(tabs, query: " FIX ")
        #expect(result.map(\.id) == ["t1"])
        #expect(result[0].panes.map(\.paneId) == ["p1"])
        #expect(SpacePaneTree.filter(tabs, query: "") == tabs)
        #expect(SpacePaneTree.filter(tabs, query: "nope").isEmpty)
    }

    // MARK: expansion

    @Test func openSpacesUnfoldByDefault() {
        #expect(SpacePaneTree.isExpanded("w1", overrides: [:], isOpen: true))
        #expect(!SpacePaneTree.isExpanded("w1", overrides: [:], isOpen: false))
    }

    @Test func anOverrideBeatsTheDefault() {
        #expect(!SpacePaneTree.isExpanded("w1", overrides: ["w1": false], isOpen: true))
        #expect(SpacePaneTree.isExpanded("w1", overrides: ["w1": true], isOpen: false))
    }

    @Test func togglingStoresTheOppositeOfWhatShows() {
        var overrides: [String: Bool] = [:]
        SpacePaneTree.toggle("w1", overrides: &overrides, isOpen: true)
        #expect(overrides["w1"] == false)
        SpacePaneTree.toggle("w1", overrides: &overrides, isOpen: true)
        #expect(overrides["w1"] == true)
    }

    @Test func overridesRoundTripThroughStorage() {
        let overrides = ["w1": true, "w2": false]
        #expect(SpacePaneTree.decode(SpacePaneTree.encode(overrides)) == overrides)
        #expect(SpacePaneTree.decode("").isEmpty)
        #expect(SpacePaneTree.decode("garbage").isEmpty)
    }

    @Test func pruningDropsOverridesForSpacesThatAreGone() {
        let kept = SpacePaneTree.pruned(["w1": true, "w2": false], keeping: ["w1"])
        #expect(kept == ["w1": true])
    }

    // MARK: loading

    @Test func aLoadIsStaleOnlyWhenTheSpacesCountsMoved() {
        let key = SpacePaneTree.LoadKey(tabCount: 2, paneCount: 3)
        #expect(!SpacePaneTree.needsReload(loaded: key, current: key))
        #expect(SpacePaneTree.needsReload(loaded: key, current: .init(tabCount: 2, paneCount: 4)))
        #expect(SpacePaneTree.needsReload(loaded: nil, current: key))
    }

    // MARK: which pane a slot shows

    private func pane(_ id: String, tab: String, focused: Bool) -> PaneEntry {
        PaneEntry(
            paneId: id, tabId: tab, workspaceId: "w", label: nil, agent: nil, agentStatus: "idle",
            cwd: nil, terminalTitle: "t", terminalTitleStripped: "t", focused: focused, revision: nil
        )
    }

    @Test func aPaneRefShowsItsOwnPane() {
        let shown = SpacePaneTree.shownPaneID(
            of: PaneRef(spaceID: "w", paneID: "p2"), remembered: nil,
            panes: [pane("p1", tab: "t1", focused: true)], activeTabID: "t1"
        )
        #expect(shown == "p2")
    }

    @Test func aSiblingSwitchedToInASlotBeatsTheRefsOwnPane() {
        let panes = [pane("p1", tab: "t1", focused: true), pane("p2", tab: "t1", focused: false)]
        let ref = PaneRef(spaceID: "w", paneID: "p1")
        #expect(SpacePaneTree.shownPaneID(of: ref, remembered: "p2", panes: panes, activeTabID: "t1") == "p2")
        // A remembered pane that has since closed falls back to the ref's own.
        #expect(SpacePaneTree.shownPaneID(of: ref, remembered: "gone", panes: panes, activeTabID: "t1") == "p1")
    }

    @Test func aSpaceRefShowsTheRememberedSiblingWhenItStillExists() {
        let panes = [pane("p1", tab: "t1", focused: true), pane("p2", tab: "t1", focused: false)]
        let ref = PaneRef(spaceID: "w", paneID: nil)
        #expect(SpacePaneTree.shownPaneID(of: ref, remembered: "p2", panes: panes, activeTabID: "t1") == "p2")
        #expect(SpacePaneTree.shownPaneID(of: ref, remembered: "gone", panes: panes, activeTabID: "t1") == "p1")
    }

    @Test func aSpaceRefFallsBackToFocusedThenActiveTabThenFirst() {
        let ref = PaneRef(spaceID: "w", paneID: nil)
        let focused = [pane("p1", tab: "t1", focused: false), pane("p2", tab: "t2", focused: true)]
        #expect(SpacePaneTree.shownPaneID(of: ref, remembered: nil, panes: focused, activeTabID: "t1") == "p2")
        let none = [pane("p1", tab: "t1", focused: false), pane("p2", tab: "t2", focused: false)]
        #expect(SpacePaneTree.shownPaneID(of: ref, remembered: nil, panes: none, activeTabID: "t2") == "p2")
        #expect(SpacePaneTree.shownPaneID(of: ref, remembered: nil, panes: none, activeTabID: "zz") == "p1")
        #expect(SpacePaneTree.shownPaneID(of: ref, remembered: nil, panes: [], activeTabID: "t1") == nil)
    }
}

@Suite("Space pane tree store")
@MainActor
struct SpacePaneTreeStoreTests {
    private func target(_ id: String) -> SpacePaneTreeTarget {
        SpacePaneTreeTarget(spaceID: id, workspaceID: "w-\(id)", key: .init(tabCount: 1, paneCount: 1))
    }

    private func isLoaded(_ load: SpacePaneTreeStore.Load?) -> Bool {
        if case .loaded = load { return true }
        return false
    }

    @Test func aSupersededRunDoesNotLeaveItsSpaceStuckLoading() async {
        let store = SpacePaneTreeStore()
        let first = Task { @MainActor in
            await store.sync([target("a")]) { _ in
                try await Task.sleep(for: .seconds(60))
                return []
            }
        }
        // Let the first run start its fetch, then supersede it with a run for two spaces.
        while store.loads["a"] == nil { await Task.yield() }
        first.cancel()
        await first.value
        await store.sync([target("a"), target("b")]) { _ in [] }
        #expect(isLoaded(store.loads["a"]))
        #expect(isLoaded(store.loads["b"]))
    }

    @Test func aRunThatStartsWhileAnotherIsMidFetchStillLoadsThatSpace() async {
        let store = SpacePaneTreeStore()
        let first = Task { @MainActor in
            await store.sync([target("a")]) { _ in
                try await Task.sleep(for: .seconds(60))
                return []
            }
        }
        while store.loads["a"] == nil { await Task.yield() }
        // The new run starts before the old one has seen its cancellation.
        first.cancel()
        await store.sync([target("a"), target("b")]) { _ in [] }
        await first.value
        #expect(isLoaded(store.loads["a"]))
        #expect(isLoaded(store.loads["b"]))
    }

    @Test func aFailedFetchShowsTheFriendlyMessageAndWaitsForRetry() async {
        let store = SpacePaneTreeStore()
        struct Boom: Error {}
        await store.sync([target("a")]) { _ in throw Boom() }
        guard case .failed = store.loads["a"] else { Issue.record("expected failed"); return }
        await store.sync([target("a")]) { _ in [] }
        guard case .failed = store.loads["a"] else { Issue.record("a failure waits for Retry"); return }
        store.retry("a")
        await store.sync([target("a")]) { _ in [] }
        #expect(isLoaded(store.loads["a"]))
    }
}
