import SwiftUI

// MARK: - Space row

struct PendingSpaceRow: View {
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: QuietListMetrics.columnSpacing) {
            CircularArcSpinner(size: QuietListMetrics.statusColumn)
            Text(title)
                .font(.appHeadlineSm)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { QuietListDivider() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityIdentifier("space-pending-card")
    }
}

/// A space group's root as a chat-style row: status column, title with the
/// last-activity time pinned top-right, and a line of tab/pane/agent counts.
struct SpaceRow: View {
    let group: SpaceGroup
    var isHighlighted = false
    /// The row open in the split view's detail column.
    var isSelected = false
    var lastUpdated: Date? = nil

    private var workspace: Workspace { group.root.workspace }

    var body: some View {
        HStack(alignment: .listTitleCenter, spacing: QuietListMetrics.columnSpacing) {
            StatusDot(status: group.root.status)
                .accessibilityLabel(group.root.status.label)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(group.root.label)
                        .font(.appHeadlineSm)
                        .lineLimit(1)
                    if workspace.focused {
                        FocusedMark()
                    }
                    Spacer(minLength: 8)
                    RowTimestamp(date: lastUpdated)
                }
                .alignmentGuide(.listTitleCenter) { $0[VerticalAlignment.center] }
                HStack(spacing: 12) {
                    StatChip(icon: "rectangle.split.3x1", value: "\(workspace.tabCount)", caption: "tabs")
                    StatChip(icon: "rectangle.split.2x2", value: "\(workspace.paneCount)", caption: "panes")
                    StatChip(icon: "sparkles", value: "\(group.root.agents.count)", caption: "agents")
                }
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background { RowHighlight(isActive: isHighlighted, isSelected: isSelected) }
        .overlay(alignment: .bottom) { QuietListDivider() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A linked worktree, indented under its space's row.
struct WorktreeRow: View {
    let space: Space
    var isHighlighted = false
    var isSelected = false
    var lastUpdated: Date? = nil

    var body: some View {
        HStack(alignment: .center, spacing: QuietListMetrics.columnSpacing) {
            StatusDot(status: space.status)
                .accessibilityLabel(space.status.label)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.jost(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(space.label)
                    .font(.jost(15, weight: .medium))
                    .lineLimit(1)
                if space.workspace.focused {
                    FocusedMark()
                }
                Spacer(minLength: 8)
                RowTimestamp(date: lastUpdated)
            }
        }
        .padding(.leading, QuietListMetrics.titleInset)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background { RowHighlight(isActive: isHighlighted, isSelected: isSelected) }
        .overlay(alignment: .bottom) { QuietListDivider(leadingInset: QuietListMetrics.titleInset * 2) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PendingWorktreeRow: View {
    let action: PendingWorktreeAction

    var body: some View {
        HStack(spacing: QuietListMetrics.columnSpacing) {
            CircularArcSpinner(size: 11)
                .frame(width: QuietListMetrics.statusColumn)
            Text(action.title)
                .font(.jost(14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, QuietListMetrics.titleInset)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { QuietListDivider(leadingInset: QuietListMetrics.titleInset * 2) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.title)
        .accessibilityIdentifier("worktree-pending-row")
        .id(PendingWorktreeAction.viewID)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

struct FocusedMark: View {
    var body: some View {
        Image(systemName: "scope")
            .font(.jost(11, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("Focused")
    }
}

struct RowHighlight: View {
    let isActive: Bool
    var isSelected = false

    var body: some View {
        let shape = RoundedRectangle.continuous(DesignSystem.CornerRadius.md)
        if isSelected {
            // Open in the detail column: a deeper accent tint with a thin accent outline.
            shape
                .fill(Theme.accent.opacity(0.16))
                .overlay { shape.strokeBorder(Theme.accent.opacity(0.7), lineWidth: 0.5) }
                .padding(.horizontal, -8)
        } else if isActive {
            shape
                .fill(Theme.selectedFill)
                .padding(.horizontal, -8)
        }
    }
}

extension View {
    /// Hides the List row chevron where SwiftUI supports it (iOS 26+).
    @ViewBuilder
    func hidesNavigationIndicator() -> some View {
        if #available(iOS 26.0, *) {
            navigationLinkIndicatorVisibility(.hidden)
        } else {
            self
        }
    }

    /// Strips List chrome so a row sits on the canvas like the Agents list.
    func quietListRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// Resolves the workspace's initial pane without adding an overview to the back stack.
struct WorkspacePaneView: View {
    let space: Space
    var initialPaneID: String? = nil

    @Environment(AppModel.self) private var appModel
    @Environment(\.openPaneMemory) private var openPaneMemory
    @State private var panes: [PaneEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var initialPane: PaneEntry? {
        if let initialPaneID {
            return panes.first { $0.id == initialPaneID }
        }
        return panes.first(where: \.focused)
            ?? panes.first { $0.tabId == space.workspace.activeTabId }
            ?? panes.first
    }

    var body: some View {
        Group {
            if let pane = initialPane {
                PaneDetailView(pane: pane, siblings: panes, restoring: openPaneMemory?.paneID)
            } else {
                VStack(spacing: 16) {
                    if isLoading {
                        CircularArcSpinner("Loading panes…")
                    } else if let errorMessage,
                              !HerdrConnection.isDisconnectionOrTransitionMessage(errorMessage) {
                        ErrorBanner(message: errorMessage, retry: {
                            Task { await loadPanes() }
                        })
                    } else {
                        ContentUnavailableView(
                            initialPaneID == nil ? "No panes available" : "Pane unavailable",
                            systemImage: "rectangle.split.2x2",
                            description: Text(initialPaneID == nil
                                ? "Open a pane in this workspace, then retry."
                                : "This agent's pane may have closed. Go back to refresh the agents list, or retry.")
                        )
                        Button("Retry") { Task { await loadPanes() } }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(space.label)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: space.id) { await loadPanes() }
        .connectionStatusBanner(appModel: appModel)
    }

    private func loadPanes() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await appModel.connection.paneList(workspaceId: space.workspace.workspaceId)
            try Task.checkCancellation()
            panes = fetched.filter { $0.workspaceId == space.workspace.workspaceId }
        } catch is CancellationError {
            return
        } catch {
            let message = HerdrConnection.friendlyMessage(for: error)
            if !HerdrConnection.isDisconnectionOrTransitionMessage(message) {
                errorMessage = message
            }
        }
    }
}
