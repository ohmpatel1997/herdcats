import SwiftUI

/// What the Timeline shows and says about the agent's live state.
enum TimelineLiveState {
    /// "<name> is working" shows while the live Timeline reports working
    /// and nothing waits for an answer. A suspended Timeline keeps its last
    /// status until a new snapshot arrives, so it shows nothing. A running
    /// tool row already shows progress, so the working row stays out of its way.
    static func showsWorkingRow(
        isLive: Bool,
        agentStatus: String?,
        lastItem: TimelineConversationItem?,
        pendingApproval: Bool,
        pendingQuestion: Bool,
        pendingPiDialog: Bool
    ) -> Bool {
        guard isLive, agentStatus == AgentStatus.working.rawValue,
              !pendingApproval, !pendingQuestion, !pendingPiDialog else { return false }
        if let lastItem, lastItem.isActivity, lastItem.entries.contains(where: TimelineActivitySummary.isRunning) {
            return false
        }
        return true
    }

    /// What VoiceOver says when the agent's status changes, or nil. It
    /// follows the app's alert sounds exactly:
    /// - into blocked from anything else: "<name> needs your answer";
    /// - into done from anything else, or working → idle: "<name> finished".
    ///   Herdr reports idle instead of done when the pane is being looked at.
    /// Nothing is said for the first status, or for a pane that isn't focused,
    /// so two Timelines side by side don't talk over each other.
    static func turnEndAnnouncement(agentName: String, previous: String?, current: String?,
                                    isFocusedPane: Bool) -> String? {
        guard isFocusedPane, let previous, let current else { return nil }
        let before = AgentStatus(rawValue: previous) ?? .unknown
        let now = AgentStatus(rawValue: current) ?? .unknown
        if now == .blocked, before != .blocked { return "\(agentName) needs your answer" }
        if (now == .done && before != .done) || (now == .idle && before == .working) {
            return "\(agentName) finished"
        }
        return nil
    }

    /// How long to wait before saying an announcement, then only if the
    /// status hasn't moved on. "Needs your answer" is said at once. A
    /// "finished" waits, so a brief idle between tool calls mid-turn isn't
    /// announced as the end of the turn.
    static func announcementDelay(for current: String?) -> Duration {
        current == AgentStatus.blocked.rawValue ? .zero : .seconds(2)
    }
}

/// Counts messages that arrived while you were scrolled up, for the badge
/// on the jump-to-latest button.
///
/// It remembers the message items on screen when you were last at the
/// bottom, then counts the agent's new messages and images after the newest
/// of those that still exists. Your own messages anchor the count but are
/// never counted: you sent them. So:
/// - a history page loaded above doesn't count;
/// - a message revised in place keeps its id and doesn't count;
/// - tool steps aren't messages, so a tool joining a group doesn't count;
/// - if the newest seen message was evicted, the next newest seen one
///   anchors the count, and if none survives, the count starts again at 0.
struct TimelineUnseenCounter: Equatable {
    private var seen: Set<String> = []
    private(set) var count = 0

    static func isMessage(_ item: TimelineConversationItem) -> Bool {
        let role = TimelineTurnLayout.role(item)
        return role == .user || role == .agent
    }

    /// Everything currently loaded counts as seen.
    mutating func markSeen(_ items: [TimelineConversationItem]) {
        seen = Set(items.lazy.filter(Self.isMessage).map(\.id))
        count = 0
    }

    mutating func update(_ items: [TimelineConversationItem]) {
        let messages = items.filter(Self.isMessage)
        guard let anchor = messages.lastIndex(where: { seen.contains($0.id) }) else {
            markSeen(items)
            return
        }
        count = messages[(anchor + 1)...].filter {
            !seen.contains($0.id) && TimelineTurnLayout.role($0) == .agent
        }.count
    }

    /// The badge's text: nothing at zero, and at most "99+".
    static func badgeText(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }
}

/// "<name> is working", with the working spinner, under the conversation.
struct TimelineWorkingRow: View {
    let agent: String
    @ScaledMetric(relativeTo: .footnote) private var iconSize: CGFloat = 13

    var body: some View {
        let label = "\(TimelineSpeaker.name(agent: agent)) is working"
        HStack(spacing: 6) {
            AgentKindIcon(kind: TimelineSpeaker.iconKind(agent: agent), size: iconSize)
            Text(label)
                .font(.jost(.footnote))
                .foregroundStyle(Theme.textMuted)
            CircularArcSpinner(size: 14, color: Theme.statusWorking)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("timeline-working")
    }
}
