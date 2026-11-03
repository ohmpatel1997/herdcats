import Observation
import SwiftUI

// MARK: - Spaces screen

struct SpacesScreen: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ActiveMachine.self) private var activeMachine: ActiveMachine?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let model: SpacesModel
    /// The open panes, shared with the Agents tab and by the split view and
    /// the compact stack, so folding or unfolding keeps the same panes open.
    @Binding var layout: PaneLayout
    /// Each open item's sibling pane, owned above both tabs so a rebuilt detail restores it.
    var paneMemory = OpenPaneMemory()

    /// Open spaces as last seen in the list, so a refresh that drops one
    /// doesn't blank its pane mid-read.
    @State private var lastSeen: [String: Space] = [:]

    /// Panes and tabs listed under each expanded space, on regular width.
    @State private var paneTrees = SpacePaneTreeStore()
    /// Spaces the user folded or unfolded by hand, per window. Spaces open
    /// in a slot unfold by themselves unless folded here.
    @SceneStorage("spacePaneTreeOverrides") private var treeOverridesRaw = ""

    @AppStorage(SpaceSortPreference.storageKey)
    private var sortRaw = SpaceSortPreference.default.rawValue

    @State private var isShowingCreateSpace = false
    /// Set when the user picks an option in the drawer; executed in
    /// `onDismiss` so the async work is not cancelled by sheet teardown.
    @State private var pendingCreateSpace: CreateSpaceRequest?

    @State private var openWorktreeTarget: Space?
    @State private var pendingOpenWorktree: OpenWorktreeRequest?

    @State private var createWorktreeTarget: Space?
    @State private var pendingCreateWorktree: CreateWorktreeRequest?

    @State private var renameTarget: Space?
    @State private var renameText = ""
    @State private var isShowingRenameAlert = false
    @State private var closeTarget: Space?
    @State private var isShowingCloseConfirmation = false
    /// Space whose "More" drawer is open from a swipe or long press.
    @State private var actionsTarget: Space?
    /// Chosen in the drawer; performed in `onDismiss` so the next sheet or
    /// alert is not presented while the drawer is still on screen.
    @State private var pendingSpaceAction: (action: SpaceAction, space: Space)?

    private var sort: SpaceSortPreference {
        SpaceSortPreference(rawValue: sortRaw) ?? .default
    }

    private var sortSelection: Binding<SpaceSortPreference> {
        Binding(
            get: { SpaceSortPreference(rawValue: sortRaw) ?? .default },
            set: { sortRaw = $0.rawValue }
        )
    }

    private var displayedGroups: [SpaceGroup] {
        let ordered: [SpaceGroup]
        switch sort {
        case .workspaceOrder:
            ordered = model.visibleSpaceGroups
        case .priority:
            ordered = model.visibleSpaceGroups.sorted(by: SpaceGroup.attentionOrder)
        }
        guard appModel.isCoreMode else { return ordered }
        return ordered.filter { $0.id != CoreHierarchy.otherWorkspaceID }
            + ordered.filter { $0.id == CoreHierarchy.otherWorkspaceID }
    }

    private var cardOrder: [ReorderingCard] {
        displayedGroups.map { group in
            let latestChange = group.members.flatMap { $0.agents.compactMap(\.stateChangeSeq) }.max()
            return ReorderingCard(
                id: group.id,
                priorityKey: "\(group.status.rawValue)|\(latestChange.map { String($0) } ?? "")"
            )
        }
    }

    var body: some View {
        @Bindable var model = model

        return SelectionSplitView(
            layout: $layout,
            memory: paneMemory,
            pickerKind: .spaces,
            emptyTitle: "Select a space"
        ) {
            Group {
                if model.spaces.isEmpty && model.unconfirmedSpaces.isEmpty
                    && model.pendingSpaceCreationTitle == nil {
                    if appModel.isOffline {
                        OfflineHerdView()
                    } else if model.isLoading {
                        LazyCatLoadingView(message: appModel.isCoreMode ? "Loading terminals…" : "Loading spaces…")
                    } else {
                        emptyState
                    }
                } else {
                    ScrollViewReader { proxy in
                        List {
                            if let title = model.pendingSpaceCreationTitle {
                                PendingSpaceRow(title: title)
                                    .quietListRow()
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                            let groups = displayedGroups
                            ForEach(groups) { group in
                                spaceLink(group.root) {
                                    SpaceRow(
                                        group: group,
                                        isHighlighted: model.highlightedWorktreeID == group.root.id,
                                        isSelected: isSelected(group.root),
                                        lastUpdated: model.lastActivity(in: group.root)
                                    )
                                }
                                .accessibilityIdentifier("space-row-\(group.root.workspace.number)")
                                .id(group.id)
                                paneTreeRows(for: group.root, indent: QuietListMetrics.titleInset)
                                ForEach(group.worktrees) { space in
                                    spaceLink(space, isWorktree: true) {
                                        WorktreeRow(
                                            space: space,
                                            isHighlighted: model.highlightedWorktreeID == space.id,
                                            isSelected: isSelected(space),
                                            lastUpdated: model.lastActivity(in: space)
                                        )
                                    }
                                    paneTreeRows(for: space, indent: QuietListMetrics.titleInset * 2)
                                }
                                if let pending = model.pendingWorktreeAction,
                                   pending.sourceSpaceID == group.root.id {
                                    PendingWorktreeRow(action: pending)
                                        .quietListRow()
                                }
                            }
                        }
                        .listStyle(.plain)
                        .task(id: PaneTreeTrigger(targets: treeTargets, retryTick: paneTrees.retryTick)) {
                            await paneTrees.sync(treeTargets, connection: appModel.connection)
                        }
                        .scrollContentBackground(.hidden)
                        .environment(\.defaultMinListRowHeight, 0)
                        .contentMargins(.top, 4, for: .scrollContent)
                        .contentMargins(.bottom, 44, for: .scrollContent)
                        .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.12), value: cardOrder.map(\.id))
                        .onChange(of: model.lastPresentedSpaceID) { _, spaceID in
                            guard let spaceID,
                                  let group = displayedGroups.first(where: {
                                      $0.members.contains { $0.id == spaceID }
                                  }) else { return }
                            withAnimation(.snappy(duration: 0.28)) {
                                proxy.scrollTo(group.id, anchor: .center)
                            }
                        }
                        .onChange(of: model.pendingWorktreeAction) { _, pending in
                            guard pending != nil else { return }
                            withAnimation(.snappy(duration: 0.28)) {
                                proxy.scrollTo(PendingWorktreeAction.viewID, anchor: .center)
                            }
                        }
                    }
                }
            }
            .background(Theme.listBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            if let activeMachine { await activeMachine.disconnect() } else { await appModel.disconnect() }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.jost(16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Back to Connections")
                    .accessibilityIdentifier("spaces-back-button")
                }
                ToolbarItem(placement: .principal) {
                    HerdrcatBrandMark(showsHost: true, title: "Spaces")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !appModel.isCoreMode {
                            Button {
                                isShowingCreateSpace = true
                            } label: {
                                Label("New Space", systemImage: "plus")
                            }
                            .disabled(model.isCreatingSpace)
                            .accessibilityIdentifier("space-create-button")

                            Divider()
                        }

                        Picker("Sort", selection: sortSelection) {
                            ForEach(SpaceSortPreference.allCases) { preference in
                                Label(preference.title, systemImage: preference.systemImage)
                                    .tag(preference)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.jost(16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Space List Options")
                    .accessibilityIdentifier("space-list-options-menu")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: model.spaces) { _, _ in
                rememberSelected()
                autoSelectFirstIfNeeded()
            }
            .onChange(of: layout) { _, _ in rememberSelected() }
            .onAppear { autoSelectFirstIfNeeded() }
            .sheet(item: $actionsTarget, onDismiss: {
                guard let pending = pendingSpaceAction else { return }
                pendingSpaceAction = nil
                guard !appModel.isCoreMode else { return }
                perform(pending.action, on: pending.space)
            }) { space in
                SpaceActionsDrawer(
                    space: space,
                    isWorktreeActionDisabled: model.isPerformingWorktreeAction,
                    openActions: horizontalSizeClass == .regular
                        ? PaneOpenAction.actions(for: PaneRef(spaceID: space.id, paneID: nil), layout: $layout, memory: paneMemory)
                        : [],
                    onSelect: { action in
                        pendingSpaceAction = (action, space)
                        actionsTarget = nil
                    },
                    onCancel: {
                        pendingSpaceAction = nil
                        actionsTarget = nil
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
            }
            .sheet(isPresented: $isShowingCreateSpace, onDismiss: {
                guard let request = pendingCreateSpace else { return }
                pendingCreateSpace = nil
                guard !appModel.isCoreMode else { return }
                Task { await model.createSpace(basedOn: request.base, appModel.connection) }
            }) {
                CreateSpaceDrawer(
                    spaces: model.spaces,
                    onCreate: { base in
                        pendingCreateSpace = CreateSpaceRequest(base: base)
                        isShowingCreateSpace = false
                    },
                    onCancel: {
                        pendingCreateSpace = nil
                        isShowingCreateSpace = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
            }
            .sheet(item: $openWorktreeTarget, onDismiss: {
                guard let request = pendingOpenWorktree else { return }
                pendingOpenWorktree = nil
                guard !appModel.isCoreMode else { return }
                Task {
                    await model.openWorktree(
                        in: request.space,
                        path: request.path,
                        branch: request.branch,
                        appModel.connection
                    )
                }
            }) { space in
                OpenWorktreeDrawer(
                    space: space,
                    connection: appModel.connection,
                    onOpen: { path, branch in
                        pendingOpenWorktree = OpenWorktreeRequest(space: space, path: path, branch: branch)
                        openWorktreeTarget = nil
                    },
                    onCancel: {
                        pendingOpenWorktree = nil
                        openWorktreeTarget = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
            }
            .sheet(item: $createWorktreeTarget, onDismiss: {
                guard let request = pendingCreateWorktree else { return }
                pendingCreateWorktree = nil
                guard !appModel.isCoreMode else { return }
                Task {
                    await model.createWorktree(
                        in: request.space,
                        name: request.name,
                        label: request.label,
                        appModel.connection
                    )
                }
            }) { space in
                CreateWorktreeDrawer(
                    space: space,
                    onCreate: { name, label in
                        pendingCreateWorktree = CreateWorktreeRequest(
                            space: space,
                            name: name,
                            label: label
                        )
                        createWorktreeTarget = nil
                    },
                    onCancel: {
                        pendingCreateWorktree = nil
                        createWorktreeTarget = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
            }
            .alert("Rename Space", isPresented: $isShowingRenameAlert) {
                TextField("Space Name", text: $renameText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("space-rename-text-field")
                Button("Rename") {
                    let target = renameTarget
                    let name = renameText
                    renameTarget = nil
                    guard let target, !appModel.isCoreMode else { return }
                    Task {
                        await model.renameSpace(target, to: name, appModel.connection)
                    }
                }
                .accessibilityIdentifier("space-rename-confirm-button")
                Button("Cancel", role: .cancel) {
                    renameTarget = nil
                }
            } message: {
                Text("Enter a new name for this space.")
            }
            .confirmationDialog(
                "Close Space",
                isPresented: $isShowingCloseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Close Space", role: .destructive) {
                    let target = closeTarget
                    closeTarget = nil
                    guard let target, !appModel.isCoreMode else { return }
                    Task {
                        await model.closeSpace(target, appModel.connection)
                    }
                }
                .accessibilityIdentifier("space-close-confirm-button")
                Button("Cancel", role: .cancel) {
                    closeTarget = nil
                }
            } message: {
                if let closeTarget {
                    Text("Are you sure you want to close “\(closeTarget.label)”? This will close its tabs and panes.")
                } else {
                    Text("Are you sure you want to close this space? This will close its tabs and panes.")
                }
            }
            .overlay(alignment: .bottom) {
                if let error = model.errorMessage,
                   case .connected = appModel.phase,
                   !HerdrConnection.isDisconnectionOrTransitionMessage(error) {
                    VStack {
                        Spacer()
                        ErrorBanner(message: error, retry: {
                            Task { await model.refresh(appModel.connection) }
                        })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.errorMessage == nil)
            .refreshable {
                let currentModel = model
                let connection = appModel.connection
                async let spaces: Void = currentModel.refresh(connection)
                async let usage: Void = currentModel.refreshUsage(connection, force: true)
                _ = await (spaces, usage)
            }
            .connectionStatusBanner(appModel: appModel)
        } detail: { ref in
            if let space = model.spaces.first(where: { $0.id == ref.spaceID }) ?? lastSeen[ref.spaceID] {
                WorkspacePaneView(space: space, initialPaneID: ref.paneID)
                    .environment(appModel)
                    .environment(model)
            } else {
                ContentUnavailableView("Space unavailable", systemImage: "square.grid.3x3",
                                       description: Text("This space may have closed."))
            }
        }
    }

    private func rememberSelected() {
        for ref in [layout.left, layout.right].compactMap({ $0 }) {
            if let live = model.spaces.first(where: { $0.id == ref.spaceID }) {
                lastSeen[ref.spaceID] = live
            }
        }
    }

    private func autoSelectFirstIfNeeded() {
        if layout.left == nil, horizontalSizeClass == .regular,
           ProcessInfo.processInfo.arguments.contains("-hc.select-first"),
           let first = displayedGroups.first?.root {
            layout.openInFocused(PaneRef(spaceID: first.id, paneID: nil))
        }
    }

    /// Only the split view's detail column marks a row; a pushed pane covers the list.
    // MARK: Pane tree

    private struct PaneTreeTrigger: Hashable {
        let targets: [SpacePaneTreeTarget]
        let retryTick: Int
    }

    private var treeOverrides: [String: Bool] {
        get { SpacePaneTree.decode(treeOverridesRaw) }
        nonmutating set { treeOverridesRaw = SpacePaneTree.encode(newValue) }
    }

    private func isOpen(_ space: Space) -> Bool {
        layout.left?.spaceID == space.id || layout.right?.spaceID == space.id
    }

    private func isTreeExpanded(_ space: Space) -> Bool {
        horizontalSizeClass == .regular
            && SpacePaneTree.isExpanded(space.id, overrides: treeOverrides, isOpen: isOpen(space))
    }

    /// The expanded spaces, as the trees to fetch.
    private var treeTargets: [SpacePaneTreeTarget] {
        displayedGroups.flatMap(\.members).filter(isTreeExpanded).map { space in
            SpacePaneTreeTarget(
                spaceID: space.id,
                workspaceID: space.workspace.workspaceId,
                key: .init(tabCount: space.workspace.tabCount, paneCount: space.workspace.paneCount)
            )
        }
    }

    @ViewBuilder
    private func paneTreeRows(for space: Space, indent: CGFloat) -> some View {
        if isTreeExpanded(space) {
            SpacePaneTreeRows(
                space: space,
                load: paneTrees.loads[space.id],
                indent: indent,
                layout: $layout,
                retry: { paneTrees.retry(space.id) }
            )
        }
    }

    private func treePill(for space: Space, trailingInset: CGFloat) -> some View {
        SpacePaneTreePill(
            paneCount: space.workspace.paneCount,
            isExpanded: isTreeExpanded(space)
        ) {
            var overrides = treeOverrides
            SpacePaneTree.toggle(space.id, overrides: &overrides, isOpen: isOpen(space))
            withAnimation(reduceMotion ? nil : .snappy) { treeOverrides = overrides }
        }
        .padding(.trailing, trailingInset)
    }

    private func isSelected(_ space: Space) -> Bool {
        horizontalSizeClass == .regular
            && (layout.left?.spaceID == space.id || layout.right?.spaceID == space.id)
    }

    // MARK: Pieces

    /// Opens a space on tap, its More drawer on long press, and offers
    /// trailing swipe actions: More and Close.
    @ViewBuilder
    private func spaceLink<Row: View>(
        _ space: Space,
        isWorktree: Bool = false,
        @ViewBuilder row: () -> Row
    ) -> some View {
        // Keep native cell selection and swipe handling. The long press must
        // be simultaneous so it doesn't consume the NavigationLink's tap.
        let link = Group {
            if horizontalSizeClass == .regular {
                Button { layout.openInFocused(PaneRef(spaceID: space.id, paneID: nil), shown: OpenPaneMemory.resolver(paneMemory)) } label: {
                    row().paneSlotBadge(layout.badgeSlots(spaceID: space.id), focused: layout.focused)
                }
                .buttonStyle(.plain)
                .paneDraggable(PaneRef(spaceID: space.id, paneID: nil), title: space.label, enabled: true)
            } else {
                NavigationLink(value: PaneRef(spaceID: space.id, paneID: nil)) { row() }
                    .hidesNavigationIndicator()
            }
        }
        .overlay(alignment: isWorktree ? .trailing : .bottomTrailing) {
            // Beside the row's own button, so a tap here only folds the tree.
            if horizontalSizeClass == .regular, space.workspace.paneCount > 0 {
                // A worktree row's time sits at its trailing edge; the pill goes left of it.
                treePill(for: space, trailingInset: isWorktree ? 64 : 0)
            }
        }
        .quietListRow()
        if appModel.isCoreMode {
            // No actions drawer in Core mode, so the row menu is the way to pick a side.
            if horizontalSizeClass == .regular {
                link.contextMenu {
                    ForEach(PaneOpenAction.actions(for: PaneRef(spaceID: space.id, paneID: nil), layout: $layout, memory: paneMemory)) { action in
                        Button(action: action.perform) { Label(action.title, systemImage: action.systemImage) }
                    }
                }
            } else {
                link
            }
        } else {
            // WhatsApp-style: drag right to left; Close sits at the screen edge.
            link.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                swipeCloseButton(space)
                swipeMoreButton(space)
            }
            .simultaneousGesture(
                LongPressGesture().onEnded { _ in
                    actionsTarget = space
                }
            )
            .accessibilityAction(named: "More") {
                actionsTarget = space
            }
        }
    }

    private func swipeMoreButton(_ space: Space) -> some View {
        Button {
            actionsTarget = space
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .tint(Theme.subtleFill)
        .buttonStyle(.automatic)
        .accessibilityIdentifier("space-swipe-more-\(space.id)")
    }

    private func swipeCloseButton(_ space: Space) -> some View {
        Button {
            perform(.close, on: space)
        } label: {
            Label("Close", systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
        .tint(Theme.destructive)
        .buttonStyle(.automatic)
        .accessibilityIdentifier("space-swipe-close-\(space.id)")
    }

    private func perform(_ action: SpaceAction, on space: Space) {
        guard !appModel.isCoreMode else { return }
        switch action {
        case .openWorktree:
            openWorktreeTarget = model.defaultSpace(for: space)
        case .createWorktree:
            createWorktreeTarget = model.defaultSpace(for: space)
        case .rename:
            renameTarget = space
            renameText = space.label
            isShowingRenameAlert = true
        case .close:
            closeTarget = space
            isShowingCloseConfirmation = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.3x3")
                .font(.jost(42, weight: .light))
                .foregroundStyle(.tertiary)
            Text(appModel.isCoreMode ? "No terminals" : "No Spaces Yet")
                .font(.jost(.title3, weight: .semibold))
            Text(appModel.isCoreMode
                 ? "Start a program with Herdr Core on the connected machine. Its terminal will appear here."
                 : "Start herdr on your remote machine and create a workspace,\nor tap ⋯ to create one from here.")
                .font(.jost(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}
