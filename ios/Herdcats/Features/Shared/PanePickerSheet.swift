import SwiftUI

// MARK: - Picker logic (pure)

/// Which list the picker mirrors: the one the sidebar is showing.
enum PanePickerKind {
    case spaces, agents
}

enum PanePicker {
    static func title(slot: PaneLayout.Slot, layout: PaneLayout) -> String {
        guard layout.ref(in: slot) != nil else { return "Open on the Right" }
        return slot == .left ? "Replace Left Pane" : "Replace Right Pane"
    }

    /// Whether `text` matches a search query, ignoring case and surrounding spaces.
    /// An empty query matches everything.
    static func matches(_ text: String, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return needle.isEmpty || text.lowercased().contains(needle)
    }
}

// MARK: - Picker sheet

/// Chooses the pane for one slot, in the same list the sidebar shows: spaces
/// with their tabs and panes under them, or the agents.
struct PanePickerSheet: View {
    let slot: PaneLayout.Slot
    let kind: PanePickerKind
    @Binding var layout: PaneLayout
    var memory: OpenPaneMemory?

    @Environment(AppModel.self) private var appModel
    @Environment(SpacesModel.self) private var spacesModel: SpacesModel?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var paneTrees = SpacePaneTreeStore()

    private var groups: [SpaceGroup] { spacesModel?.visibleSpaceGroups ?? [] }

    private struct TreeTrigger: Hashable {
        let targets: [SpacePaneTreeTarget]
        let retryTick: Int
    }

    private var treeTargets: [SpacePaneTreeTarget] {
        guard kind == .spaces else { return [] }
        return groups.flatMap(\.members).map { space in
            SpacePaneTreeTarget(
                spaceID: space.id,
                workspaceID: space.workspace.workspaceId,
                key: .init(tabCount: space.workspace.tabCount, paneCount: space.workspace.paneCount)
            )
        }
    }

    private func open(_ ref: PaneRef) {
        layout.open(ref, in: slot, shown: OpenPaneMemory.resolver(memory))
        dismiss()
    }

    var body: some View {
        NavigationStack {
            List {
                switch kind {
                case .spaces: spaceRows
                case .agents: agentRows
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle(PanePicker.title(slot: slot, layout: layout))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .task(id: TreeTrigger(targets: treeTargets, retryTick: paneTrees.retryTick)) {
                await paneTrees.sync(treeTargets, connection: appModel.connection)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("pane-picker")
    }

    // MARK: Spaces

    /// A space shows while its name matches, or any of its panes does.
    private func shows(_ space: Space) -> Bool {
        if PanePicker.matches(space.label, query: query) { return true }
        guard case let .loaded(_, tabs) = paneTrees.loads[space.id] else { return false }
        return !SpacePaneTree.filter(tabs, query: query).isEmpty
    }

    @ViewBuilder
    private var spaceRows: some View {
        ForEach(groups) { group in
            if group.members.contains(where: shows) {
                if shows(group.root) {
                    pickerRow(PaneRef(spaceID: group.root.id, paneID: nil)) {
                        SpaceRow(
                            group: group,
                            isSelected: layout.badgeSlots(spaceID: group.root.id).isEmpty == false,
                            lastUpdated: spacesModel?.lastActivity(in: group.root)
                        )
                        .paneSlotBadge(layout.badgeSlots(spaceID: group.root.id), focused: layout.focused)
                    }
                    treeRows(for: group.root, indent: QuietListMetrics.titleInset)
                }
                ForEach(group.worktrees.filter(shows)) { space in
                    pickerRow(PaneRef(spaceID: space.id, paneID: nil)) {
                        WorktreeRow(
                            space: space,
                            isSelected: layout.badgeSlots(spaceID: space.id).isEmpty == false,
                            lastUpdated: spacesModel?.lastActivity(in: space)
                        )
                        .paneSlotBadge(layout.badgeSlots(spaceID: space.id), focused: layout.focused)
                    }
                    treeRows(for: space, indent: QuietListMetrics.titleInset * 2)
                }
            }
        }
    }

    private func treeRows(for space: Space, indent: CGFloat) -> some View {
        SpacePaneTreeRows(
            space: space,
            load: paneTrees.loads[space.id],
            indent: indent,
            layout: $layout,
            retry: { paneTrees.retry(space.id) },
            query: PanePicker.matches(space.label, query: query) ? "" : query,
            onOpen: open
        )
    }

    // MARK: Agents

    @ViewBuilder
    private var agentRows: some View {
        let items = AgentListItem.grouped(in: spacesModel?.spaces ?? [])
            .flatMap(\.items)
            .filter { PanePicker.matches($0.title, query: query) || PanePicker.matches($0.space.label, query: query) }
            .sorted(by: AgentListItem.attentionOrder)
        ForEach(items) { item in
            let ref = PaneRef(spaceID: item.space.id, paneID: item.agent.paneId)
            let badge = layout.badgeSlot(paneID: item.id, shown: OpenPaneMemory.resolver(memory))
            pickerRow(ref) {
                AgentListRow(
                    item: item,
                    isSelected: [layout.left, layout.right].contains { $0.flatMap(OpenPaneMemory.resolver(memory)) == item.id },
                    lastUpdated: spacesModel?.lastUpdatedByPaneID[item.id]
                )
                .paneSlotBadge(badge, focused: layout.focused)
            }
        }
    }

    private func pickerRow<Row: View>(_ ref: PaneRef, @ViewBuilder row: () -> Row) -> some View {
        Button { open(ref) } label: { row() }
            .buttonStyle(.plain)
            .quietListRow()
    }
}
