import Observation
import SwiftUI

// MARK: - Spaces screen

struct SpacesScreen: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ActiveMachine.self) private var activeMachine: ActiveMachine?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let model: SpacesModel

    /// Id of the open space. Shared by the split view and the compact stack,
    /// so folding or unfolding keeps the same space open.
    @State private var selectedID: String?
    /// The selected space as last seen in the list, so a refresh that drops
    /// it doesn't blank the pane mid-read.
    @State private var lastSeen: Space?

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
            selection: $selectedID,
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
                                ForEach(group.worktrees) { space in
                                    spaceLink(space) {
                                        WorktreeRow(
                                            space: space,
                                            isHighlighted: model.highlightedWorktreeID == space.id,
                                            isSelected: isSelected(space),
                                            lastUpdated: model.lastActivity(in: space)
                                        )
                                    }
                                }
                                if let pending = model.pendingWorktreeAction,
                                   pending.sourceSpaceID == group.root.id {
                                    PendingWorktreeRow(action: pending)
                                        .quietListRow()
                                }
                            }
                        }
                        .listStyle(.plain)
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
            .onChange(of: selectedID) { _, _ in rememberSelected() }
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
        } detail: { id in
            if let space = model.spaces.first(where: { $0.id == id }) ?? lastSeen.flatMap({ $0.id == id ? $0 : nil }) {
                WorkspacePaneView(space: space)
                    .environment(appModel)
                    .environment(model)
            } else {
                ContentUnavailableView("Space unavailable", systemImage: "square.grid.3x3",
                                       description: Text("This space may have closed."))
            }
        }
    }

    private func rememberSelected() {
        guard let selectedID, let live = model.spaces.first(where: { $0.id == selectedID }) else { return }
        lastSeen = live
    }

    private func autoSelectFirstIfNeeded() {
        if selectedID == nil, horizontalSizeClass == .regular,
           ProcessInfo.processInfo.arguments.contains("-hc.select-first") {
            selectedID = displayedGroups.first?.root.id
        }
    }

    /// Only the split view's detail column marks a row; a pushed pane covers the list.
    private func isSelected(_ space: Space) -> Bool {
        horizontalSizeClass == .regular && selectedID == space.id
    }

    // MARK: Pieces

    /// Opens a space on tap, its More drawer on long press, and offers
    /// trailing swipe actions: More and Close.
    @ViewBuilder
    private func spaceLink<Row: View>(_ space: Space, @ViewBuilder row: () -> Row) -> some View {
        // Keep native cell selection and swipe handling. The long press must
        // be simultaneous so it doesn't consume the NavigationLink's tap.
        let link = Group {
            if horizontalSizeClass == .regular {
                Button { selectedID = space.id } label: { row() }
                    .buttonStyle(.plain)
            } else {
                NavigationLink(value: space.id) { row() }
                    .hidesNavigationIndicator()
            }
        }
        .quietListRow()
        if appModel.isCoreMode {
            link
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
