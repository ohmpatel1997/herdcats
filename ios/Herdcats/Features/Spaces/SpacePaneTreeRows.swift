import Observation
import SwiftUI

/// A space whose tree is on screen, and what it was last fetched against.
struct SpacePaneTreeTarget: Hashable {
    let spaceID: String
    let workspaceID: String
    let key: SpacePaneTree.LoadKey
}

/// The tabs and panes fetched for each expanded space.
@Observable
@MainActor
final class SpacePaneTreeStore {
    enum Load {
        case loading
        case loaded(SpacePaneTree.LoadKey, [SpacePaneTab])
        case failed(SpacePaneTree.LoadKey, String)
    }

    private(set) var loads: [String: Load] = [:]
    /// Bumped by Retry so the loading task runs again for the same targets.
    private(set) var retryTick = 0

    func retry(_ spaceID: String) {
        loads[spaceID] = nil
        retryTick += 1
    }

    private func needsLoad(_ target: SpacePaneTreeTarget) -> Bool {
        switch loads[target.spaceID] {
        case nil: true
        // A run that was superseded mid-fetch leaves `.loading` behind for the
        // next run to pick up.
        case .loading: true
        case let .loaded(key, _): SpacePaneTree.needsReload(loaded: key, current: target.key)
        // A failure waits for Retry, so a flaky host isn't hammered.
        case let .failed(key, _): SpacePaneTree.needsReload(loaded: key, current: target.key)
        }
    }

    /// Fetches the tree for every target that is new or whose counts moved.
    func sync(_ targets: [SpacePaneTreeTarget], connection: HerdrConnection) async {
        await sync(targets) { workspaceID in
            async let tabs = connection.tabList(workspaceId: workspaceID)
            async let panes = connection.paneList(workspaceId: workspaceID)
            return SpacePaneTree.tabs(tabs: try await tabs, panes: try await panes)
        }
    }

    func sync(
        _ targets: [SpacePaneTreeTarget],
        fetch: (String) async throws -> [SpacePaneTab]
    ) async {
        for target in targets where needsLoad(target) {
            let previous = loads[target.spaceID]
            // Keep showing the old tree while a refresh runs.
            if case .loaded = previous {} else { loads[target.spaceID] = .loading }
            do {
                let tree = try await fetch(target.workspaceID)
                // A superseded run must not write over what the newer run loaded.
                guard !Task.isCancelled else {
                    if case .loading = loads[target.spaceID] { loads[target.spaceID] = previous }
                    return
                }
                loads[target.spaceID] = .loaded(target.key, tree)
            } catch {
                if Task.isCancelled || error is CancellationError {
                    // Superseded: let the next run start from what was there.
                    // Leave the slot alone if a newer run has already filled it.
                    if case .loading = loads[target.spaceID] { loads[target.spaceID] = previous }
                    return
                }
                loads[target.spaceID] = .failed(target.key, HerdrConnection.friendlyMessage(for: error))
            }
        }
    }
}

/// The small count pill on a space row that folds or unfolds its tree.
struct SpacePaneTreePill: View {
    let paneCount: Int
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("\(paneCount)")
                    .font(.jost(12, weight: .medium))
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.jost(10, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .foregroundStyle(.secondary)
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide panes" : "Show panes")
        .accessibilityValue("\(paneCount)")
        .accessibilityIdentifier("space-panes-toggle")
    }
}

/// The rows under an expanded space: its tabs as headers, its panes under them.
struct SpacePaneTreeRows: View {
    let space: Space
    let load: SpacePaneTreeStore.Load?
    /// How far the rows sit in from the row above (worktrees are indented already).
    let indent: CGFloat
    @Binding var layout: PaneLayout
    let retry: () -> Void
    /// Keeps only the panes whose title matches (the picker's search).
    var query = ""
    /// Set by the pane picker: a tap hands the pane over instead of opening it
    /// in the focused slot, and rows are neither draggable nor given a menu.
    var onOpen: ((PaneRef) -> Void)?

    @Environment(\.paneMemoryStore) private var memory

    /// The pane each open slot of this space shows, in a split or not.
    private func shownPanes(in panes: [PaneEntry]) -> [(slot: PaneLayout.Slot, paneID: String)] {
        [(PaneLayout.Slot.left, layout.left), (.right, layout.right)].compactMap { slot, ref in
            guard let ref, ref.spaceID == space.id,
                  let paneID = SpacePaneTree.shownPaneID(
                      of: ref,
                      remembered: memory?.paneID(forSelection: ref.memoryKey),
                      panes: panes,
                      activeTabID: space.workspace.activeTabId
                  ) else { return nil }
            return (slot, paneID)
        }
    }

    var body: some View {
        switch load {
        case nil, .loading:
            HStack(spacing: 8) {
                CircularArcSpinner(size: 11)
                Text("Loading panes…")
                    .font(.jost(.footnote))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, indent)
            .padding(.vertical, 8)
            .quietListRow()
        case let .failed(_, message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.jost(.footnote))
                    .foregroundStyle(Theme.destructive)
                Button("Retry", action: retry)
                    .font(.jost(.footnote, weight: .semibold))
                    .accessibilityIdentifier("space-panes-retry")
            }
            .padding(.leading, indent)
            .padding(.vertical, 8)
            .quietListRow()
        case let .loaded(_, loadedTabs):
            let tabs = SpacePaneTree.filter(loadedTabs, query: query)
            let shown = shownPanes(in: tabs.flatMap(\.panes))
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                if index > 0 {
                    // A line between the space's tabs, instead of their names.
                    QuietListDivider(leadingInset: indent)
                        .padding(.vertical, 3)
                        .quietListRow()
                }
                ForEach(tab.panes) { pane in
                    paneRow(pane, shown: shown)
                }
            }
        }
    }

    private func paneRow(_ pane: PaneEntry, shown: [(slot: PaneLayout.Slot, paneID: String)]) -> some View {
        let ref = PaneRef(spaceID: space.id, paneID: pane.paneId)
        let slots = shown.filter { $0.paneID == pane.paneId }.map(\.slot)
        return Button {
            if let onOpen { onOpen(ref) } else { layout.openInFocused(ref, shown: OpenPaneMemory.resolver(memory)) }
        } label: {
            PaneTreeRow(pane: pane, indent: indent, isSelected: !slots.isEmpty)
                // Tags only while split, like the space rows.
                .paneSlotBadge(layout.isSplit ? slots : [], focused: layout.focused)
        }
        .buttonStyle(.plain)
        .paneDraggable(ref, title: pane.displayTitle, enabled: onOpen == nil)
        .contextMenu {
            if onOpen == nil {
                ForEach(PaneOpenAction.actions(for: ref, layout: $layout, memory: memory)) { action in
                    Button(action: action.perform) { Label(action.title, systemImage: action.systemImage) }
                }
            }
        }
        .quietListRow()
        .accessibilityIdentifier("space-pane-row-\(pane.paneId)")
    }
}

private struct PaneTreeRow: View {
    @Environment(\.paneRowBadges) private var paneBadges
    let pane: PaneEntry
    let indent: CGFloat
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: pane.status)
                .frame(width: QuietListMetrics.statusColumn)
            Text(pane.displayTitle)
                .font(.jost(14))
                .lineLimit(1)
            Spacer(minLength: 8)
            ForEach(paneBadges, id: \.slot) { PaneSlotTag(badge: $0) }
        }
        .padding(.leading, indent)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background { RowHighlight(isActive: false, isSelected: isSelected) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
