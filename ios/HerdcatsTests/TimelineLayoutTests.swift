import Foundation
import Testing

@testable import Herdcats

/// The Timeline's row list: who each item belongs to, where speaker names
/// and gaps go, and what changes when older messages load above.
@Suite("Timeline conversation layout")
struct TimelineLayoutTests {
    private func user(_ id: String, kind: String = "message") -> AgentTimelineEntry {
        AgentTimelineEntry(id: id, kind: kind, text: id, role: "user", toolName: nil,
                           status: nil, details: nil, truncated: false)
    }
    private func agent(_ id: String, kind: String = "message") -> AgentTimelineEntry {
        AgentTimelineEntry(id: id, kind: kind, text: id, role: "assistant", toolName: nil,
                           status: nil, details: nil, truncated: false)
    }
    private func tool(_ id: String) -> AgentTimelineEntry {
        AgentTimelineEntry(id: id, kind: "tool", text: "", role: nil, toolName: "Bash",
                           status: "completed", details: nil, truncated: false)
    }
    private func interrupted(_ id: String) -> AgentTimelineEntry {
        AgentTimelineEntry(id: "turn_aborted:\(id)", kind: "message", text: "Turn interrupted",
                           role: "assistant", toolName: nil, status: "failed", details: nil, truncated: false)
    }
    private func record(_ id: String) -> AgentTimelineEntry {
        AgentTimelineEntry(id: id, kind: "record", text: "future_block", role: nil, toolName: nil,
                           status: nil, details: nil, truncated: false)
    }
    private func items(_ entries: [AgentTimelineEntry]) -> [TimelineConversationItem] {
        TimelineConversationItem.group(entries, showsRecords: true)
    }
    private func rows(_ entries: [AgentTimelineEntry], agent: String = "claude") -> [TimelineRow] {
        TimelineRows.build(items: items(entries), agent: agent)
    }
    private func speakers(_ rows: [TimelineRow]) -> [String] {
        rows.compactMap { row in
            guard case .speaker(let id, _) = row else { return nil }
            return id
        }
    }
    private func itemsIn(_ rows: [TimelineRow]) -> [TimelineConversationItem] {
        rows.compactMap { row in
            guard case .item(let item) = row else { return nil }
            return item
        }
    }
    private func gapHeights(_ rows: [TimelineRow]) -> [String: CGFloat] {
        var heights: [String: CGFloat] = [:]
        for case .gap(let id, let height) in rows { heights[id] = height }
        return heights
    }

    @Test func rolesSplitUserAgentActivityAndNotices() {
        let grouped = items([user("u"), user("photo", kind: "image"), agent("a"), agent("chart", kind: "image"),
                             tool("t1"), tool("t2"), interrupted("1"), record("r")])
        #expect(grouped.map { TimelineTurnLayout.role($0) } == [.user, .user, .agent, .agent, .activity, .notice, .notice])
        #expect(TimelineTurnLayout.role(entry: user("u")) == .user)
        #expect(TimelineTurnLayout.role(entry: interrupted("2")) == .notice)
        // A message with no role is the agent's, as it was drawn before.
        let unknown = AgentTimelineEntry(id: "x", kind: "message", text: "x", role: nil, toolName: nil,
                                         status: nil, details: nil, truncated: false)
        #expect(TimelineTurnLayout.role(entry: unknown) == .agent)
    }

    @Test func speakerRowAppearsOncePerAgentTurn() {
        // You, then the agent twice: one speaker row above the first reply.
        #expect(rows([user("u"), agent("a1"), agent("a2")]).map(\.id)
                == ["item:u", "gap:a1", "speaker:a1", "item:a1", "gap:a2", "item:a2"])
        // A tool run that starts the turn gets the speaker row above it.
        #expect(rows([user("u"), tool("t"), agent("a")]).map(\.id)
                == ["item:u", "gap:t", "speaker:t", "item:t", "gap:a", "item:a"])
        // Loaded history that starts mid-turn names the agent first.
        #expect(rows([agent("a1"), agent("a2"), user("u"), agent("a3")]).map(\.id)
                == ["speaker:a1", "item:a1", "gap:a2", "item:a2", "gap:u", "item:u",
                    "gap:a3", "speaker:a3", "item:a3"])
        // A notice between turns neither starts nor ends a turn.
        let withNotice = rows([user("u1"), agent("a1"), interrupted("1"), user("u2"), interrupted("2"), agent("a2")])
        #expect(speakers(withNotice) == ["a1", "a2"])
        #expect(speakers(rows([agent("a1"), record("r"), agent("a2")])) == ["a1"])
        // Your own messages never get a speaker row.
        #expect(speakers(rows([user("u1"), user("u2")])).isEmpty)
    }

    @Test func gapRowsSeparateTurns() {
        let built = rows([user("u"), agent("a"), tool("t1"), tool("t2"), agent("a2"), user("u2"), interrupted("1")])
        #expect(gapHeights(built) == [
            "a": TimelineRows.turnGap,
            "t1": TimelineRows.itemGap,
            "a2": TimelineRows.itemGap,
            "u2": TimelineRows.turnGap,
            "turn_aborted:1": TimelineRows.turnGap,
        ])
        #expect(TimelineRows.turnGap == 24)
        #expect(TimelineRows.itemGap == 12)
        // Adjacent tool steps are one activity item with no gap inside it.
        #expect(!built.contains { $0.id == "gap:t2" })
        let activity = itemsIn(built).filter(\.isActivity)
        #expect(activity.map(\.id) == ["t1"])
        #expect(activity.first?.entries.map(\.id) == ["t1", "t2"])
        // Nothing sits before the first item except, for the agent, its name.
        #expect(rows([user("u")]).map(\.id) == ["item:u"])
    }

    @Test func prependingAPageAtAMessageBoundaryChangesOnlyRowsAboveTheOldFirstItem() throws {
        // The page ends with the agent mid-turn, and the loaded history starts
        // with the agent too: the speaker row above old[0] goes away on prepend.
        let old = [agent("old-1"), agent("old-2"), user("old-u"), agent("old-3")]
        let page = [user("page-u"), agent("page-1"), agent("page-2")]
        let before = rows(old)
        let after = rows(page + old)
        let anchor = TimelineRow.item(TimelineConversationItem(entries: [old[0]]))
        let beforeIndex = try #require(before.firstIndex(of: anchor))
        let afterIndex = try #require(after.firstIndex(of: anchor))
        #expect(Array(before[beforeIndex...]) == Array(after[afterIndex...]))
        // Only rows above the anchor changed: its speaker row became a gap.
        #expect(before[..<beforeIndex].map(\.id) == ["speaker:old-1"])
        #expect(after[afterIndex - 1] == .gap(beforeItemID: "old-1", height: TimelineRows.itemGap))
        #expect(!after.contains { $0.id == "speaker:old-1" })
    }

    @Test func historyPageThatSplitsAToolRunMergesIntoOneGroup() {
        // This is how the app already behaves: tool entries on both sides of
        // a page boundary become one activity group named after the first.
        let old = [tool("old-t1"), agent("old-a")]
        let page = [user("page-u"), tool("page-t1"), tool("page-t2")]
        let merged = items(page + old)
        #expect(merged.map(\.id) == ["page-u", "page-t1", "old-a"])
        #expect(merged[1].entries.map(\.id) == ["page-t1", "page-t2", "old-t1"])
        // The reading-position lookup maps an entry id to its item, so the
        // old first entry still finds the merged group.
        let anchor = merged.first { $0.entries.contains { $0.id == "old-t1" } }
        #expect(anchor?.id == "page-t1")
        let built = TimelineRows.build(items: merged, agent: "claude")
        #expect(built.map(\.id) == ["item:page-u", "gap:page-t1", "speaker:page-t1", "item:page-t1",
                                    "gap:old-a", "item:old-a"])
    }

    @Test func speakerNamesUseTheAppsDisplayNames() {
        #expect(TimelineSpeaker.name(agent: "antigravity_cli") == "Agy")
        #expect(TimelineSpeaker.name(agent: "agy") == "Agy")
        #expect(TimelineSpeaker.name(agent: "claude") == "Claude")
        #expect(TimelineSpeaker.name(agent: "codex") == "Codex")
        #expect(TimelineSpeaker.name(agent: "pi") == "Pi")
        #expect(TimelineSpeaker.name(agent: "cursor") == "Cursor")
        #expect(TimelineSpeaker.name(agent: "something-new") == "Agent")
        #expect(TimelineSpeaker.name(agent: "") == "Agent")
        #expect(TimelineSpeaker.name(agent: nil) == "Agent")
        // Agy's icon is registered under "agy", never its timeline identity.
        #expect(TimelineSpeaker.iconKind(agent: "antigravity_cli") == "agy")
        #expect(TimelineSpeaker.iconKind(agent: "agy") == "agy")
        #expect(TimelineSpeaker.iconKind(agent: "claude") == "claude")
        #expect(AgentKindVisual.assetName(for: TimelineSpeaker.iconKind(agent: "antigravity_cli")) != nil)
    }

    @Test func bubbleLinksBecomeNamedAccessibilityActions() {
        let two = TimelineMarkdown.bubbleStyled(
            "Read [the docs](https://example.com/docs) and <https://developer.apple.com/design>.")
        #expect(TimelineMarkdown.linkActions(two) == [
            TimelineLinkAction(name: "Open link: example.com", url: URL(string: "https://example.com/docs")!),
            TimelineLinkAction(name: "Open link: developer.apple.com", url: URL(string: "https://developer.apple.com/design")!),
        ])
        // A link the sanitizer strips gives no action.
        #expect(TimelineMarkdown.linkActions(TimelineMarkdown.bubbleStyled("[tap me](tel:+15555550100)")).isEmpty)
        #expect(TimelineMarkdown.linkActions(
            TimelineMarkdown.bubbleStyled("[https://apple.com](https://evil.example)")).isEmpty)
        // Text with no links gives none.
        #expect(TimelineMarkdown.linkActions(TimelineMarkdown.bubbleStyled("Just a plain message.")).isEmpty)
        // Styling splits one link into several runs; it is still one action.
        #expect(TimelineMarkdown.linkActions(
            TimelineMarkdown.bubbleStyled("[**bold** docs](https://example.com/a)")).count == 1)
        // Two links to one host get names that differ.
        let sameHost = TimelineMarkdown.linkActions(TimelineMarkdown.bubbleStyled(
            "[a](https://example.com/a) and [b](https://example.com/b)"))
        #expect(sameHost.map(\.name) == ["Open link: example.com", "Open link: example.com/b"])
        // Links that differ only by query still get distinct names.
        let sameHostAndPath = TimelineMarkdown.linkActions(TimelineMarkdown.bubbleStyled(
            "[a](https://example.com/p?x=1), [b](https://example.com/p?x=2) and [c](https://example.com/p?x=3)"))
        #expect(sameHostAndPath.map(\.name) == ["Open link: example.com", "Open link: example.com/p",
                                                "Open link: https://example.com/p?x=3"])
        #expect(Set(sameHostAndPath.map(\.name)).count == 3)
    }

    @Test func itemRowsHoldOnlyTheirItem() {
        // An item row holds the item and nothing about its neighbours, and
        // the layout role comes from the entry alone. The reading position
        // itself is covered by the prepend test above and the UI tests.
        let reply = agent("reply")
        let mine = user("mine")
        for neighbours in [[], [user("u")], [agent("a")], [tool("t")], [interrupted("1")]] {
            for entry in [reply, mine] {
                let built = rows(neighbours + [entry])
                let expected = TimelineRow.item(TimelineConversationItem(entries: [entry]))
                #expect(built.last == expected)
                #expect(TimelineTurnLayout.role(entry: entry) == (entry.role == "user" ? .user : .agent))
            }
        }
    }

    @Test func historyAnchorSkipsALeadingNotice() {
        // Loaded history starting [record, agent]: the speaker row between
        // them disappears when an older page ends mid-turn, so the agent's
        // message, not the record above it, is the one to hold still.
        let loaded = items([record("r"), agent("a"), user("u")])
        let frames: [String: CGRect] = [
            "r": CGRect(x: 0, y: 100, width: 300, height: 20),
            "a": CGRect(x: 0, y: 150, width: 300, height: 80),
            "u": CGRect(x: 0, y: 260, width: 300, height: 40),
        ]
        let anchor = TimelineHistoryAnchor.pick(frames: frames, items: loaded, visibleTop: 90, visibleBottom: 600)
        #expect(anchor?.id == "a")
        #expect(anchor?.frame == frames["a"])
        // Only a notice in view: hold it rather than nothing.
        let onlyNotice = TimelineHistoryAnchor.pick(frames: frames, items: loaded, visibleTop: 90, visibleBottom: 130)
        #expect(onlyNotice?.id == "r")
        // Items outside the band don't count; nothing in view gives no anchor.
        #expect(TimelineHistoryAnchor.pick(frames: frames, items: loaded, visibleTop: 240, visibleBottom: 600)?.id == "u")
        #expect(TimelineHistoryAnchor.pick(frames: frames, items: loaded, visibleTop: 400, visibleBottom: 600) == nil)
    }

    @Test func rowIdentifiersCannotCollideWithBridgeIds() {
        // A bridge id that looks like a row prefix still yields unique rows.
        let built = rows([user("x"), agent("gap:x"), agent("speaker:x"), user("item:x"), agent("y")])
        #expect(Set(built.map(\.id)).count == built.count)
    }

    @Test func rowsBuildInOnePassForLargeTimelines() {
        var entries: [AgentTimelineEntry] = []
        for turn in 0..<250 {
            entries += [user("u\(turn)"), agent("a\(turn)"), tool("t\(turn)"), agent("b\(turn)")]
        }
        let grouped = items(entries)
        #expect(grouped.count == 1_000)
        let built = TimelineRows.build(items: grouped, agent: "claude")
        // 1,000 items, 999 gaps between them, and one speaker per agent turn.
        #expect(built.count == 1_000 + 999 + 250)
        #expect(built.prefix(6).map(\.id) == ["item:u0", "gap:a0", "speaker:a0", "item:a0", "gap:t0", "item:t0"])
        #expect(built.last?.id == "item:b249")
        #expect(itemsIn(built).map(\.id) == grouped.map(\.id))
    }
}

/// Sizes the Timeline layout depends on.
@Suite("Timeline layout metrics")
@MainActor struct TimelineLayoutMetricsTests {
    @Test func bubbleAndColumnWidthsMatchTheDesign() {
        #expect(AgentTimelineEntryView.bubbleMaxWidth == 560)
        #expect(AgentTimelineView.readingWidth == 720)
        #expect(PaneTopFade.height == 16)
    }

    @Test func bubbleKeepsLessLeadingSpaceAtAccessibilitySizes() {
        #expect(AgentTimelineEntryView.bubbleLeadingGap(isAccessibilitySize: false) == 48)
        #expect(AgentTimelineEntryView.bubbleLeadingGap(isAccessibilitySize: true) == 16)
    }
}
