import Foundation
import SwiftUI

// MARK: - Spaces model usage reporting and background refresh

extension SpacesModel {
    /// Rate-limited unless `force` is set (pull-to-refresh / periodic poll).
    func refreshUsage(_ connection: HerdrConnection, force: Bool = false) async {
        guard !isRefreshingUsage else { return }
        if !force, let last = usageLastUpdated, Date().timeIntervalSince(last) < 50 {
            return
        }
        let generation = usageGate.begin()
        isRefreshingUsage = true
        usageUnavailableMessage = nil
        defer {
            if usageGate.finishIfCurrent(generation) {
                isRefreshingUsage = false
                hasCompletedUsageRequest = true
            }
        }

        do {
            let report: QuotaReport
            if let quotaReportFetch {
                report = try await quotaReportFetch()
            } else {
                report = try await connection.quotaReport()
            }
            try Task.checkCancellation()
            guard usageGate.isCurrent(generation) else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                applyUsageReport(report)
            }
        } catch is CancellationError {
            // Expected view retirement is a settled request, not an active retry/error.
        } catch let error as HerdrError where error == .quotaAxiNotFound {
            guard !Task.isCancelled else { return }
            guard usageGate.isCurrent(generation) else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                usageCards = []
                usageUnavailableMessage = nil
                quotaAxiMissing = true
            }
        } catch {
            guard !Task.isCancelled else { return }
            guard usageGate.isCurrent(generation) else { return }
            // Keep the last good snapshot; only surface a soft note when empty.
            quotaAxiMissing = false
            if usageCards.isEmpty {
                let raw = HerdrConnection.friendlyMessage(for: error)
                if raw.localizedCaseInsensitiveContains("commandfailed")
                    || raw.localizedCaseInsensitiveContains("exitcode") {
                    usageUnavailableMessage = "Could not read quota-axi on this remote machine. Pull to refresh."
                } else {
                    usageUnavailableMessage = raw
                }
            }
        }
    }

    func applyUsageReport(_ report: QuotaReport) {
        usageCards = report.usageCards()
        usageLastUpdated = Date()
        usageUnavailableMessage = nil
        quotaAxiMissing = false
    }

    /// Re-reads one provider's quota for its unavailable card's retry button.
    func retryUsage(provider id: String, connection: HerdrConnection) async {
        if let quotaRetryFetch {
            await retryUsage(provider: id, fetch: quotaRetryFetch)
            return
        }
        await retryUsage(provider: id) { try await connection.quotaReport(provider: $0) }
    }

    /// Test seam for `retryUsage(provider:connection:)`. A newer full refresh
    /// wins; a failed retry keeps the card in its unavailable state.
    func retryUsage(provider id: String, fetch: (String) async throws -> QuotaReport) async {
        guard !isRefreshingUsage, !retryingUsageProviders.contains(id) else { return }
        retryingUsageProviders.insert(id)
        defer { retryingUsageProviders.remove(id) }
        let generation = usageGate.generation
        guard let report = try? await fetch(id) else { return }
        guard usageGate.isCurrent(generation), !isRefreshingUsage, !usageCards.isEmpty else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            usageCards = AgentUsageCard.merging(usageCards, quotaProvider: id, report: report)
        }
    }

    func startAutoRefresh(_ connection: HerdrConnection) {
        stopAutoRefresh()
        autoRefreshTask = Task { [weak self] in
            var clock = SpacesAutoRefreshClock(epoch: self?.refreshEpoch ?? 0)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(SpacesRefreshPolicy.tick))
                } catch {
                    return
                }
                guard let self else { return }
                clock.advance(epoch: self.refreshEpoch)
                guard self.autoRefreshEnabled, self.isSceneActive else { continue }
                let interval = await SpacesRefreshPolicy.interval(
                    isCoreMode: connection.backend == .core,
                    eventsOpen: connection.coreEventsOpen
                )
                guard clock.isDue(interval: interval) else { continue }
                clock.didRefresh(epoch: self.refreshEpoch)
                await self.refresh(connection)
                clock.seenEpoch = self.refreshEpoch
            }
        }
        // Quota changes slowly; poll independently so the 5s herdr loop stays light.
        usageRefreshTask = Task { [weak self] in
            // First fetch shortly after connect (spaces refresh runs in parallel).
            await self?.refreshUsage(connection, force: true)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard let self else { return }
                guard self.autoRefreshEnabled, self.isSceneActive else { continue }
                await self.refreshUsage(connection, force: true)
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        usageRefreshTask?.cancel()
        usageRefreshTask = nil
    }
}

// MARK: - Worktree and space presentation helpers

struct PendingWorktreeAction: Equatable {
    static let viewID = "worktree-pending-row"

    let sourceSpaceID: String
    let title: String

    static func openTitle(path: String?, branch: String?) -> String {
        let subject = [branch, path.map { ($0 as NSString).lastPathComponent }]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let subject else { return "Opening worktree…" }
        return "Opening worktree “\(subject)”…"
    }

    static func createTitle(name: String?, label: String?) -> String {
        let subject = [label, name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let subject else { return "Creating worktree…" }
        return "Creating worktree “\(subject)”…"
    }
}

enum WorktreePresentation {
    static func space(_ workspace: Workspace, entry: WorktreeEntry?, source: Space) -> Space {
        guard workspace.worktree == nil,
              let entry,
              let sourceWorktree = source.workspace.worktree else {
            return Space(workspace: workspace, agents: [])
        }
        let completed = Workspace(
            workspaceId: workspace.workspaceId,
            label: workspace.label,
            number: workspace.number,
            tabCount: workspace.tabCount,
            paneCount: workspace.paneCount,
            activeTabId: workspace.activeTabId,
            agentStatus: workspace.agentStatus,
            focused: workspace.focused,
            worktree: Worktree(
                checkoutPath: entry.path,
                repoName: sourceWorktree.repoName,
                repoRoot: sourceWorktree.repoRoot,
                isLinkedWorktree: entry.isLinkedWorktree ?? true
            )
        )
        return Space(workspace: completed, agents: [])
    }
}

/// Holds successful command responses on screen until a list refresh confirms them.
enum SpacePresentationOverlay {
    static func visibleSpaces(_ spaces: [Space], unconfirmed: [Space]) -> [Space] {
        let listedIDs = Set(spaces.map(\.id))
        return spaces + unconfirmed.filter { !listedIDs.contains($0.id) }
    }

    static func unconfirmed(_ pending: [Space], after spaces: [Space]) -> [Space] {
        let listedIDs = Set(spaces.map(\.id))
        return pending.filter { !listedIDs.contains($0.id) }
    }
}

/// State machine tracking elapsed auto-refresh time and resets from
/// out-of-band refreshes (Core events, foreground returns, manual pulls).
struct SpacesAutoRefreshClock: Equatable {
    var elapsed: TimeInterval = 0
    var seenEpoch: Int
    let tick: TimeInterval

    init(epoch: Int, tick: TimeInterval = SpacesRefreshPolicy.tick) {
        self.seenEpoch = epoch
        self.tick = tick
    }

    mutating func advance(epoch: Int) {
        if epoch != seenEpoch {
            elapsed = 0
        }
        seenEpoch = epoch
        elapsed += tick
    }

    func isDue(interval: TimeInterval) -> Bool {
        SpacesRefreshPolicy.isDue(elapsed: elapsed, interval: interval)
    }

    mutating func didRefresh(epoch: Int) {
        elapsed = 0
        seenEpoch = epoch
    }
}

/// Cadence of the Spaces auto-refresh loop. Core pushes events that already
/// trigger refreshes, so while its subscription is open the loop only runs a
/// slow safety refresh.
enum SpacesRefreshPolicy {
    /// Wake-up granularity of the loop.
    static let tick: TimeInterval = 5
    static let tuiInterval: TimeInterval = 5
    static let coreSafetyInterval: TimeInterval = 60

    static func interval(isCoreMode: Bool, eventsOpen: Bool) -> TimeInterval {
        isCoreMode && eventsOpen ? coreSafetyInterval : tuiInterval
    }

    static func isDue(elapsed: TimeInterval, interval: TimeInterval) -> Bool {
        elapsed >= interval
    }
}
