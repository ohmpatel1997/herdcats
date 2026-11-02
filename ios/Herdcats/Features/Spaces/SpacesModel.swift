import Foundation
import Observation
import SwiftUI

// MARK: - Spaces model

@MainActor
@Observable
final class SpacesModel {
    private(set) var spaces: [Space] = [] {
        didSet {
            spaceGroups = SpaceGroup.group(spaces)
        }
    }
    private(set) var spaceGroups: [SpaceGroup] = []
    /// Latest pane activity among the space's agents — the list row's timestamp.
    func lastActivity(in space: Space) -> Date? {
        let dates = lastUpdatedByPaneID
        return space.agents.compactMap { dates[$0.paneId] }.max()
    }

    private(set) var lastUpdated: Date?
    /// Pane-id → last activity time, shared with pane detail cards.
    private(set) var lastUpdatedByPaneID: [String: Date] = [:]
    // The view can render before its initial refresh task starts.
    private(set) var isLoading = true

    /// A successful refresh confirms the agent list, even when it is empty.
    var hasLoadedAgentList: Bool {
        return lastUpdated != nil
    }
    /// Provider usage cards for the Agents header (from remote `quota-axi`).
    var usageCards: [AgentUsageCard] = []
    var usageLastUpdated: Date?
    var usageUnavailableMessage: String?
    /// True when the Herdr machine has no `quota-axi` binary to query.
    var quotaAxiMissing = false
    /// quota-axi provider ids with a card retry in flight.
    var retryingUsageProviders: Set<String> = []

    var errorMessage: String?

    /// Initial failures must expose Retry instead of looking like an endless load.
    var agentListError: String? {
        guard let errorMessage,
              !HerdrConnection.isDisconnectionOrTransitionMessage(errorMessage) else { return nil }
        return errorMessage
    }

    var showsAgentLoading: Bool {
        isLoading || (!hasLoadedAgentList && agentListError == nil)
    }
    var autoRefreshEnabled = true
    /// When false, periodic polls sleep without issuing remote commands.
    /// Initial / pull-to-refresh loads still run.
    var isSceneActive = true
    private(set) var isCreatingSpace = false
    private(set) var pendingSpaceCreationTitle: String?
    private(set) var lastPresentedSpaceID: String?
    private(set) var unconfirmedSpaces: [Space] = []
    private(set) var pendingWorktreeAction: PendingWorktreeAction?
    private(set) var highlightedWorktreeID: String?

    var visibleSpaceGroups: [SpaceGroup] {
        guard !unconfirmedSpaces.isEmpty else { return spaceGroups }
        return SpaceGroup.group(SpacePresentationOverlay.visibleSpaces(spaces, unconfirmed: unconfirmedSpaces))
    }

    /// Attention badge for the Agents tab — hidden while zero.
    var blockedAgentCount: Int {
        spaces.flatMap(\.agents).filter { AgentStatus(rawValue: $0.agentStatus) == .blocked }.count
    }

    var autoRefreshTask: Task<Void, Never>?
    /// Counts started refreshes so the auto-refresh loop can restart its
    /// interval after an event-driven or manual refresh.
    @ObservationIgnored var refreshEpoch = 0
    var usageRefreshTask: Task<Void, Never>?
    enum QuotaContentState: Equatable {
        case loading, cards, notSetup, empty
        case error(String)
    }
    var hasCompletedUsageRequest = false
    var quotaContentState: QuotaContentState {
        if !usageCards.isEmpty { return .cards }
        if quotaAxiMissing { return .notSetup }
        if isRefreshingUsage { return .loading }
        if let message = usageUnavailableMessage { return .error(message) }
        if usageLastUpdated != nil || hasCompletedUsageRequest { return .empty }
        return .loading // Initial view mounts before its fetch task starts.
    }
    var isRefreshingUsage = false
    @ObservationIgnored var quotaRetryFetch: ((String) async throws -> QuotaReport)?
    @ObservationIgnored var quotaReportFetch: (() async throws -> QuotaReport)?
    @ObservationIgnored var agentListFetch: (() async throws -> ([Workspace], [AgentEntry]))?
    private var refreshGate = RefreshGenerationGate()
    var usageGate = RefreshGenerationGate()
    private var connectionScope: ConnectionIdentity?
    private var spaceCreationGeneration = 0
    private var worktreeActionGeneration = 0
    /// Agent statuses from the last successful refresh; `nil` until the first
    /// load so connecting never replays existing done / blocked states.
    private var alertBaseline: [String: AgentStatus]?
    /// Test seam: plays the user's chosen sound and haptic for an agent alert.
    var playAlert: (AgentAlertEvent) -> Void = { event in
        AgentAlertSound.selected(for: event).play()
        HapticFeedback.play(for: event)
    }

    func bindConnectionScope(_ scope: ConnectionIdentity?) {
        if connectionScope != scope {
            spaceCreationGeneration += 1
            isCreatingSpace = false
            pendingSpaceCreationTitle = nil
            lastPresentedSpaceID = nil
            unconfirmedSpaces = []
            worktreeActionGeneration += 1
            isPerformingWorktreeAction = false
            pendingWorktreeAction = nil
            highlightedWorktreeID = nil
        }
        connectionScope = scope
        alertBaseline = nil
        if let scope {
            lastUpdatedByPaneID = PaneLastUpdatedStore.dates(scope: scope)
        } else {
            lastUpdatedByPaneID = [:]
        }
    }

    func refresh(_ connection: HerdrConnection) async {
        let generation = refreshGate.begin()
        refreshEpoch &+= 1
        isLoading = true

        // Watchdog: invalidate this generation so a late completion cannot
        // overwrite a newer refresh, then unlock the UI.
        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard let self else { return }
            guard self.refreshGate.watchdogTimeout(for: generation) else { return }
            self.isLoading = false
            self.errorMessage = "Refreshing timed out — the connection may be unhealthy."
        }
        defer {
            watchdog.cancel()
            if refreshGate.finishIfCurrent(generation) {
                isLoading = false
            }
        }

        do {
            let workspaceList: [Workspace]
            let agentList: [AgentEntry]
            if let agentListFetch {
                (workspaceList, agentList) = try await agentListFetch()
            } else {
                async let workspaces = connection.workspaceList()
                async let agents = connection.agentList()
                (workspaceList, agentList) = try await (workspaces, agents)
            }
            guard refreshGate.isCurrent(generation) else { return }
            spaces = Space.join(workspaces: workspaceList, agents: agentList)
            unconfirmedSpaces = SpacePresentationOverlay.unconfirmed(
                unconfirmedSpaces,
                after: spaces
            )
            if let event = AgentStatusAlerts.event(previous: alertBaseline, current: agentList) {
                playAlert(event)
            }
            alertBaseline = AgentStatusAlerts.snapshot(agentList)
            let fallbackScope: ConnectionIdentity?
            if let connectionScope {
                fallbackScope = connectionScope
            } else {
                fallbackScope = await connection.identity
            }
            if let scope = fallbackScope {
                connectionScope = scope
                lastUpdatedByPaneID = PaneLastUpdatedStore.observe(agentList, scope: scope)
            }
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            guard refreshGate.isCurrent(generation) else { return }
            reportError(error)
        }
    }

    private func reportError(_ error: Error) {
        let message = HerdrConnection.friendlyMessage(for: error)
        if !HerdrConnection.isDisconnectionOrTransitionMessage(message) {
            errorMessage = message
        }
    }

    /// Creates a new space on the Herdr machine. When `base` is set, the new
    /// space opens in that space's directory; `nil` lets herdr pick the
    /// default directory.
    func createSpace(basedOn base: Space?, _ connection: HerdrConnection) async {
        guard !isCreatingSpace else { return }
        spaceCreationGeneration += 1
        let generation = spaceCreationGeneration
        isCreatingSpace = true
        errorMessage = nil
        lastPresentedSpaceID = nil
        withAnimation(.snappy(duration: 0.28)) {
            pendingSpaceCreationTitle = base.map { "Creating space from \($0.label)…" } ?? "Creating space…"
        }
        defer {
            if spaceCreationGeneration == generation {
                isCreatingSpace = false
                withAnimation(.snappy(duration: 0.28)) {
                    pendingSpaceCreationTitle = nil
                }
            }
        }
        do {
            let target = connection
            let cwd = try await Self.baseWorkingDirectory(for: base, connection: target)
            guard spaceCreationGeneration == generation, !Task.isCancelled else { return }
            let created = (try await target.workspaceCreate(cwd: cwd)).workspace
            guard spaceCreationGeneration == generation, !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.28)) {
                if !spaces.contains(where: { $0.workspace.workspaceId == created.workspaceId }) {
                    unconfirmedSpaces.append(Space(workspace: created, agents: []))
                }
                pendingSpaceCreationTitle = nil
                lastPresentedSpaceID = created.workspaceId
            }
            await refresh(connection)
        } catch {
            guard spaceCreationGeneration == generation, !Task.isCancelled else { return }
            reportError(error)
        }
    }

    private(set) var isPerformingWorktreeAction = false

    /// Finds the default (root / primary non-linked) space for the repository of a given space,
    /// falling back to the space itself if none is found.
    func defaultSpace(for space: Space, in spaces: [Space]? = nil) -> Space {
        let pool = spaces ?? self.spaces
        guard let repoRoot = space.workspace.worktree?.repoRoot, !repoRoot.isEmpty else {
            return space
        }
        return pool.first { candidate in
            candidate.workspace.worktree?.repoRoot == repoRoot &&
            candidate.workspace.worktree?.isLinkedWorktree == false
        } ?? space
    }

    /// Opens an existing Git worktree in the specified space.
    func openWorktree(
        in space: Space,
        path: String? = nil,
        branch: String? = nil,
        _ connection: HerdrConnection
    ) async {
        guard !isPerformingWorktreeAction else { return }
        worktreeActionGeneration += 1
        let generation = worktreeActionGeneration
        let targetSpace = defaultSpace(for: space)
        isPerformingWorktreeAction = true
        errorMessage = nil
        lastPresentedSpaceID = nil
        highlightedWorktreeID = nil
        withAnimation(.snappy(duration: 0.28)) {
            pendingWorktreeAction = PendingWorktreeAction(
                sourceSpaceID: targetSpace.id,
                title: PendingWorktreeAction.openTitle(path: path, branch: branch)
            )
        }
        defer { finishWorktreeAction(generation) }
        do {
            let conn = connection
            let result: WorktreeOpenResult
            if targetSpace.workspace.worktree?.isLinkedWorktree == false {
                result = try await conn.worktreeOpen(
                    workspaceId: targetSpace.workspace.workspaceId,
                    path: path,
                    branch: branch
                )
            } else if let repoRoot = targetSpace.workspace.worktree?.repoRoot, !repoRoot.isEmpty {
                result = try await conn.worktreeOpen(
                    cwd: repoRoot,
                    path: path,
                    branch: branch
                )
            } else {
                result = try await conn.worktreeOpen(
                    workspaceId: targetSpace.workspace.workspaceId,
                    path: path,
                    branch: branch
                )
            }
            guard worktreeActionGeneration == generation, !Task.isCancelled else { return }
            presentWorktree(result.workspace, entry: result.worktree, source: targetSpace)
            await refresh(connection)
        } catch {
            guard worktreeActionGeneration == generation, !Task.isCancelled else { return }
            reportError(error)
        }
    }

    /// Creates and opens a new Git worktree based on the specified space.
    func createWorktree(
        in space: Space,
        name: String? = nil,
        label: String? = nil,
        _ connection: HerdrConnection
    ) async {
        guard !isPerformingWorktreeAction else { return }
        worktreeActionGeneration += 1
        let generation = worktreeActionGeneration
        let targetSpace = defaultSpace(for: space)
        isPerformingWorktreeAction = true
        errorMessage = nil
        lastPresentedSpaceID = nil
        highlightedWorktreeID = nil
        withAnimation(.snappy(duration: 0.28)) {
            pendingWorktreeAction = PendingWorktreeAction(
                sourceSpaceID: targetSpace.id,
                title: PendingWorktreeAction.createTitle(name: name, label: label)
            )
        }
        defer { finishWorktreeAction(generation) }
        do {
            let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let branch = trimmedName?.isEmpty == false ? trimmedName : nil
            let labelText = trimmedLabel?.isEmpty == false ? trimmedLabel : nil
            let conn = connection

            let result: WorktreeCreateResult
            if targetSpace.workspace.worktree?.isLinkedWorktree == false {
                result = try await conn.worktreeCreate(
                    workspaceId: targetSpace.workspace.workspaceId,
                    branch: branch,
                    label: labelText
                )
            } else if let repoRoot = targetSpace.workspace.worktree?.repoRoot, !repoRoot.isEmpty {
                result = try await conn.worktreeCreate(
                    cwd: repoRoot,
                    branch: branch,
                    label: labelText
                )
            } else {
                result = try await conn.worktreeCreate(
                    workspaceId: targetSpace.workspace.workspaceId,
                    branch: branch,
                    label: labelText
                )
            }
            guard worktreeActionGeneration == generation, !Task.isCancelled else { return }
            presentWorktree(result.workspace, entry: result.worktree, source: targetSpace)
            await refresh(connection)
        } catch {
            guard worktreeActionGeneration == generation, !Task.isCancelled else { return }
            reportError(error)
        }
    }

    private func presentWorktree(_ workspace: Workspace, entry: WorktreeEntry?, source: Space) {
        let presented = WorktreePresentation.space(workspace, entry: entry, source: source)
        withAnimation(.snappy(duration: 0.28)) {
            if !spaces.contains(where: { $0.id == presented.id }) {
                unconfirmedSpaces.append(presented)
            }
            pendingWorktreeAction = nil
            lastPresentedSpaceID = presented.id
            highlightedWorktreeID = presented.id
        }
        let highlightedID = presented.id
        let generation = worktreeActionGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard self?.worktreeActionGeneration == generation,
                  self?.highlightedWorktreeID == highlightedID else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self?.highlightedWorktreeID = nil
            }
        }
    }

    private func finishWorktreeAction(_ generation: Int) {
        guard worktreeActionGeneration == generation else { return }
        isPerformingWorktreeAction = false
        withAnimation(.snappy(duration: 0.28)) {
            pendingWorktreeAction = nil
        }
    }

    private(set) var isPerformingSpaceAction = false

    /// Renames a space (Herdr workspace label).
    func renameSpace(_ space: Space, to name: String, _ connection: HerdrConnection) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPerformingSpaceAction else { return }
        isPerformingSpaceAction = true
        defer { isPerformingSpaceAction = false }
        do {
            try await connection.workspaceRename(workspaceId: space.workspace.workspaceId, label: trimmed)
            await refresh(connection)
        } catch {
            reportError(error)
        }
    }

    /// Closes a space and removes it from the list after refresh.
    func closeSpace(_ space: Space, _ connection: HerdrConnection) async {
        guard !isPerformingSpaceAction else { return }
        isPerformingSpaceAction = true
        defer { isPerformingSpaceAction = false }
        do {
            try await connection.workspaceClose(workspaceId: space.workspace.workspaceId)
            await refresh(connection)
        } catch {
            reportError(error)
        }
    }

    /// Directory a new space inherits from the space it is based on: the
    /// checkout path when the space has repo metadata, else the first live
    /// pane's working directory.
    private static func baseWorkingDirectory(
        for base: Space?,
        connection: HerdrConnection
    ) async throws -> String? {
        guard let base else { return nil }
        if let checkout = base.workspace.worktree?.checkoutPath, !checkout.isEmpty {
            return checkout
        }
        let panes = try await connection.paneList(workspaceId: base.workspace.workspaceId)
        return panes.first { $0.cwd?.isEmpty == false }?.cwd
    }
}
