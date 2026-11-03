import Foundation

/// One tab of a space with its panes, for the Spaces list's tree. The list
/// separates tabs with a divider, so a tab's name isn't shown.
struct SpacePaneTab: Identifiable, Equatable {
    let id: String
    let panes: [PaneEntry]
}

/// The pure logic behind the panes and tabs listed under a space's row.
enum SpacePaneTree {
    /// Groups panes under their tab, in tab order. Empty tabs are dropped, and
    /// panes of a tab the list doesn't know still show up.
    static func tabs(tabs: [TabEntry], panes: [PaneEntry]) -> [SpacePaneTab] {
        let byTab = Dictionary(grouping: panes, by: \.tabId)
        var groups = tabs.sorted { $0.number < $1.number }.compactMap { tab -> SpacePaneTab? in
            guard let panes = byTab[tab.tabId], !panes.isEmpty else { return nil }
            return SpacePaneTab(id: tab.tabId, panes: panes)
        }
        let known = Set(tabs.map(\.tabId))
        for tabID in panes.map(\.tabId) where !known.contains(tabID) && !groups.contains(where: { $0.id == tabID }) {
            groups.append(SpacePaneTab(id: tabID, panes: byTab[tabID] ?? []))
        }
        return groups
    }

    /// The tabs' panes whose title matches `query`; tabs left empty are dropped.
    /// An empty query keeps everything.
    static func filter(_ tabs: [SpacePaneTab], query: String) -> [SpacePaneTab] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return tabs }
        return tabs.compactMap { tab in
            let panes = tab.panes.filter { PanePicker.matches($0.displayTitle, query: query) }
            return panes.isEmpty ? nil : SpacePaneTab(id: tab.id, panes: panes)
        }
    }

    // MARK: which pane a slot shows

    /// The pane a slot's ref ends up showing. The sibling the user switched to
    /// in the slot wins while it still exists, then the pane the ref names. A
    /// ref that names none opens the space's focused pane, else the one in its
    /// active tab, else the first, as the detail view resolves it.
    static func shownPaneID(of ref: PaneRef, remembered: String?, panes: [PaneEntry], activeTabID: String) -> String? {
        if let remembered, panes.contains(where: { $0.paneId == remembered }) { return remembered }
        if let paneID = ref.paneID { return paneID }
        return (panes.first(where: \.focused) ?? panes.first { $0.tabId == activeTabID } ?? panes.first)?.paneId
    }

    // MARK: expansion

    /// A space open in a slot unfolds by itself. The user's own choice wins.
    static func isExpanded(_ spaceID: String, overrides: [String: Bool], isOpen: Bool) -> Bool {
        overrides[spaceID] ?? isOpen
    }

    static func toggle(_ spaceID: String, overrides: inout [String: Bool], isOpen: Bool) {
        overrides[spaceID] = !isExpanded(spaceID, overrides: overrides, isOpen: isOpen)
    }

    static func pruned(_ overrides: [String: Bool], keeping spaceIDs: Set<String>) -> [String: Bool] {
        overrides.filter { spaceIDs.contains($0.key) }
    }

    static func encode(_ overrides: [String: Bool]) -> String {
        guard let data = try? JSONEncoder().encode(overrides) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ raw: String) -> [String: Bool] {
        (try? JSONDecoder().decode([String: Bool].self, from: Data(raw.utf8))) ?? [:]
    }

    // MARK: loading

    /// What a loaded tree was fetched against. A space whose counts moved
    /// gained or lost a tab or pane, so its tree is fetched again.
    struct LoadKey: Hashable {
        let tabCount: Int
        let paneCount: Int
    }

    static func needsReload(loaded: LoadKey?, current: LoadKey) -> Bool {
        loaded != current
    }
}
