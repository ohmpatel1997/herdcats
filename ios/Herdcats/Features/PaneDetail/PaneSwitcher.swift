import SwiftUI

/// A pane or tab still being created, shown in the switcher until Herdr returns it.
struct PendingPanePlaceholder: Equatable {
    static let viewID = "pane-pending"

    let title: String
    /// Pane the new one is split from; nil places a new tab at the end.
    let afterPaneID: String?
    let kind: AddPaneKind

    static func title(name: String, kind: AddPaneKind = .pane) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return kind == .pane ? "Opening pane…" : "Opening tab…"
    }
}

/// Snap rules for the pane switcher's vertical drag between cards and chips.
enum PaneSwitcherCollapse {
    /// Drag distance past which releasing the strip toggles its state.
    static let snapDistance: CGFloat = 24

    /// Panes narrower than this start with the chip strip, so the strip
    /// doesn't eat a split pane's terminal. 0 means not measured yet.
    static let narrowPaneWidth: CGFloat = 420

    static func prefersCompact(paneWidth: CGFloat) -> Bool {
        paneWidth > 0 && paneWidth < narrowPaneWidth
    }

    /// Whether the switcher is compact after a vertical drag on it ends.
    /// Dragging down expands; dragging up collapses.
    static func isCompact(afterDragFrom startCompact: Bool, translation: CGFloat) -> Bool {
        startCompact ? translation <= snapDistance : translation < -snapDistance
    }

    /// Strip height while it follows the finger, clamped between both states.
    static func height(
        isCompact: Bool,
        translation: CGFloat?,
        compactHeight: CGFloat,
        expandedHeight: CGFloat
    ) -> CGFloat {
        let base = isCompact ? compactHeight : expandedHeight
        guard let translation else { return base }
        return min(expandedHeight, max(compactHeight, base + translation))
    }
}

/// Each selectable pane gets its own solid card in the expanded and compact rows:
/// `--surface` with a `--border` outline, or `--raised` with an accent outline
/// when selected, like the website's active rows.
struct PaneSwitcherGlassItem<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let shape: S
    var isSelected = false

    func body(content: Content) -> some View {
        content
            .background(isSelected ? Theme.selectedFill : Theme.cardBackground, in: shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(Theme.accent, lineWidth: 1.5)
                        .allowsHitTesting(false)
                } else if !reduceTransparency {
                    // A fine outer rim and inset highlight give the edge depth
                    // while preserving the nearly opaque field background.
                    shape.strokeBorder(
                        .black.opacity(colorScheme == .dark ? 0.45 : 0.18),
                        lineWidth: 0.5
                    )
                    .allowsHitTesting(false)
                } else {
                    shape.strokeBorder(Theme.hairline, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if !isSelected && !reduceTransparency {
                    shape.inset(by: 0.75).strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(colorScheme == .dark ? 0.4 : 0.95), location: 0),
                                .init(color: .clear, location: 0.15),
                                .init(color: .clear, location: 0.85),
                                .init(color: .white.opacity(colorScheme == .dark ? 0.35 : 0.85), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
                }
            }
    }
}

/// The same pane identity and status shown in space detail, presented as
/// separate translucent cards. Drag up to collapse to a row of glass chips.
/// A dashed tile at the end of the strip for the pane open in the other half
/// of a split, shown when the split is folded to one pane.
struct PanePartnerTile {
    let title: String
    let focus: () -> Void
}

struct PaneSwitcher: View {
    let panes: [PaneEntry]
    let tabs: [TabEntry]
    @Binding var selection: String
    @Binding var isCompact: Bool
    var lastUpdatedByPaneID: [String: Date] = [:]
    var pendingPane: PendingPanePlaceholder?
    var isAddDisabled = false
    var allowsMutations = true
    var partnerTile: PanePartnerTile?
    var onAdd: () -> Void
    var onRename: (PaneEntry) -> Void = { _ in }
    var onKill: (PaneEntry) -> Void = { _ in }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .subheadline) private var cardHeight = 100
    @ScaledMetric(relativeTo: .caption) private var chipHeight = 30
    /// Vertical translation while the strip follows a drag; nil otherwise.
    @State private var dragTranslation: CGFloat?
    /// Set once a drag commits to horizontal so it is left to the scroll view.
    @State private var isHorizontalDrag = false

    init(
        panes: [PaneEntry],
        tabs: [TabEntry],
        selection: Binding<String>,
        isCompact: Binding<Bool>,
        lastUpdatedByPaneID: [String: Date] = [:],
        pendingPane: PendingPanePlaceholder? = nil,
        isAddDisabled: Bool = false,
        allowsMutations: Bool = true,
        partnerTile: PanePartnerTile? = nil,
        onAdd: @escaping () -> Void,
        onRename: @escaping (PaneEntry) -> Void = { _ in },
        onKill: @escaping (PaneEntry) -> Void = { _ in }
    ) {
        self.panes = panes
        self.tabs = tabs
        self._selection = selection
        self._isCompact = isCompact
        self.lastUpdatedByPaneID = lastUpdatedByPaneID
        self.pendingPane = pendingPane
        self.isAddDisabled = isAddDisabled
        self.allowsMutations = allowsMutations
        self.partnerTile = partnerTile
        self.onAdd = onAdd
        self.onRename = onRename
        self.onKill = onKill
    }

    private var expandedHeight: CGFloat { cardHeight + 20 }
    private var compactHeight: CGFloat { chipHeight + 12 }

    private var orderedPanes: [PaneEntry] {
        Self.ordered(panes: panes, tabs: tabs)
    }

    /// Display order of the switcher: grouped by tab, orphans last.
    static func ordered(panes: [PaneEntry], tabs: [TabEntry]) -> [PaneEntry] {
        let knownTabIDs = Set(tabs.map(\.id))
        return tabs.flatMap { tab in panes.filter { $0.tabId == tab.id } }
            + panes.filter { !knownTabIDs.contains($0.tabId) }
    }

    private func paneAccessibilityLabel(for pane: PaneEntry) -> String {
        var parts = [pane.displayTitle]
        if let agent = pane.agent {
            parts.append(AgentKindVisual.displayName(for: agent))
        } else {
            parts.append("Command line")
        }
        if let updated = lastUpdatedByPaneID[pane.paneId] {
            parts.append(PaneUpdatedFormat.label(for: updated))
        }
        parts.append(pane.status.label)
        if pane.focused {
            parts.append("Focused in Herdr")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        let height = PaneSwitcherCollapse.height(
            isCompact: isCompact,
            translation: dragTranslation,
            compactHeight: compactHeight,
            expandedHeight: expandedHeight
        )
        let showsCards = height > (compactHeight + expandedHeight) / 2

        ZStack(alignment: .top) {
            cardsRow
                .opacity(showsCards ? 1 : 0)
                .allowsHitTesting(showsCards)
                .accessibilityHidden(!showsCards)
            chipsRow
                .opacity(showsCards ? 0 : 1)
                .allowsHitTesting(!showsCards)
                .accessibilityHidden(showsCards)
        }
        .frame(height: height, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(collapseDrag)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: isCompact ? "Show Pane Cards" : "Show Pane Chips") {
            withAnimation(.snappy(duration: 0.28)) {
                isCompact.toggle()
            }
        }
    }

    private var collapseDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isHorizontalDrag else { return }
                if dragTranslation == nil {
                    guard abs(value.translation.height) > abs(value.translation.width) else {
                        isHorizontalDrag = true
                        return
                    }
                }
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                defer { isHorizontalDrag = false }
                guard dragTranslation != nil else { return }
                let next = PaneSwitcherCollapse.isCompact(
                    afterDragFrom: isCompact,
                    translation: value.translation.height
                )
                if next != isCompact {
                    HapticFeedback.impact(.light)
                }
                withAnimation(.snappy(duration: 0.28)) {
                    isCompact = next
                    dragTranslation = nil
                }
            }
    }

    private var cardsRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    HStack(spacing: 8) {
                        let ordered = orderedPanes
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, pane in
                            if index > 0, ordered[index - 1].tabId != pane.tabId {
                                tabDivider(height: cardHeight * 0.62)
                            }

                            Button {
                                selection = pane.id
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        StatusDot(status: pane.status)
                                            .alignmentGuide(.firstTextBaseline) { dimensions in
                                                dimensions.height * 0.5 + 4.5
                                            }
                                        Text(pane.displayTitle)
                                            .font(.jost(.subheadline, weight: .medium))
                                            .lineLimit(2, reservesSpace: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    HStack(spacing: 6) {
                                        if let agent = pane.agent {
                                            AgentBadge(kind: agent)
                                                .opacity(0.7)
                                        } else {
                                            CommandLineBadge()
                                                .opacity(0.7)
                                        }
                                        Spacer(minLength: 0)
                                        if let updated = lastUpdatedByPaneID[pane.paneId] {
                                            Text(PaneUpdatedFormat.label(for: updated))
                                                .font(.jost(.caption2))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .padding(12)
                                .frame(width: 260, height: cardHeight, alignment: .leading)
                                .contentShape(RoundedRectangle.continuous(DesignSystem.CornerRadius.lg))
                                .modifier(PaneSwitcherGlassItem(
                                    shape: RoundedRectangle.continuous(DesignSystem.CornerRadius.lg),
                                    isSelected: selection == pane.id
                                ))
                                .herdrFocusLine(pane.focused, in: RoundedRectangle.continuous(DesignSystem.CornerRadius.lg))
                            }
                            .buttonStyle(.herdrCard)
                            .contextMenu { paneMenu(for: pane) }
                            .paneDraggable(dragRef(for: pane), title: pane.displayTitle, enabled: horizontalSizeClass == .regular)
                            .accessibilityLabel(paneAccessibilityLabel(for: pane))
                            .accessibilityAddTraits(selection == pane.id ? .isSelected : [])
                            .id(pane.id)

                            if pendingPane?.afterPaneID == pane.id {
                                pendingCard
                            }
                        }
                        if let pendingPane, !ordered.contains(where: { $0.id == pendingPane.afterPaneID }) {
                            if pendingPane.kind == .tab, !ordered.isEmpty {
                                tabDivider(height: cardHeight * 0.62)
                            }
                            pendingCard
                        }

                        if allowsMutations {
                            Button(action: onAdd) {
                                Image(systemName: "plus")
                                    .font(.jost(.title2, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 56, height: cardHeight)
                                    .contentShape(RoundedRectangle.continuous(DesignSystem.CornerRadius.lg))
                                    .modifier(PaneSwitcherGlassItem(
                                        shape: RoundedRectangle.continuous(DesignSystem.CornerRadius.lg)
                                    ))
                            }
                            .buttonStyle(.herdrCard)
                            .disabled(isAddDisabled)
                            .opacity(isAddDisabled ? 0.45 : 1)
                            .accessibilityLabel("Add Pane or Tab")
                            .accessibilityIdentifier("pane-add-button")
                            .id("pane-add")
                        }

                        if let partnerTile {
                            partnerCard(partnerTile)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, id in
                withAnimation(.snappy(duration: 0.28)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: isCompact) { _, compact in
                if !compact { proxy.scrollTo(selection, anchor: .center) }
            }
            .onChange(of: pendingPane) { _, pending in
                if pending != nil {
                    withAnimation { proxy.scrollTo(PendingPanePlaceholder.viewID, anchor: .center) }
                }
            }
        }
    }

    private var chipsRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    HStack(spacing: 6) {
                        let ordered = orderedPanes
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, pane in
                            if index > 0, ordered[index - 1].tabId != pane.tabId {
                                tabDivider(height: 20)
                            }
                            chip(for: pane)
                            if pendingPane?.afterPaneID == pane.id {
                                pendingChip
                            }
                        }
                        if let pendingPane, !ordered.contains(where: { $0.id == pendingPane.afterPaneID }) {
                            if pendingPane.kind == .tab, !ordered.isEmpty {
                                tabDivider(height: 20)
                            }
                            pendingChip
                        }

                        if allowsMutations {
                            Button(action: onAdd) {
                                Image(systemName: "plus")
                                    .font(.jost(.caption, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: chipHeight, height: chipHeight)
                                    .contentShape(Capsule())
                                    .modifier(PaneSwitcherGlassItem(shape: Capsule()))
                            }
                            .buttonStyle(.herdrCard)
                            .disabled(isAddDisabled)
                            .opacity(isAddDisabled ? 0.45 : 1)
                            .accessibilityLabel("Add Pane or Tab")
                            .accessibilityIdentifier("pane-add-button")
                            .id("pane-add")
                        }

                        if let partnerTile {
                            partnerChip(partnerTile)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, id in
                withAnimation(.snappy(duration: 0.28)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: isCompact) { _, compact in
                if compact { proxy.scrollTo(selection, anchor: .center) }
            }
            .onChange(of: pendingPane) { _, pending in
                if pending != nil {
                    withAnimation { proxy.scrollTo(PendingPanePlaceholder.viewID, anchor: .center) }
                }
            }
        }
    }

    private func partnerCard(_ tile: PanePartnerTile) -> some View {
        let shape = RoundedRectangle.continuous(DesignSystem.CornerRadius.lg)
        return Button(action: tile.focus) {
            VStack(spacing: 6) {
                Image(systemName: "square.on.square")
                    .font(.jost(.title3, weight: .semibold))
                Text(tile.title)
                    .font(.jost(.caption, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.accent)
            .padding(12)
            .frame(width: 140, height: cardHeight)
            .contentShape(shape)
            .overlay(shape.strokeBorder(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.herdrCard)
        .accessibilityLabel("Other pane: \(tile.title)")
        .accessibilityHint("Shows the pane open on the other side")
        .accessibilityIdentifier("pane-partner-tile")
    }

    private func partnerChip(_ tile: PanePartnerTile) -> some View {
        Button(action: tile.focus) {
            HStack(spacing: 6) {
                Image(systemName: "square.on.square")
                Text(tile.title).lineLimit(1)
            }
            .font(.jost(.caption, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .frame(height: chipHeight)
            .contentShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.herdrCard)
        .accessibilityLabel("Other pane: \(tile.title)")
        .accessibilityHint("Shows the pane open on the other side")
        .accessibilityIdentifier("pane-partner-tile")
    }

    private func chip(for pane: PaneEntry) -> some View {
        let isSelected = selection == pane.id
        return Button {
            selection = pane.id
        } label: {
            HStack(spacing: 6) {
                StatusDot(status: pane.status)
                Text(pane.displayTitle)
                    .font(.jost(.caption, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: 160)
            .frame(height: chipHeight)
            .contentShape(Capsule())
            .modifier(PaneSwitcherGlassItem(shape: Capsule(), isSelected: isSelected))
            .herdrFocusLine(
                pane.focused,
                in: Capsule(),
                thickness: 2
            )
        }
        .buttonStyle(.herdrCard)
        .contextMenu { paneMenu(for: pane) }
        .paneDraggable(dragRef(for: pane), title: pane.displayTitle, enabled: horizontalSizeClass == .regular)
        .accessibilityLabel(paneAccessibilityLabel(for: pane))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(pane.id)
    }

    /// What a dragged card or chip opens in the split view's detail column.
    private func dragRef(for pane: PaneEntry) -> PaneRef {
        PaneRef(spaceID: pane.workspaceId, paneID: pane.paneId)
    }

    /// Non-interactive stand-in for a pane that Herdr is still creating.
    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CircularArcSpinner(size: 14)
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions.height * 0.5 + 4.5
                    }
                Text(pendingPane?.title ?? "")
                    .font(.jost(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 260, height: cardHeight, alignment: .leading)
        .modifier(PaneSwitcherGlassItem(
            shape: RoundedRectangle.continuous(DesignSystem.CornerRadius.lg)
        ))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pendingAccessibilityLabel)
        .accessibilityIdentifier("pane-pending-card")
        .id(PendingPanePlaceholder.viewID)
    }

    private var pendingChip: some View {
        HStack(spacing: 6) {
            CircularArcSpinner(size: 11)
            Text(pendingPane?.title ?? "")
                .font(.jost(.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: 160)
        .frame(height: chipHeight)
        .modifier(PaneSwitcherGlassItem(shape: Capsule()))
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pendingAccessibilityLabel)
        .accessibilityIdentifier("pane-pending-chip")
        .id(PendingPanePlaceholder.viewID)
    }

    private var pendingAccessibilityLabel: String {
        let kind = pendingPane?.kind == .tab ? "tab" : "pane"
        return "\(pendingPane?.title ?? "New \(kind)"), creating \(kind)"
    }

    private func tabDivider(height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.45))
            .frame(width: 1, height: height)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func paneMenu(for pane: PaneEntry) -> some View {
        if allowsMutations {
            Button {
                onRename(pane)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .disabled(isAddDisabled)
            .accessibilityIdentifier("pane-card-rename-\(pane.id)")

            Button(role: .destructive) {
                onKill(pane)
            } label: {
                Label("Kill", systemImage: "xmark.circle")
            }
            .disabled(isAddDisabled)
            .accessibilityIdentifier("pane-card-kill-\(pane.id)")
        }
    }
}
