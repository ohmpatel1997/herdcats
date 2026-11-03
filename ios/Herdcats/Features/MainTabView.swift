import Observation
import SwiftUI

// MARK: - Main tab view

/// Keeps the chosen tab while replacing navigation and data on machine changes.
struct MainTabView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ActiveMachine.self) private var active: ActiveMachine?
    @State private var selectedTab = ConnectedTabsView.MainTab.requestedInitialTab()

    /// A switch installs a new `AppModel`; reconnects (even failed ones that
    /// clear `connectionIdentity`) keep the same model, so navigation survives.
    static func subtreeID(for model: AppModel) -> ObjectIdentifier { ObjectIdentifier(model) }

    var body: some View {
        ConnectedTabsView(selectedTab: $selectedTab)
            .environment(appModel)
            .id(Self.subtreeID(for: appModel))
            // Switch progress and errors render per screen via `connectionStatusBanner(appModel:)`.
            .background {
                if let active, !active.pendingHostKeyOwnedByForm, let pending = active.pending {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .hostKeyApprovalSheet(onCancelled: {
                            guard active.pending === pending else { return }
                            await active.cancelSwitch()
                        }, onApproved: {
                            guard active.pending === pending else { return }
                            _ = await active.finishPendingSwitch()
                        })
                        .environment(pending)
                        .id(ObjectIdentifier(pending))
                }
            }
    }
}

/// Owns the selected machine's shared data and lifecycle-aware refresh loop.
struct ConnectedTabsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = SpacesModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var selectedTab: MainTab
    /// The open panes, per window. Spaces and Agents share one layout, so
    /// switching tabs keeps the same panes.
    @SceneStorage("paneLayout") private var paneLayoutRaw = ""
    /// The machine `paneLayout` belongs to. Pane IDs are host-local, so a
    /// layout from another machine must not open anything on this one.
    @SceneStorage("paneLayoutMachine") private var paneLayoutMachine = ""
    /// Each open item's sibling pane, shared by both tabs so a sibling picked
    /// in one shows in the other.
    @State private var paneMemory = OpenPaneMemory()

    private var paneLayout: Binding<PaneLayout> {
        Binding(
            get: { PaneLayout(storageValue: paneLayoutRaw) },
            set: { paneLayoutRaw = $0.storageValue }
        )
    }

    enum MainTab: String, Hashable {
        case spaces
        case agents
        case quota
        case settings

        /// Optional launch-argument driven initial tab (UI tests, screenshots):
        /// `-hc.tab agents` / `-hc.tab spaces` / `-hc.tab quota` / `-hc.tab settings`.
        static func requestedInitialTab() -> MainTab {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-hc.tab"),
                  index + 1 < arguments.count,
                  let tab = MainTab(rawValue: arguments[index + 1]) else {
                if AutoConnect.configIfRequested() != nil || LaunchPreference.autoConnectConfig() != nil {
                    return .agents
                }
                return .spaces
            }
            return tab
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SpacesScreen(model: model, layout: paneLayout, paneMemory: paneMemory)
                .hidesSystemTabBarForSidebarSwitcher(horizontalSizeClass)
                .tabItem {
                    Label("Spaces", systemImage: "square.grid.3x3")
                }
                .tag(MainTab.spaces)

            AgentsScreen(model: model, layout: paneLayout, paneMemory: paneMemory)
                .hidesSystemTabBarForSidebarSwitcher(horizontalSizeClass)
                .tabItem {
                    Label("Agents", systemImage: "cpu")
                }
                .badge(model.blockedAgentCount)
                .tag(MainTab.agents)

            QuotaScreen(model: model)
                .hidesSystemTabBarForSidebarSwitcher(horizontalSizeClass)
                .tabItem {
                    Label("Quota", systemImage: "gauge.with.dots.needle.67percent")
                }
                .tag(MainTab.quota)

            SettingsScreen(model: model)
                .hidesSystemTabBarForSidebarSwitcher(horizontalSizeClass)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(MainTab.settings)
        }
        .environment(model)
        .environment(
            \.sidebarTabs,
            SidebarTabLayout.usesSidebarSwitcher(horizontalSizeClass)
                ? SidebarTabs(selection: $selectedTab, blockedCount: model.blockedAgentCount)
                : nil
        )
        .task {
            #if DEBUG && targetEnvironment(simulator)
            if ScreenshotFixtures.enabled && ProcessInfo.processInfo.arguments.contains("-hc.split-capture") {
                paneLayout.wrappedValue = PaneLayout()
                paneMemory.forget()
            }
            #endif
            model.stopAutoRefresh()
            model.bindConnectionScope(appModel.connectionIdentity)
            guard !Task.isCancelled else { return }
            let active = scenePhase == .active
            model.isSceneActive = active
            appModel.isSceneActive = active
            await model.refresh(appModel.connection)
            guard !Task.isCancelled else { return }
            model.startAutoRefresh(appModel.connection)
        }
        .onChange(of: appModel.connectionIdentity, initial: true) { _, identity in
            // A failed reconnect clears the identity; keep the layout for the same machine's return.
            guard let key = identity?.storageKey else { return }
            if !paneLayoutMachine.isEmpty, paneLayoutMachine != key {
                paneLayout.wrappedValue = PaneLayout()
                paneMemory.forget()
            }
            paneLayoutMachine = key
        }
        .onChange(of: model.spaces) { _, spaces in
            // Drop panes whose space is gone. An empty list is left alone: it
            // is more likely a refresh gap than every space closing at once.
            guard model.hasLoadedAgentList, !spaces.isEmpty else { return }
            let ids = Set(spaces.map(\.id))
            let current = paneLayout.wrappedValue
            let pruned = current.pruned { ids.contains($0.spaceID) }
            if pruned != current { paneLayout.wrappedValue = pruned }
        }
        .onChange(of: appModel.phase) { oldPhase, newPhase in
            if case .connected = newPhase, case .offline = oldPhase {
                Task {
                    await model.refresh(appModel.connection)
                    await model.refreshUsage(appModel.connection, force: true)
                }
            }
        }
        .onChange(of: appModel.runtimeRevision) { _, _ in
            guard appModel.isCoreMode, appModel.isSceneActive, !appModel.isOffline else { return }
            Task { await model.refresh(appModel.connection) }
        }
        .onChange(of: scenePhase) { _, phase in
            let active = phase == .active
            model.isSceneActive = active
            appModel.isSceneActive = active
            if active {
                if appModel.isOffline {
                    Task { await appModel.reconnect(automatically: true) }
                } else if model.autoRefreshEnabled {
                    Task {
                        await model.refresh(appModel.connection)
                        await model.refreshUsage(appModel.connection, force: true)
                    }
                }
            }
        }
        .onDisappear {
            model.stopAutoRefresh()
        }
    }
}

// MARK: - Agents screen

/// Every agent across every space. Ordered by herdr's attention priority
/// (flat queue) or grouped by space — both selectable from the ⋯ menu.
/// Tapping a row opens that agent's pane directly.
struct AgentsScreen: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let model: SpacesModel
    /// The open panes, shared with the Spaces tab and by the split view and
    /// the compact stack, so folding or unfolding keeps the same panes open.
    @Binding var layout: PaneLayout
    /// Each open item's sibling pane, owned above both tabs so a rebuilt detail restores it.
    var paneMemory = OpenPaneMemory()
    @State private var raisedCardID: String?
    /// Spaces of the open panes as last seen in the list, so a refresh that
    /// drops one doesn't blank its pane mid-read.
    @State private var lastSeen: [String: Space] = [:]

    @AppStorage(AgentsSortPreference.storageKey)
    private var sortRaw = AgentsSortPreference.default.rawValue

    private var sort: AgentsSortPreference {
        AgentsSortPreference(rawValue: sortRaw) ?? .default
    }

    private var sortSelection: Binding<AgentsSortPreference> {
        Binding(
            get: { AgentsSortPreference(rawValue: sortRaw) ?? .default },
            set: { sortRaw = $0.rawValue }
        )
    }

    /// The flat attention queue — herdr's `priority` agent panel sort:
    /// blocked, done, working, idle, unknown, latest state change first.
    private var items: [AgentListItem] {
        model.spaces
            .flatMap { space in space.agents.map { AgentListItem(space: space, agent: $0) } }
            .sorted(by: AgentListItem.attentionOrder)
    }

    /// Spaces with their agents — herdr's `spaces` agent panel sort.
    private var sections: [(space: Space, items: [AgentListItem])] {
        AgentListItem.grouped(in: model.spaces)
    }

    private var cardOrder: [ReorderingCard] {
        let displayedItems = sort == .priority ? items : sections.flatMap { $0.items }
        return displayedItems.map { item in
            ReorderingCard(
                id: item.id,
                priorityKey: "\(item.agent.agentStatus)|\(item.agent.stateChangeSeq.map { String($0) } ?? "")"
            )
        }
    }

    var body: some View {
        let currentItems = items
        SelectionSplitView(
            layout: $layout,
            memory: paneMemory,
            pickerKind: .agents,
            emptyTitle: "Select an agent"
        ) {
            Group {
                if appModel.isOffline && currentItems.isEmpty {
                    OfflineHerdView()
                } else if currentItems.isEmpty && model.showsAgentLoading {
                    loadingSkeleton
                } else if currentItems.isEmpty && !model.hasLoadedAgentList && model.agentListError != nil {
                    ContentUnavailableView("Unable to Load Agents", systemImage: "exclamationmark.triangle",
                                           description: Text("Retry to load agents from your machines."))
                } else if currentItems.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            switch sort {
                            case .priority:
                                ForEach(currentItems) { item in
                                    agentRow(item)
                                }
                            case .spaces:
                                let currentSections = sections
                                ForEach(currentSections, id: \.space.id) { section in
                                    spaceHeader(section.space)
                                    ForEach(section.items) { item in
                                        agentRow(item)
                                    }
                                }
                            }
                        }
                        .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.12), value: cardOrder.map(\.id))
                        .onChange(of: cardOrder) { old, new in
                            raisedCardID = ReorderingCard.movingID(from: old, to: new)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 28)
                    }
                }
            }
            .background(Theme.listBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HerdrcatBrandMark(showsHost: true, title: "Agents")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: sortSelection) {
                            ForEach(AgentsSortPreference.allCases) { preference in
                                Label(preference.title, systemImage: preference.systemImage)
                                    .tag(preference)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.jost(16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Agent List Options")
                    .accessibilityIdentifier("agent-list-options-menu")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: currentItems) { _, _ in
                rememberSelected()
                autoSelectFirstIfNeeded()
            }
            .onChange(of: layout) { _, _ in rememberSelected() }
            .onAppear { autoSelectFirstIfNeeded() }
            .overlay(alignment: .bottom) {
                if let error = model.agentListError,
                   case .connected = appModel.phase {
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
                await model.refresh(appModel.connection)
            }
            .connectionStatusBanner(appModel: appModel)
        } detail: { ref in
            if let space = model.spaces.first(where: { $0.id == ref.spaceID }) ?? lastSeen[ref.spaceID] {
                WorkspacePaneView(space: space, initialPaneID: ref.paneID)
                    .environment(appModel)
                    .environment(model)
            } else {
                ContentUnavailableView("Agent unavailable", systemImage: "cpu",
                                       description: Text("This agent may have closed."))
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
           let first = items.first {
            layout.openInFocused(ref(for: first))
        }
    }

    private func ref(for item: AgentListItem) -> PaneRef {
        PaneRef(spaceID: item.space.id, paneID: item.agent.paneId)
    }

    private func isOpen(_ item: AgentListItem) -> Bool {
        let shown = OpenPaneMemory.resolver(paneMemory)
        return [layout.left, layout.right].contains { $0.flatMap(shown) == item.id }
    }

    // MARK: Pieces

    private var loadingSkeleton: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<6) { index in
                    // Mirrors AgentListRow: bars take their height from the
                    // real fonts so a skeleton row is as tall as a loaded one.
                    HStack(alignment: .listTitleCenter, spacing: QuietListMetrics.columnSpacing) {
                        Circle()
                            .fill(Theme.subtleFill)
                            .frame(width: 9, height: 9)
                            .frame(width: QuietListMetrics.statusColumn, height: QuietListMetrics.statusColumn)
                        VStack(alignment: .leading, spacing: QuietListMetrics.lineSpacing) {
                            HStack(spacing: 6) {
                                skeletonBar(width: index.isMultiple(of: 2) ? 170 : 140, font: .appHeadlineSm)
                                Spacer(minLength: 8)
                                skeletonBar(width: 36, font: .jost(.footnote))
                            }
                            .alignmentGuide(.listTitleCenter) { $0[VerticalAlignment.center] }
                            skeletonBar(width: 120, font: .caption.monospaced())
                        }
                    }
                    .padding(.vertical, QuietListMetrics.rowVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { QuietListDivider() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading agents")
        .accessibilityIdentifier("agent-list-loading")
    }

    /// A placeholder bar exactly one line of `font` tall, inset like the glyphs.
    private func skeletonBar(width: CGFloat, font: Font) -> some View {
        Text(" ")
            .font(font)
            .hidden()
            .frame(width: width)
            .background {
                RoundedRectangle.continuous(DesignSystem.CornerRadius.sm)
                    .fill(Theme.subtleFill)
                    .padding(.vertical, 3)
            }
    }

    @ViewBuilder
    private func agentRow(_ item: AgentListItem) -> some View {
        let isRegular = horizontalSizeClass == .regular
        let row = AgentListRow(
            item: item,
            isSelected: isRegular && isOpen(item),
            lastUpdated: model.lastUpdatedByPaneID[item.agent.paneId]
        )
        Group {
            if isRegular {
                Button { layout.openInFocused(ref(for: item), shown: OpenPaneMemory.resolver(paneMemory)) } label: {
                    row.paneSlotBadge(layout.badgeSlot(paneID: item.id, shown: OpenPaneMemory.resolver(paneMemory)), focused: layout.focused)
                }
                .contextMenu {
                    ForEach(PaneOpenAction.actions(for: ref(for: item), layout: $layout, memory: paneMemory)) { action in
                        Button(action: action.perform) { Label(action.title, systemImage: action.systemImage) }
                    }
                }
                .paneDraggable(ref(for: item), title: item.title, enabled: true)
            } else {
                NavigationLink(value: ref(for: item)) { row }
            }
        }
        .buttonStyle(.plain)
        .zIndex(raisedCardID == item.id ? 1 : 0)
        .transition(.opacity)
    }

    private func spaceHeader(_ space: Space) -> some View {
        HStack(spacing: 8) {
            Text("#\(space.workspace.number) · \(space.label)")
                .font(.pixel(10, bold: true))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            StatusPill(status: space.status)
            Spacer(minLength: 0)
        }
        .padding(.top, 18)
        .padding(.bottom, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Space \(space.label), \(space.status.label)")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "cpu")
                .font(.jost(42, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No agents running")
                .font(.jost(.title3, weight: .semibold))
            Text(appModel.isCoreMode
                 ? "Run a status-reporting agent in Herdr Core. You can browse every terminal in Spaces."
                 : "Launch an agent inside a herdr space —\nit will show up here on the next refresh.")
                .font(.jost(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

// MARK: - Agent list item

struct AgentListItem: Identifiable, Hashable {
    let space: Space
    let agent: AgentEntry

    var id: String { agent.paneId }

    var status: AgentStatus {
        AgentStatus(rawValue: agent.agentStatus) ?? .unknown
    }

    var title: String {
        agent.displayTitle
    }

    /// Herdr's attention queue: `AgentStatus.attentionPriority` descending,
    /// then the most recent state change first — the same order herdr's
    /// priority-sorted agent panel uses.
    static func attentionOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.status.attentionPriority != rhs.status.attentionPriority {
            return lhs.status.attentionPriority > rhs.status.attentionPriority
        }
        // Older servers may omit the sequence; keep those agents after known changes.
        switch (lhs.agent.stateChangeSeq, rhs.agent.stateChangeSeq) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        return (lhs.space.workspace.number, lhs.title, lhs.id)
            < (rhs.space.workspace.number, rhs.title, rhs.id)
    }

    /// One section per space that actually hosts agents — spaces in workspace
    /// order, agents in the space's join order — mirroring herdr's `spaces`
    /// agent panel sort. Agent-less spaces are hidden instead of rendering an
    /// empty header.
    static func grouped(in spaces: [Space]) -> [(space: Space, items: [AgentListItem])] {
        spaces.compactMap { space in
            guard !space.agents.isEmpty else { return nil }
            return (space, space.agents.map { AgentListItem(space: space, agent: $0) })
        }
    }
}

// MARK: - Agent list row

struct AgentListRow: View {
    @Environment(\.paneRowBadges) private var paneBadges
    let item: AgentListItem
    /// The row open in the split view's detail column.
    var isSelected = false
    var lastUpdated: Date?

    private var agent: AgentEntry { item.agent }

    var body: some View {
        HStack(alignment: .listTitleCenter, spacing: QuietListMetrics.columnSpacing) {
            StatusDot(status: item.status)
                .accessibilityLabel(item.status.label)
            VStack(alignment: .leading, spacing: QuietListMetrics.lineSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(.appHeadlineSm)
                        .lineLimit(1)
                    if agent.focused {
                        Image(systemName: "scope")
                            .font(.jost(11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Focused")
                    }
                    Spacer(minLength: 8)
                    ForEach(paneBadges, id: \.slot) { PaneSlotTag(badge: $0) }
                    RowTimestamp(date: lastUpdated)
                }
                .alignmentGuide(.listTitleCenter) { $0[VerticalAlignment.center] }
                HStack(spacing: 6) {
                    AgentKindIcon(kind: agent.agent, size: 13)
                        .accessibilityElement()
                        .accessibilityLabel(AgentKindVisual.displayName(for: agent.agent))
                    if !agent.shortCwd.isEmpty {
                        Text(agent.shortCwd)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, QuietListMetrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background { RowHighlight(isActive: false, isSelected: isSelected) }
        .overlay(alignment: .bottom) { QuietListDivider() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shared toolbar

struct HerdrcatBrandMark: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ActiveMachine.self) private var active: ActiveMachine?
    @State private var connections: [RecentConnection] = []
    @State private var selectedConnection: RecentConnection?
    var showsHost = false
    var title: String? = nil

    private var host: String? {
        guard showsHost else { return nil }
        switch appModel.phase {
        case let .connected(host, _), let .offline(host, _): return host
        default: return nil
        }
    }

    private func identity(_ connection: RecentConnection) -> ConnectionIdentity {
        ConnectionIdentity(host: connection.host, port: connection.port, username: connection.username,
            backend: connection.backend)
    }

    private var activeConnection: RecentConnection? {
        connections.first { identity($0) == appModel.connectionIdentity }
    }

    private func select(_ connection: RecentConnection) {
        guard let active else { return }
        Task {
            if await active.switchMachine(to: connection) == .needsCredentials {
                selectedConnection = connection
            }
        }
    }

    /// Servers in list order; a server saved with both runtimes gets a row for each.
    private var rows: [RecentConnection] {
        RecentConnectionStore.servers(connections).flatMap { RecentConnectionStore.savedRuntimes(of: $0, in: connections) }
    }

    private var shortHost: String {
        // Same label as the checked menu row.
        activeConnection?.shortDisplayName(among: connections) ?? RecentConnection.abbreviatedHost(host ?? "")
    }

    private func isPending(_ connection: RecentConnection) -> Bool {
        guard let pending = active?.pending else { return false }
        let pendingIdentity = pending.connectionIdentity ?? pending.activeConfig.map { ConnectionIdentity($0) }
        return identity(connection) == pendingIdentity
    }

    private func reloadConnections() {
        connections = (try? RecentConnectionStore.load()) ?? connections
    }

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 8) {
                if title == nil {
                    Image("HerdrcatLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle.continuous(DesignSystem.CornerRadius.xs))
                }
                Text(title ?? "Herdcats")
                    .font(.jost(17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            if let host {
                Menu {
                    // The checkmark marks the current machine, so no host header.
                    ForEach(rows) { connection in
                        let label = connection.shortDisplayName(among: connections)
                        Button {
                            select(connection)
                        } label: {
                            HStack {
                                Text(label)
                                if isPending(connection) {
                                    ProgressView()
                                    Text("Connecting…")
                                }
                                if identity(connection) == appModel.connectionIdentity {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .accessibilityLabel(label + (isPending(connection) ? ", Connecting…" : ""))
                    }
                    .onAppear { reloadConnections() }
                    Divider()
                    Button("Add Machine…", systemImage: "plus") {
                        Task {
                            // The new form owns the next switch; an earlier one must not finish under it.
                            await active?.cancelSwitch()
                            selectedConnection = RecentConnection(host: "", port: 22, username: "",
                                authMode: "password", remember: true)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(shortHost).lineLimit(1).truncationMode(.middle)
                        Image(systemName: "chevron.down")
                    }
                    .font(.jost(.caption2))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                .accessibilityLabel("Machine: \(activeConnection?.displayName ?? host)")
                .accessibilityIdentifier("machine-picker")
            }
        }
        .onAppear { reloadConnections() }
        .onChange(of: appModel.connectionIdentity) { _, _ in reloadConnections() }
        .sheet(item: $selectedConnection, onDismiss: reloadConnections) { connection in
            if connection.host.isEmpty {
                ConnectionSettingsView(connection: connection, switcher: active)
            } else {
                SavedConnectionSignInView(initial: (try? ConnectionSignIn.load(connection)) ?? ConnectionSignIn(entry: connection),
                    replay: false, switcher: active)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
