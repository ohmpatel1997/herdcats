import AVFoundation
import PhotosUI
import Foundation
import Observation
import SwiftUI
import UIKit

// MARK: - Pane detail (live output + input)

/// Live view of one terminal pane: scrollable terminal output on top, a text
/// field underneath that types directly into the pane (Return sends text +
/// Enter, exactly as if typed at the keyboard).
struct PaneDetailView: View {
    let pane: PaneEntry

    @Environment(AppModel.self) private var appModel
    @Environment(SpacesModel.self) private var spacesModel: SpacesModel?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showsPaneSwitcher) private var showsPaneSwitcher
    @Environment(\.showsPaneBackButton) private var showsPaneBackButton
    @Environment(\.openPaneMemory) private var openPaneMemory
    @Environment(\.closeDetail) private var closeDetail
    @State private var siblings: [PaneEntry]
    @State private var tabs: [TabEntry] = []
    @State private var selectedPaneID: String
    @State private var timelineModes: [String: Bool] = [:]
    @State private var bridgeUpgrade = TimelineBridgeUpgrade()
    @State private var lastUpdatedByPaneID: [String: Date] = [:]
    /// Pane switcher shows chips instead of cards to give the output more room.
    @State private var isSwitcherCompact = false
    @ScaledMetric(relativeTo: .subheadline) private var paneCardHeight = 100
    @ScaledMetric(relativeTo: .caption) private var paneChipHeight = 30
    @State private var showLiveDiagnostics = false
    @AppStorage(PaneComposePreference.storageKey)
    private var showComposeByDefault = PaneComposePreference.default

    @State private var isShowingRenameAlert = false
    @State private var renameText = ""
    @State private var isShowingKillConfirmation = false
    /// Pane targeted by rename/kill from the toolbar or a card context menu.
    @State private var actionTargetPane: PaneEntry?
    @State private var isShowingAddPane = false
    @State private var pendingAddPane: AddPaneRequest?
    /// Placeholder shown in the switcher while a new pane or tab is being created.
    @State private var creatingPane: PendingPanePlaceholder?
    @State private var actionErrorMessage: String?
    @State private var isPerformingAction = false
    /// Workspace owning `pane`, refreshed on appear so workspace-level actions
    /// (rename / close / delete worktree checkout) target live data.
    @State private var workspace: Workspace?
    @State private var pendingWorkspaceAction: WorkspaceAction?

    /// `restoring` is the sibling that was open before the layout changed
    /// width; it is ignored when that pane is no longer in the workspace.
    init(pane: PaneEntry, siblings: [PaneEntry] = [], restoring restoredPaneID: String? = nil) {
        self.pane = pane
        let peers = siblings.filter {
            $0.workspaceId == pane.workspaceId
        }
        let all = peers.contains(where: { $0.id == pane.id }) ? peers : [pane] + peers
        _siblings = State(initialValue: all)
        _selectedPaneID = State(initialValue: all.contains { $0.id == restoredPaneID } ? restoredPaneID ?? pane.id : pane.id)
    }

    private var selectedPane: PaneEntry {
        siblings.first { $0.id == selectedPaneID } ?? pane
    }

    private var paneSwitcherHeight: CGFloat {
        guard showsPaneSwitcher else { return 0 }
        return isSwitcherCompact ? paneChipHeight + 12 : paneCardHeight + 20
    }

    /// Identity for `PaneSessionView`: the selected pane within the current
    /// connection scope. Changing either tears the session view down and
    /// rebuilds it with fresh state and per-pane/per-scope persistence keys,
    /// so Voice/Compose drafts, attachments, dictation, and Live sessions
    /// can never cross panes or connection identities. `storageKey` is
    /// percent-encoded and UserDefaults-safe; `#` cannot appear in it.
    private var sessionIdentity: String {
        "\(connectionScope.storageKey)#\(selectedPaneID)"
    }

    private var connectionScope: ConnectionIdentity {
        appModel.connectionIdentity
            ?? ConnectionIdentity(host: "unknown", port: 0, username: "unknown")
    }

    private var timelineMode: Binding<Bool> {
        let key = sessionIdentity
        return Binding(
            get: {
                guard !appModel.isCoreMode, TimelineAgentAvailability.supports(agent: selectedPane.agent) else { return false }
                return timelineModes[key] ?? !UserDefaults.standard.bool(forKey: TimelineSetupPreference.key(scope: connectionScope))
            },
            set: { timelineModes[key] = !appModel.isCoreMode && TimelineAgentAvailability.supports(agent: selectedPane.agent) && $0 }
        )
    }

    private var selectedPaneSession: some View {
        PaneSessionView(
            pane: selectedPane,
            connectionScope: connectionScope,
            showsTimeline: timelineMode,
            bridgeUpgrade: bridgeUpgrade,
            topOutputInset: paneSwitcherHeight,
            showLiveDiagnostics: $showLiveDiagnostics,
            onMarkedSeen: {
                Task {
                    await refreshPeersAndTabs()
                    if let spacesModel {
                        await spacesModel.refresh(appModel.connection)
                    }
                }
            },
            onOutputInteraction: {
                guard !isSwitcherCompact else { return }
                withAnimation(.snappy(duration: 0.28)) {
                    isSwitcherCompact = true
                }
            }
        )
        .id(sessionIdentity)
    }

    /// What the hidden switcher strip offers: pick a sibling pane, and add,
    /// rename or kill one.
    @ViewBuilder
    private var paneMenuSection: some View {
        if siblings.count > 1 {
            Picker(selection: $selectedPaneID) {
                ForEach(siblings) { sibling in
                    Text(sibling.displayTitle).tag(sibling.id)
                }
            } label: {
                Label("Switch Pane", systemImage: "rectangle.stack")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("pane-menu-switch")
        }
        if !appModel.isCoreMode {
            Button {
                isShowingAddPane = true
            } label: {
                Label("Add Pane", systemImage: "plus")
            }
            .accessibilityIdentifier("pane-menu-add")

            Button {
                beginRename(selectedPane)
            } label: {
                Label("Rename Pane", systemImage: "pencil")
            }
            .accessibilityIdentifier("pane-menu-rename")

            Button(role: .destructive) {
                beginKill(selectedPane)
            } label: {
                Label("Kill Pane", systemImage: "xmark.square")
            }
            .accessibilityIdentifier("pane-menu-kill")
        }
    }

    var body: some View {
        selectedPaneSession
        .overlay(alignment: .top) {
            if showsPaneSwitcher {
                PaneSwitcher(
                    panes: siblings,
                    tabs: tabs,
                    selection: $selectedPaneID,
                    isCompact: $isSwitcherCompact,
                    lastUpdatedByPaneID: lastUpdatedByPaneID,
                    pendingPane: creatingPane,
                    isAddDisabled: isPerformingAction,
                    allowsMutations: !appModel.isCoreMode,
                    onAdd: {
                        isShowingAddPane = true
                    },
                    onRename: { pane in
                        beginRename(pane)
                    },
                    onKill: { pane in
                        beginKill(pane)
                    }
                )
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(selectedPane.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Hide the system back control to disable interactive swipe-back.
        // Leaving a pane requires an explicit tap.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // The split view's detail column has no stack to pop.
            if showsPaneBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        leave()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                    .tint(Color.primary)
                    .accessibilityIdentifier("pane-back-button")
                }
            }
            ToolbarItem(placement: .principal) {
                StatusNavigationTitle(
                    title: selectedPane.displayTitle,
                    status: selectedPane.status,
                    subtitle: selectedPane.shortCwd.isEmpty ? nil : selectedPane.shortCwd,
                    agent: selectedPane.agent
                )
            }
            if !appModel.isCoreMode, TimelineAgentAvailability.supports(agent: selectedPane.agent) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        timelineMode.wrappedValue.toggle()
                    } label: {
                        Image(systemName: timelineMode.wrappedValue ? "terminal" : "bubble.left")
                            .font(.jost(16, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel(timelineMode.wrappedValue ? "Terminal" : "Timeline")
                    .accessibilityIdentifier(timelineMode.wrappedValue ? "timeline-open-terminal" : "terminal-open-timeline")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if timelineMode.wrappedValue, let version = bridgeUpgrade.bridgeVersion, HostHelperProbe.isOlderThanPinned(version) {
                        Button {
                            bridgeUpgrade.requestUpgrade()
                        } label: {
                            Label("Upgrade Herdcats Bridge", systemImage: "arrow.up.circle")
                        }
                        .accessibilityIdentifier("timeline-upgrade-menu-button")
                        Divider()
                    }
                    // The switcher strip is hidden while the list column shows,
                    // so its pane switching and actions move into this menu.
                    if !showsPaneSwitcher {
                        paneMenuSection
                        Divider()
                    }
                    if !appModel.isCoreMode {
                    Toggle("Show Compose by Default", isOn: $showComposeByDefault)
                        .accessibilityIdentifier("pane-show-compose-toggle")
                    Divider()

                    Button {
                        if let workspace {
                            pendingWorkspaceAction = .rename(workspace)
                        }
                    } label: {
                        Label("Rename Workspace", systemImage: "square.and.pencil")
                    }
                    .disabled(workspace == nil)
                    .accessibilityIdentifier("workspace-rename-button")

                    Button(role: .destructive) {
                        if let workspace {
                            pendingWorkspaceAction = .close(workspace)
                        }
                    } label: {
                        Label("Close Workspace", systemImage: "xmark.circle")
                    }
                    .disabled(workspace == nil)
                    .accessibilityIdentifier("workspace-close-button")

                    Button(role: .destructive) {
                        if let workspace {
                            pendingWorkspaceAction = .deleteWorktree(workspace)
                        }
                    } label: {
                        Label("Delete Worktree Checkout", systemImage: "trash")
                    }
                    .disabled(workspace?.worktree == nil)
                    .accessibilityIdentifier("workspace-delete-worktree-button")
                    }

                    #if DEBUG
                    Divider()

                    Button {
                        showLiveDiagnostics.toggle()
                        PaneLiveInputMetrics.shared.setEnabled(showLiveDiagnostics)
                    } label: {
                        Label(
                            showLiveDiagnostics ? "Hide Diagnostics" : "Show Diagnostics",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                    .accessibilityLabel(showLiveDiagnostics ? "Hide diagnostics" : "Show diagnostics")
                    .accessibilityIdentifier("pane-diagnostics-button")
                    #endif
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.jost(16, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .disabled(isPerformingAction)
                .accessibilityLabel("Pane Options")
                .accessibilityIdentifier("pane-options-menu")
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: selectedPaneID) { _, selected in
            bridgeUpgrade.bridgeVersion = nil
            openPaneMemory?.remember(selected)
        }
        // Pushed panes hide the tab bar; in the detail column it stays so tabs can still switch.
        .toolbar(showsPaneBackButton ? .hidden : .automatic, for: .tabBar)
        .onDisappear {
            #if DEBUG
            showLiveDiagnostics = false
            PaneLiveInputMetrics.shared.setEnabled(false)
            #endif
        }
        .sheet(item: $pendingWorkspaceAction) { action in
            WorkspaceActionDrawer(
                action: action,
                onConfirm: { outcome in
                    pendingWorkspaceAction = nil
                    Task { await performWorkspaceAction(action, outcome: outcome) }
                },
                onCancel: {
                    pendingWorkspaceAction = nil
                }
            )
            .presentationDetents([.height(WorkspaceActionDrawer.estimatedHeight(for: action))])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
        }
        .alert("Rename Pane", isPresented: $isShowingRenameAlert) {
            TextField("Pane Name", text: $renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("pane-rename-text-field")
            Button("Rename") {
                let target = actionTargetPane ?? selectedPane
                let name = renameText
                actionTargetPane = nil
                Task {
                    await renamePane(target, to: name)
                }
            }
            .accessibilityIdentifier("pane-rename-confirm-button")
            Button("Cancel", role: .cancel) {
                actionTargetPane = nil
            }
        } message: {
            Text("Enter a new name for this pane.")
        }
        .confirmationDialog(
            "Kill Pane",
            isPresented: $isShowingKillConfirmation,
            titleVisibility: .visible
        ) {
            Button("Kill Pane", role: .destructive) {
                let target = actionTargetPane ?? selectedPane
                actionTargetPane = nil
                Task {
                    await killPane(target)
                }
            }
            .accessibilityIdentifier("pane-kill-confirm-button")
            Button("Cancel", role: .cancel) {
                actionTargetPane = nil
            }
        } message: {
            let title = (actionTargetPane ?? selectedPane).displayTitle
            Text("Are you sure you want to kill “\(title)”? This will close the terminal pane.")
        }
        .alert(
            "Action Failed",
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                actionErrorMessage = nil
            }
        } message: {
            if let actionErrorMessage {
                Text(actionErrorMessage)
            }
        }
        .sheet(isPresented: $isShowingAddPane, onDismiss: {
            guard let request = pendingAddPane else { return }
            pendingAddPane = nil
            Task { await addPane(request) }
        }) {
            AddPaneDrawer(
                onAdd: { request in
                    pendingAddPane = request
                    isShowingAddPane = false
                },
                onCancel: {
                    pendingAddPane = nil
                    isShowingAddPane = false
                }
            )
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
        }
        .task(id: pane.workspaceId) {
            await refreshWorkspace()
            await refreshPeersAndTabs()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                let auto = spacesModel?.autoRefreshEnabled ?? true
                let active = appModel.isSceneActive
                guard PaneRefreshPolicy.shouldAutoPoll(
                    autoRefreshEnabled: auto,
                    isSceneActive: active
                ) else { continue }
                await refreshPeersAndTabs()
            }
        }
        .onChange(of: appModel.runtimeRevision) { _, _ in
            guard appModel.isCoreMode, appModel.isSceneActive, !appModel.isOffline else { return }
            Task {
                await refreshWorkspace()
                await refreshPeersAndTabs()
            }
        }
    }

    /// Leaves the pane: clears the list selection when shown from a list,
    /// so the split view's detail column empties too, else pops the stack.
    private func leave() {
        if let closeDetail {
            closeDetail()
        } else {
            dismiss()
        }
    }

    private func refreshPeersAndTabs() async {
        if let latest = try? await appModel.connection.paneList(workspaceId: pane.workspaceId),
           !Task.isCancelled {
            switch PanePeerRefresh.outcome(peers: latest, selectedPaneID: selectedPaneID) {
            case .dismiss:
                leave()
            case let .apply(peers, nextSelected):
                siblings = peers
                lastUpdatedByPaneID = PaneLastUpdatedStore.observe(peers, scope: connectionScope)
                selectedPaneID = nextSelected
            }
        }
        if let latestTabs = try? await appModel.connection.tabList(workspaceId: pane.workspaceId),
           !Task.isCancelled {
            tabs = PanePeerRefresh.sortedTabs(latestTabs)
        }
    }

    private func beginRename(_ pane: PaneEntry) {
        actionTargetPane = pane
        let initial = (pane.label != nil && pane.label != "command")
            ? pane.label!
            : pane.displayTitle
        renameText = initial
        isShowingRenameAlert = true
    }

    private func beginKill(_ pane: PaneEntry) {
        actionTargetPane = pane
        isShowingKillConfirmation = true
    }

    /// Loads the workspace owning this pane so workspace-level actions act on
    /// live label / worktree data.
    private func refreshWorkspace() async {
        guard
            let latest = try? await appModel.connection.workspaceList(),
            let match = latest.first(where: { $0.workspaceId == pane.workspaceId })
        else { return }
        workspace = match
    }

    /// Executes a drawer-confirmed workspace action. Close and worktree
    /// removal tear down every pane in the workspace, so the detail view
    /// dismisses itself on success.
    private func performWorkspaceAction(_ action: WorkspaceAction, outcome: WorkspaceActionOutcome) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            switch (action, outcome) {
            case let (.rename(target), .rename(name)):
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                workspace = try await appModel.connection.workspaceRename(
                    workspaceId: target.workspaceId,
                    label: trimmed
                )
            case let (.close(target), .close):
                try await appModel.connection.workspaceClose(workspaceId: target.workspaceId)
                leave()
            case let (.deleteWorktree(target), .deleteWorktree(force, trustRepository)):
                try await appModel.connection.worktreeRemove(
                    workspaceId: target.workspaceId,
                    force: force,
                    trustRepository: trustRepository
                )
                leave()
            default:
                return
            }
        } catch {
            actionErrorMessage = HerdrConnection.friendlyMessage(for: error)
        }
    }

    private func renamePane(_ paneToRename: PaneEntry, to newName: String) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let updatedPane = try await appModel.connection.paneRename(paneId: paneToRename.paneId, name: newName)
            if let idx = siblings.firstIndex(where: { $0.id == updatedPane.id }) {
                siblings[idx] = updatedPane
            }
            if let latest = try? await appModel.connection.paneList(workspaceId: paneToRename.workspaceId) {
                siblings = latest
                lastUpdatedByPaneID = PaneLastUpdatedStore.observe(latest, scope: connectionScope)
            }
        } catch {
            actionErrorMessage = HerdrConnection.friendlyMessage(for: error)
        }
    }

    private func killPane(_ paneToKill: PaneEntry) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await appModel.connection.paneClose(paneId: paneToKill.paneId)
            let remaining = siblings.filter { $0.id != paneToKill.id }
            siblings = remaining
            if remaining.isEmpty {
                leave()
            } else {
                if selectedPaneID == paneToKill.id {
                    selectedPaneID = remaining[0].id
                }
            }
            if let latest = try? await appModel.connection.paneList(workspaceId: paneToKill.workspaceId) {
                siblings = latest
                lastUpdatedByPaneID = PaneLastUpdatedStore.observe(latest, scope: connectionScope)
                if latest.isEmpty {
                    leave()
                } else if !latest.contains(where: { $0.id == selectedPaneID }) {
                    selectedPaneID = latest[0].id
                }
            }
        } catch {
            actionErrorMessage = HerdrConnection.friendlyMessage(for: error)
        }
    }

    private func addPane(_ request: AddPaneRequest) async {
        isPerformingAction = true
        let source = selectedPane
        withAnimation(.snappy(duration: 0.28)) {
            creatingPane = PendingPanePlaceholder(
                title: PendingPanePlaceholder.title(name: request.name, kind: request.kind),
                afterPaneID: request.kind == .pane ? source.id : nil,
                kind: request.kind
            )
        }
        defer {
            isPerformingAction = false
            withAnimation(.snappy(duration: 0.28)) {
                creatingPane = nil
            }
        }
        do {
            let createdPaneID: String
            var createdPane: PaneEntry?
            switch request.kind {
            case .pane:
                let created = try await appModel.connection.paneSplit(
                    paneId: source.paneId,
                    direction: "right",
                    cwd: source.cwd,
                    focus: false
                )
                createdPaneID = created.paneId
                createdPane = created
                let trimmedName = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedName.isEmpty {
                    createdPane = try await appModel.connection.paneRename(paneId: createdPaneID, name: trimmedName)
                }
            case .tab:
                createdPaneID = try await appModel.connection.tabCreate(
                    workspaceId: source.workspaceId,
                    cwd: source.cwd,
                    label: request.name
                )
            }
            if let latest = try? await appModel.connection.paneList(workspaceId: source.workspaceId) {
                siblings = latest
                lastUpdatedByPaneID = PaneLastUpdatedStore.observe(latest, scope: connectionScope)
                if latest.contains(where: { $0.id == createdPaneID }) {
                    selectedPaneID = createdPaneID
                }
            } else if let createdPane {
                siblings.append(createdPane)
                lastUpdatedByPaneID = PaneLastUpdatedStore.observe(siblings, scope: connectionScope)
                selectedPaneID = createdPaneID
            }
            if let latestTabs = try? await appModel.connection.tabList(workspaceId: source.workspaceId) {
                tabs = PanePeerRefresh.sortedTabs(latestTabs)
            }
        } catch {
            actionErrorMessage = HerdrConnection.friendlyMessage(for: error)
            if let latest = try? await appModel.connection.paneList(workspaceId: source.workspaceId) {
                siblings = latest
                lastUpdatedByPaneID = PaneLastUpdatedStore.observe(latest, scope: connectionScope)
            }
        }
    }
}
