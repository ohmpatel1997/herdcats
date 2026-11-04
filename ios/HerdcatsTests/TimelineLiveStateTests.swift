import Foundation
import Testing

@testable import Herdcats

/// The working row, spoken status updates, and the unseen-message badge.
@Suite("Timeline live state")
struct TimelineLiveStateTests {
    private func message(_ id: String, role: String = "assistant", kind: String = "message") -> AgentTimelineEntry {
        AgentTimelineEntry(id: id, kind: kind, text: id, role: role, toolName: nil,
                           status: nil, details: nil, truncated: false)
    }
    private func tool(_ id: String, status: String = "completed") -> AgentTimelineEntry {
        AgentTimelineEntry(id: id, kind: "tool", text: "", role: nil, toolName: "Bash",
                           status: status, details: nil, truncated: false)
    }
    private func items(_ entries: [AgentTimelineEntry]) -> [TimelineConversationItem] {
        TimelineConversationItem.group(entries, showsRecords: true)
    }
    private func announce(_ previous: String?, _ current: String?, focused: Bool = true) -> String? {
        TimelineLiveState.turnEndAnnouncement(agentName: "Claude", previous: previous, current: current,
                                              isFocusedPane: focused)
    }
    private func counter(seen: [AgentTimelineEntry]) -> TimelineUnseenCounter {
        var counter = TimelineUnseenCounter()
        counter.markSeen(items(seen))
        return counter
    }

    // MARK: Working row

    @Test func workingRowShowsOnlyWhileWorkingWithNothingPending() {
        let last = items([message("a")]).last
        func shows(_ status: String?, live: Bool = true, approval: Bool = false, question: Bool = false,
                   dialog: Bool = false) -> Bool {
            TimelineLiveState.showsWorkingRow(isLive: live, agentStatus: status, lastItem: last,
                                              pendingApproval: approval, pendingQuestion: question,
                                              pendingPiDialog: dialog)
        }
        #expect(shows("working"))
        // A suspended Timeline still holds its last status; it shows nothing.
        #expect(!shows("working", live: false))
        for status in ["idle", "done", "blocked", "unknown", nil] as [String?] {
            #expect(!shows(status), "\(status ?? "nil")")
        }
        #expect(!shows("working", approval: true))
        #expect(!shows("working", question: true))
        #expect(!shows("working", dialog: true))
        // An empty conversation can still be working.
        #expect(TimelineLiveState.showsWorkingRow(isLive: true, agentStatus: "working", lastItem: nil,
                                                  pendingApproval: false, pendingQuestion: false, pendingPiDialog: false))
    }

    @Test func workingRowHidesWhenARunningToolRowShowsProgress() {
        func shows(_ entries: [AgentTimelineEntry]) -> Bool {
            TimelineLiveState.showsWorkingRow(isLive: true, agentStatus: "working", lastItem: items(entries).last,
                                              pendingApproval: false, pendingQuestion: false, pendingPiDialog: false)
        }
        #expect(!shows([message("a"), tool("t1"), tool("t2", status: "running")]))
        #expect(shows([message("a"), tool("t1"), tool("t2")]))
        // A running tool earlier in the conversation doesn't hide it.
        #expect(shows([tool("t", status: "running"), message("a")]))
    }

    // MARK: Spoken updates

    @Test func announcesFinishOnWorkingToIdle() {
        #expect(announce("working", "idle") == "Claude finished")
    }

    @Test func announcesFinishOnWorkingToDone() {
        #expect(announce("working", "done") == "Claude finished")
    }

    @Test func announcesFinishOnBlockedToDone() {
        #expect(announce("blocked", "done") == "Claude finished")
    }

    @Test func announcesFinishOnIdleToDone() {
        #expect(announce("idle", "done") == "Claude finished")
    }

    @Test func announcesNeedsAnswerOnAnyChangeIntoBlocked() {
        for previous in ["working", "idle", "done", "unknown", "something-new"] {
            #expect(announce(previous, "blocked") == "Claude needs your answer", "\(previous)")
        }
    }

    @Test func noAnnouncementOnDoneToIdleBlockedToIdleOrFirstStatus() {
        #expect(announce("done", "idle") == nil)
        #expect(announce("blocked", "idle") == nil)
        #expect(announce("idle", "working") == nil)
        #expect(announce("done", "working") == nil)
        #expect(announce("done", "done") == nil)
        #expect(announce("blocked", "blocked") == nil)
        #expect(announce(nil, "done") == nil)
        #expect(announce(nil, "blocked") == nil)
        #expect(announce("working", nil) == nil)
    }

    @Test func finishedWaitsBeforeItIsSaidButNeedsAnswerDoesNot() {
        #expect(TimelineLiveState.announcementDelay(for: "blocked") == .zero)
        #expect(TimelineLiveState.announcementDelay(for: "done") == .seconds(2))
        #expect(TimelineLiveState.announcementDelay(for: "idle") == .seconds(2))
    }

    @Test func noAnnouncementForUnfocusedPane() {
        #expect(announce("working", "done", focused: false) == nil)
        #expect(announce("working", "blocked", focused: false) == nil)
    }

    @Test func announcementsMatchTheAlertSoundRule() {
        // Every pair of statuses: a spoken "finished" or "needs your answer"
        // exactly when the alert code plays its done or blocked sound.
        let statuses = ["idle", "working", "blocked", "done", "unknown"]
        for before in statuses {
            for now in statuses {
                let agent = AgentEntry(
                    agent: "claude", agentStatus: now, stateChangeSeq: nil,
                    cwd: nil, paneId: "p", tabId: "t1", workspaceId: "w1",
                    terminalTitle: nil, terminalTitleStripped: nil, focused: true,
                    revision: nil)
                let alert = AgentStatusAlerts.event(previous: ["p": AgentStatus(rawValue: before) ?? .unknown],
                                                    current: [agent])
                let spoken = announce(before, now)
                switch alert {
                case .blocked: #expect(spoken == "Claude needs your answer", "\(before) → \(now)")
                case .done: #expect(spoken == "Claude finished", "\(before) → \(now)")
                case nil: #expect(spoken == nil, "\(before) → \(now)")
                }
            }
        }
    }

    // MARK: Unseen messages

    @Test func unseenCountCountsMessageItemsAfterTheLastSeenItem() {
        var unseen = counter(seen: [message("u", role: "user"), message("a")])
        unseen.update(items([message("u", role: "user"), message("a"), message("b"), tool("t"),
                             message("chart", kind: "image"), message("c")]))
        // b, the agent's image and c are new; the tool row isn't a message.
        #expect(unseen.count == 3)
        unseen.markSeen(items([message("a"), message("b")]))
        #expect(unseen.count == 0)
    }

    @Test func yourOwnMessagesAreNeverCountedAsNew() {
        var unseen = counter(seen: [message("a")])
        unseen.update(items([message("a"), message("mine", role: "user"),
                             message("photo", role: "user", kind: "image")]))
        #expect(unseen.count == 0)
        // They still anchor the count once seen.
        unseen.markSeen(items([message("a"), message("mine", role: "user")]))
        unseen.update(items([message("mine", role: "user"), message("reply")]))
        #expect(unseen.count == 1)
    }

    @Test func unseenCountIgnoresPrependedHistory() {
        var unseen = counter(seen: [message("a"), message("b")])
        unseen.update(items([message("old-1", role: "user"), message("old-2"), message("a"), message("b")]))
        #expect(unseen.count == 0)
        unseen.update(items([message("old-1", role: "user"), message("a"), message("b"), message("c")]))
        #expect(unseen.count == 1)
    }

    @Test func unseenCountIgnoresInPlaceRevisionsAndMergedToolEntries() {
        var unseen = counter(seen: [message("a"), tool("t1")])
        // The same id with new text, and a tool joining the last group.
        let revised = AgentTimelineEntry(id: "a", kind: "message", text: "longer text", role: "assistant",
                                         toolName: nil, status: nil, details: nil, truncated: false)
        unseen.update(items([revised, tool("t1"), tool("t2"), tool("t3")]))
        #expect(unseen.count == 0)
    }

    @Test func unseenCountFallsBackWhenTheLastSeenItemIsEvicted() {
        var unseen = counter(seen: [message("a"), message("b"), message("c")])
        // "c" was evicted or dropped by the entry cap; "b" anchors the count.
        unseen.update(items([message("a"), message("b"), message("d"), message("e")]))
        #expect(unseen.count == 2)
    }

    @Test func unseenCountResetsWhenNoSeenItemSurvives() {
        var unseen = counter(seen: [message("a"), message("b")])
        unseen.update(items([message("x"), message("y")]))
        #expect(unseen.count == 0)
        // Those messages are now the baseline.
        unseen.update(items([message("x"), message("y"), message("z")]))
        #expect(unseen.count == 1)
    }

    @Test func unseenCountResetsOnSnapshotOrScopeChange() {
        var unseen = counter(seen: [message("a")])
        unseen.update(items([message("a"), message("b"), message("c")]))
        #expect(unseen.count == 2)
        // The Timeline marks everything seen when the snapshot or scope changes.
        let snapshot = items([message("s1"), message("s2")])
        unseen.markSeen(snapshot)
        #expect(unseen.count == 0)
        unseen.update(snapshot)
        #expect(unseen.count == 0)
        // A fresh counter starts from whatever arrives first.
        var fresh = TimelineUnseenCounter()
        fresh.update(snapshot)
        #expect(fresh.count == 0)
    }

    @Test func badgeTextCapsAt99PlusAndHidesAtZero() {
        #expect(TimelineUnseenCounter.badgeText(0) == nil)
        #expect(TimelineUnseenCounter.badgeText(-1) == nil)
        #expect(TimelineUnseenCounter.badgeText(1) == "1")
        #expect(TimelineUnseenCounter.badgeText(99) == "99")
        #expect(TimelineUnseenCounter.badgeText(100) == "99+")
        #expect(JumpToLatestButton.accessibilityValue(.count(2)) == "2 new")
        #expect(JumpToLatestButton.accessibilityValue(.count(0)) == "")
        #expect(JumpToLatestButton.accessibilityValue(.none) == "")
        #expect(JumpToLatestButton.accessibilityValue(.dot) == "New output")
    }
}

/// The terminal jump button's "new output" dot.
@Suite("Terminal new output")
struct TerminalNewOutputTests {
    private func screen(_ history: [String], live: [String]) -> String {
        (history + live).joined(separator: "\n")
    }
    /// A live area of `rows` rows whose top row is a ticking timer, like an
    /// agent's spinner above its todo list, input box and status line.
    private func live(_ rows: Int, seconds: Int) -> [String] {
        ["  ✻ Thinking… \(seconds)s"] + (1..<rows).map { "  ☐ todo \($0)" }
    }
    private let history = (1...40).map { "line \($0)" }

    @Test func terminalDotIgnoresBottomRowRedraws() {
        // Only the spinner's timer changes, in live areas up to 12 rows tall.
        for rows in 7...12 {
            let seen = TerminalNewOutput.mark(screen(history, live: live(rows, seconds: 3)))
            #expect(!TerminalNewOutput.hasNewLines(seen: seen, current: screen(history, live: live(rows, seconds: 9))),
                    "\(rows) rows")
        }
        // The whole live area redrawn, and trailing blank lines, don't count either.
        let seen = TerminalNewOutput.mark(screen(history, live: live(6, seconds: 1)))
        let redrawn = ["╭──────────╮", "│ > typing more │", "╰──────────╯", "  esc to interrupt", "", "  ✻ 2s"]
        #expect(!TerminalNewOutput.hasNewLines(seen: seen, current: screen(history, live: redrawn)))
        #expect(!TerminalNewOutput.hasNewLines(seen: seen, current: screen(history, live: live(6, seconds: 1)) + "\n\n  \n"))
    }

    @Test func terminalDotShowsForAppendedLines() {
        // Real output moves lines up into the scrollback above the live area.
        for rows in [6, 9, 12] {
            let seen = TerminalNewOutput.mark(screen(history, live: live(rows, seconds: 3)))
            let printed = screen(history + ["Edited README.md", "Ran 24 tests"], live: live(rows, seconds: 9))
            #expect(TerminalNewOutput.hasNewLines(seen: seen, current: printed), "\(rows) rows")
        }
        // Output too short to anchor on yet, then some arrives.
        let short = TerminalNewOutput.mark(screen([], live: live(6, seconds: 1)))
        #expect(!TerminalNewOutput.hasNewLines(seen: short, current: screen([], live: live(6, seconds: 2))))
        #expect(TerminalNewOutput.hasNewLines(seen: short, current: screen(["first"], live: live(6, seconds: 2))))
    }

    @Test func terminalDotShowsWhenOutputReplacesTheSameNumberOfLines() {
        // The pane keeps only its newest lines: two new lines push the two
        // oldest out, so the line count doesn't change, but the dot shows.
        let seen = TerminalNewOutput.mark(screen(history, live: live(10, seconds: 3)))
        let scrolled = Array(history.dropFirst(2)) + ["Edited README.md", "Ran 24 tests"]
        #expect(scrolled.count == history.count)
        #expect(TerminalNewOutput.hasNewLines(seen: seen, current: screen(scrolled, live: live(10, seconds: 9))))
        // A cleared and redrawn screen is new output too.
        let cleared = screen((1...30).map { "fresh \($0)" }, live: live(10, seconds: 9))
        #expect(TerminalNewOutput.hasNewLines(seen: seen, current: cleared))
    }

    @Test func terminalDotClearsAtTheBottom() {
        let current = screen(history, live: live(8, seconds: 4))
        // At the bottom, the mark is whatever is on screen, so no dot.
        #expect(!TerminalNewOutput.hasNewLines(seen: TerminalNewOutput.mark(current), current: current))
        // Before any mark there is nothing to compare against.
        #expect(!TerminalNewOutput.hasNewLines(seen: nil, current: current))
    }
}
