import Foundation
import os
import Security
import NIOSSH
import SwiftUI
import UIKit
import Testing
@testable import Herdcats

@Suite("Pane preferences")
struct PaneScrollBehaviorPreferenceTests {
    @Test func defaultsToHoldingTheReadersPosition() {
        #expect(PaneScrollBehaviorPreference.default == .holdPosition)
        #expect(PaneScrollBehaviorPreference(rawValue: "nonsense") ?? .default == .holdPosition)
    }

    @Test func persistsAndRestoresEveryCaseByRawValue() {
        for preference in PaneScrollBehaviorPreference.allCases {
            #expect(PaneScrollBehaviorPreference(rawValue: preference.rawValue) == preference)
            #expect(!preference.title.isEmpty)
            #expect(!preference.detail.isEmpty)
        }
        #expect(PaneScrollBehaviorPreference.allCases.count == 2)
        #expect(PaneScrollBehaviorPreference.storageKey == "paneScrollBehaviorPreference")
    }

    @Test func displayTitlesDescribeScrollBehavior() {
        #expect(PaneScrollBehaviorPreference.holdPosition.title == "Stay put")
        #expect(PaneScrollBehaviorPreference.followOutput.title == "Jump to end")
    }
}

@Suite("Done clear preference")
struct DoneClearPreferenceTests {
    @Test func defaultsToExplicitMarkAsRead() throws {
        let suite = "DoneClearPreferenceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DoneClearPreference.default == .explicit)
        #expect(DoneClearPreference.load(from: defaults) == .explicit)
        defaults.set(DoneClearPreference.implicit.rawValue, forKey: DoneClearPreference.storageKey)
        #expect(DoneClearPreference.load(from: defaults) == .implicit)
    }

    @Test func persistsAndRestoresEveryCase() {
        for preference in DoneClearPreference.allCases {
            #expect(DoneClearPreference(rawValue: preference.rawValue) == preference)
            #expect(!preference.title.isEmpty)
            #expect(!preference.detail.isEmpty)
        }
        #expect(DoneClearPreference.allCases.count == 2)
        #expect(DoneClearPreference.storageKey == "doneClearPreference")
    }

    @Test func displayTitlesUseInboxLanguage() {
        #expect(DoneClearPreference.explicit.title == "Manually")
        #expect(DoneClearPreference.implicit.title == "When opened")
    }
}

@Suite("Quota order and pacing")
struct QuotaOrderTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86_400

    func chip(_ id: String, _ percent: Int, resetsIn: TimeInterval?, duration: TimeInterval?) -> AgentUsageChip {
        AgentUsageChip(
            id: id,
            label: id,
            percentRemaining: percent,
            resetsAt: resetsIn.map { now.addingTimeInterval($0) },
            windowDuration: duration
        )
    }

    func card(_ provider: String, _ chips: [AgentUsageChip]) -> AgentUsageCard {
        AgentUsageCard(provider: provider, chips: chips, unavailableReason: nil)
    }

    @Test func defaultsToRunsOutFirst() {
        #expect(QuotaOrderPreference.default == .runsOutFirst)
        #expect(QuotaOrderPreference(rawValue: "unknown") ?? .default == .runsOutFirst)
        #expect(QuotaOrderPreference.storageKey == "quotaOrderPreference")
        for preference in QuotaOrderPreference.allCases {
            #expect(QuotaOrderPreference(rawValue: preference.rawValue) == preference)
            #expect(!preference.title.isEmpty)
        }
    }

    @Test func quotaColorUsesHybridScale() {
        // High + on pace → green (inner matches outer).
        let ahead = chip("five_hour", 90, resetsIn: 2.5 * hour, duration: 5 * hour)
        #expect(Theme.quotaColor(for: ahead, now: now) == Theme.successGreen)
        #expect(Theme.quotaColor(for: ahead, now: now, inner: true) == Theme.successGreen)
        #expect(!ahead.isBehindPace(now: now))

        // High + behind → yellow heads-up (not orange/red).
        let earlyBehind = chip("five_hour", 88, resetsIn: 4.5 * hour, duration: 5 * hour)
        #expect(earlyBehind.isBehindPace(now: now))
        #expect(Theme.quotaColor(for: earlyBehind, now: now) == Theme.quotaHeadsUp)
        #expect(Theme.quotaColor(for: earlyBehind, now: now, inner: true) == Theme.quotaHeadsUp)

        // Mid remaining → orange regardless of pace.
        let mid = chip("five_hour", 30, resetsIn: 2.5 * hour, duration: 5 * hour)
        #expect(Theme.quotaColor(for: mid, now: now) == Theme.warning)

        // Critical → red.
        let critical = chip("five_hour", 10, resetsIn: 2.5 * hour, duration: 5 * hour)
        #expect(Theme.quotaColor(for: critical, now: now) == Theme.destructive)

        // No schedule: percent bands only (no yellow path).
        #expect(Theme.quotaColor(for: chip("x", 50, resetsIn: nil, duration: nil), now: now) == Theme.successGreen)
        #expect(Theme.quotaColor(for: chip("x", 30, resetsIn: nil, duration: nil), now: now) == Theme.warning)
        #expect(Theme.quotaColor(for: chip("x", 10, resetsIn: nil, duration: nil), now: now) == Theme.destructive)
    }

    @Test func behindPaceMeansEmptyBeforeReset() throws {
        // 18% left, 2h to reset, 3h elapsed: 82% used in 3h -> empty in ~40m.
        let fast = chip("five_hour", 18, resetsIn: 2 * hour, duration: 5 * hour)
        let empty = try #require(fast.secondsUntilEmpty(now: now))
        #expect(abs(empty - 40 * 60) < 60)
        #expect(empty < 2 * hour)
        #expect(try #require(fast.projectedPercentAtReset(now: now)) < 0)

        // 78% left, 5d to reset, 2d elapsed: lasts, ~23% left at reset.
        let slow = chip("seven_day", 78, resetsIn: 5 * day, duration: 7 * day)
        #expect(!slow.isBehindPace(now: now))
        #expect(abs(try #require(slow.projectedPercentAtReset(now: now)) - 23) < 0.01)

        // Nothing used yet never runs out.
        #expect(chip("five_hour", 100, resetsIn: 2 * hour, duration: 5 * hour).secondsUntilEmpty(now: now) == nil)
    }

    @Test func runsOutFirstRanksByWorstWindowThenUnavailableLast() {
        let cards = [
            AgentUsageCard(provider: "zai", chips: [], unavailableReason: "Sign-in required"),
            card("agy", [
                chip("gemini_5h", 88, resetsIn: 3 * hour, duration: 5 * hour),
                chip("gemini_weekly", 54, resetsIn: 3 * day, duration: 7 * day)
            ]),
            card("cursor", [chip("included_usage", 72, resetsIn: 12 * day, duration: 30 * day)]),
            card("codex", [chip("weekly", 41, resetsIn: 4 * day, duration: 7 * day)]),
            card("claude", [
                chip("five_hour", 18, resetsIn: 2 * hour, duration: 5 * hour),
                chip("seven_day", 78, resetsIn: 5 * day, duration: 7 * day)
            ])
        ]
        // Claude empties in ~40m, Codex in ~2d; Agy ends its week at ~20%, Cursor at ~53%.
        #expect(QuotaOrderPreference.runsOutFirst.ordered(cards, now: now).map(\.provider)
            == ["claude", "codex", "agy", "cursor", "zai"])
    }

    @Test func alphabeticalSortsByCardTitle() {
        let cards = [
            card("zai", [chip("five_hour", 50, resetsIn: nil, duration: nil)]),
            card("codex", [chip("weekly", 50, resetsIn: nil, duration: nil)]),
            card("agy-claude", [chip("claude_gpt_5h", 50, resetsIn: nil, duration: nil)]),
            card("agy", [chip("gemini_5h", 50, resetsIn: nil, duration: nil)])
        ]
        #expect(QuotaOrderPreference.alphabetical.ordered(cards, now: now).map(\.provider)
            == ["agy", "agy-claude", "codex", "zai"])
    }

    @Test func quotaTabIsLaunchable() {
        #expect(ConnectedTabsView.MainTab(rawValue: "quota") == .quota)
    }

    @Test func longestWindowIsOuterRing() {
        let weekly = chip("seven_day", 78, resetsIn: 5 * day, duration: 7 * day)
        let session = chip("five_hour", 18, resetsIn: 2 * hour, duration: 5 * hour)
        let undated = chip("mcp", 50, resetsIn: nil, duration: nil)
        #expect(card("claude", [undated, weekly, session]).ringOrderedChips.map(\.id)
            == ["seven_day", "five_hour", "mcp"])
    }
}

@Suite("Quota last updated")
struct QuotaLastUpdatedTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    @Test func formatsRecentUpdatesAsJustNow() {
        #expect(QuotaUpdatedFormat.label(for: base, now: base) == "Updated just now")
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(10)) == "Updated just now")
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(29.9)) == "Updated just now")
        // Future dates due to clock skew
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(-5)) == "Updated just now")
    }

    @Test func formatsThirtySecondsAgo() {
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(30)) == "Updated 30s ago")
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(45)) == "Updated 30s ago")
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(59.9)) == "Updated 30s ago")
    }

    @Test func formatsMinutesHoursAndDays() {
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(60)) == "Updated 1m ago")
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(90)) == "Updated 1m ago")
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(120)) == "Updated 2m ago")
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(3599)) == "Updated 59m ago")
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(3600)) == "Updated 1h ago")
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(7200)) == "Updated 2h ago")
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(86400)) == "Updated 1d ago")
        #expect(QuotaUpdatedFormat.label(for: base, now: base.addingTimeInterval(172800)) == "Updated 2d ago")
    }
}

@Suite("Pane switcher collapse")
struct PaneSwitcherCollapseTests {
    @Test func narrowPanesDefaultToTheCompactStrip() {
        #expect(PaneSwitcherCollapse.prefersCompact(paneWidth: 300))
        #expect(PaneSwitcherCollapse.prefersCompact(paneWidth: 419))
        #expect(!PaneSwitcherCollapse.prefersCompact(paneWidth: 420))
        #expect(!PaneSwitcherCollapse.prefersCompact(paneWidth: 800))
    }

    @Test func anUnmeasuredPaneDoesNotForceTheCompactStrip() {
        #expect(!PaneSwitcherCollapse.prefersCompact(paneWidth: 0))
    }

    @Test func dragDownPastThresholdExpandsChips() {
        #expect(PaneSwitcherCollapse.isCompact(afterDragFrom: true, translation: 30) == false)
    }

    @Test func shortOrUpwardDragKeepsChips() {
        #expect(PaneSwitcherCollapse.isCompact(afterDragFrom: true, translation: 24))
        #expect(PaneSwitcherCollapse.isCompact(afterDragFrom: true, translation: -40))
    }

    @Test func dragUpPastThresholdCollapsesCards() {
        #expect(PaneSwitcherCollapse.isCompact(afterDragFrom: false, translation: -30))
    }

    @Test func shortOrDownwardDragKeepsCards() {
        #expect(PaneSwitcherCollapse.isCompact(afterDragFrom: false, translation: -24) == false)
        #expect(PaneSwitcherCollapse.isCompact(afterDragFrom: false, translation: 40) == false)
    }

    @Test func heightFollowsDragWithinBounds() {
        let compact: CGFloat = 42
        let expanded: CGFloat = 120
        #expect(
            PaneSwitcherCollapse.height(
                isCompact: true, translation: nil, compactHeight: compact, expandedHeight: expanded) == 42)
        #expect(
            PaneSwitcherCollapse.height(
                isCompact: false, translation: nil, compactHeight: compact, expandedHeight: expanded) == 120)
        #expect(
            PaneSwitcherCollapse.height(
                isCompact: true, translation: 30, compactHeight: compact, expandedHeight: expanded) == 72)
        #expect(
            PaneSwitcherCollapse.height(
                isCompact: true, translation: 500, compactHeight: compact, expandedHeight: expanded) == 120)
        #expect(
            PaneSwitcherCollapse.height(
                isCompact: false, translation: -500, compactHeight: compact, expandedHeight: expanded) == 42)
    }
}

@Suite("Pane peer refresh")
struct PanePeerRefreshTests {
    func pane(
        id: String,
        status: String = "idle",
        agent: String? = "claude"
    ) throws -> PaneEntry {
        let agentJSON = agent.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"pane_id":"\(id)","tab_id":"w1:t1","workspace_id":"w1","label":null,\
        "agent":\(agentJSON),"agent_status":"\(status)","cwd":null,\
        "terminal_title":null,"terminal_title_stripped":null,"focused":false,"revision":1}
        """
        return try JSONDecoder().decode(PaneEntry.self, from: Data(json.utf8))
    }

    func tab(id: String, number: Int) throws -> TabEntry {
        let json = """
        {"tab_id":"\(id)","workspace_id":"w1","label":"t","number":\(number),\
        "pane_count":1,"agent_status":"idle","focused":false}
        """
        return try JSONDecoder().decode(TabEntry.self, from: Data(json.utf8))
    }

    @Test func emptyPeersDismiss() throws {
        #expect(PanePeerRefresh.outcome(peers: [], selectedPaneID: "w1:p1") == .dismiss)
    }

    @Test func keepsSelectionWhenStillPresent() throws {
        let peers = try [pane(id: "w1:p1"), pane(id: "w1:p2")]
        let outcome = PanePeerRefresh.outcome(peers: peers, selectedPaneID: "w1:p2")
        #expect(outcome == .apply(peers: peers, selectedPaneID: "w1:p2"))
    }

    @Test func fallsBackWhenSelectedPaneDisappears() throws {
        let peers = try [pane(id: "w1:p1"), pane(id: "w1:p3")]
        let outcome = PanePeerRefresh.outcome(peers: peers, selectedPaneID: "w1:p2")
        #expect(outcome == .apply(peers: peers, selectedPaneID: "w1:p1"))
    }

    @Test func sortsTabsByNumber() throws {
        let tabs = try [tab(id: "t2", number: 2), tab(id: "t1", number: 1), tab(id: "t3", number: 3)]
        #expect(PanePeerRefresh.sortedTabs(tabs).map(\.number) == [1, 2, 3])
    }
}

@Suite("Pane session state")
struct PaneSessionStateTests {
    @Test @MainActor func updatePaneReplacesLiveStatusAndAgent() throws {
        let idleJSON = """
        {"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","label":null,\
        "agent":"claude","agent_status":"idle","cwd":null,\
        "terminal_title":null,"terminal_title_stripped":null,"focused":false,"revision":1}
        """
        let workingJSON = """
        {"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","label":null,\
        "agent":"codex","agent_status":"working","cwd":"/tmp",\
        "terminal_title":null,"terminal_title_stripped":null,"focused":true,"revision":2}
        """
        let idle = try JSONDecoder().decode(PaneEntry.self, from: Data(idleJSON.utf8))
        let working = try JSONDecoder().decode(PaneEntry.self, from: Data(workingJSON.utf8))
        let scope = ConnectionIdentity(host: "a.local", port: 22, username: "bob")
        let state = PaneSessionState(pane: idle, connectionScope: scope)
        #expect(state.pane.status == .idle)
        #expect(state.pane.agent == "claude")
        state.updatePane(working)
        #expect(state.pane.status == .working)
        #expect(state.pane.agent == "codex")
        #expect(state.pane.focused)
    }

    @Test @MainActor func updateParsedOutputCachesLinesAndDoesNotReparseUnchangedOutput() throws {
        let idleJSON = """
        {"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","label":null,\
        "agent":"claude","agent_status":"idle","cwd":null,\
        "terminal_title":null,"terminal_title_stripped":null,"focused":false,"revision":1}
        """
        let idle = try JSONDecoder().decode(PaneEntry.self, from: Data(idleJSON.utf8))
        let scope = ConnectionIdentity(host: "a.local", port: 22, username: "bob")
        let state = PaneSessionState(pane: idle, connectionScope: scope)

        #expect(state.selectableOutput.characters.isEmpty)
        #expect(state.outputRevision == 0)

        state.updateParsedOutput(palette: TerminalPalette(palette: .moonlit, dark: true))
        let initialRevision = state.outputRevision
        #expect(initialRevision == 1)

        // Calling again with identical inputs should be a no-op (no revision bump)
        state.updateParsedOutput(palette: TerminalPalette(palette: .moonlit, dark: true))
        #expect(state.outputRevision == initialRevision)

        // Changing appearance should recompute and bump revision
        state.updateParsedOutput(palette: TerminalPalette(palette: .moonlit, dark: false))
        #expect(state.outputRevision == initialRevision + 1)

        // Same output and dark appearance, but a different palette, must redraw.
        let mocha = TerminalPalette(palette: .mocha, dark: true)
        state.updateParsedOutput(palette: mocha)
        let mochaRevision = state.outputRevision
        state.updateParsedOutput(palette: mocha)
        #expect(state.outputRevision == mochaRevision)
        state.updateParsedOutput(palette: TerminalPalette(palette: .solarizedDark, dark: true))
        #expect(state.outputRevision == mochaRevision + 1)
    }

    @MainActor private func makeState() throws -> PaneSessionState {
        let json = """
        {"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","label":null,\
        "agent":"claude","agent_status":"idle","cwd":null,\
        "terminal_title":null,"terminal_title_stripped":null,"focused":false,"revision":1}
        """
        let pane = try JSONDecoder().decode(PaneEntry.self, from: Data(json.utf8))
        return PaneSessionState(pane: pane, connectionScope: ConnectionIdentity(host: "a.local", port: 22, username: "bob"))
    }

    @Test @MainActor func reloadShowsLoadingOnlyWhileOutputIsEmpty() async throws {
        let state = try makeState()
        var loadingDuringFirstRead = false
        var readingDuringFirstRead = false
        await state.reload {
            loadingDuringFirstRead = state.isLoading
            readingDuringFirstRead = state.isReading
            return "hello"
        }
        #expect(loadingDuringFirstRead)
        #expect(readingDuringFirstRead)
        #expect(!state.isLoading)
        #expect(!state.isReading)
        #expect(state.output == "hello")

        var loadingDuringSecondRead = true
        var readingDuringSecondRead = false
        await state.reload {
            loadingDuringSecondRead = state.isLoading
            readingDuringSecondRead = state.isReading
            return "hello"
        }
        #expect(!loadingDuringSecondRead)
        #expect(readingDuringSecondRead)
        #expect(!state.isLoading)
        #expect(!state.isReading)
    }

    @Test func textViewRendersOnlyWhenRevisionOrFontChanges() {
        let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let larger = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        #expect(SelectablePaneOutput.Coordinator.shouldRender(lastRevision: nil, lastFont: nil, revision: 0, font: font))
        #expect(!SelectablePaneOutput.Coordinator.shouldRender(lastRevision: 3, lastFont: font, revision: 3, font: font))
        #expect(SelectablePaneOutput.Coordinator.shouldRender(lastRevision: 3, lastFont: font, revision: 4, font: font))
        #expect(SelectablePaneOutput.Coordinator.shouldRender(lastRevision: 3, lastFont: font, revision: 3, font: larger))
    }

    @Test @MainActor func identicalReadDoesNotBumpRevisionOrReparse() throws {
        let json = """
        {"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","label":null,\
        "agent":"claude","agent_status":"idle","cwd":null,\
        "terminal_title":null,"terminal_title_stripped":null,"focused":false,"revision":1}
        """
        let pane = try JSONDecoder().decode(PaneEntry.self, from: Data(json.utf8))
        let scope = ConnectionIdentity(host: "a.local", port: 22, username: "bob")
        let state = PaneSessionState(pane: pane, connectionScope: scope)
        let palette = TerminalPalette(palette: .moonlit, dark: true)

        state.applyRead("hello\nworld")
        state.updateParsedOutput(palette: palette)
        let revision = state.outputRevision
        #expect(state.output == "hello\nworld")

        let fired = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = state.output } onChange: { fired.withLock { $0 = true } }
        state.applyRead("hello\nworld")
        #expect(!fired.withLock { $0 })
        state.updateParsedOutput(palette: palette)
        #expect(state.outputRevision == revision)

        withObservationTracking { _ = state.output } onChange: { fired.withLock { $0 = true } }
        state.applyRead("changed")
        #expect(fired.withLock { $0 })
        state.applyRead("hello\nworld")

        state.applyRead("hello\nworld!")
        state.updateParsedOutput(palette: palette)
        #expect(state.outputRevision == revision + 1)
    }

    @MainActor private func makeScrollView(output: String, isLoading: Bool) -> PaneOutputScrollView {
        PaneOutputScrollView(
            output: output, selectableText: AttributedString(output), outputRevision: 1,
            outputPointSize: 14, paneScrollBehavior: .holdPosition, keyboardFocused: false,
            isOffline: false, isLoading: isLoading, reservesMarkAsReadSpace: false,
            topOverlayInset: 0, bottomOverlayInset: 0, paneId: "p",
            shouldPinToBottom: .constant(false), onUserScroll: {}, onTapOutput: {}, onSelectionChange: { _ in }
        )
    }

    @Test @MainActor func scrollViewEqualityIgnoresLoadingOnlyWhenOutputPresent() {
        #expect(makeScrollView(output: "text", isLoading: true) == makeScrollView(output: "text", isLoading: false))
        #expect(makeScrollView(output: "", isLoading: true) != makeScrollView(output: "", isLoading: false))
    }

    @Test @MainActor func selectableTextMatchesLegacyConstruction() throws {
        let text = "intro\n@@ -1,2 +1,2 @@\n- old\n+ new\n context\n+++ file\nafter"
        let lines = PaneOutputPresentation.trimmedLines(
            from: text, palette: TerminalPalette(palette: .moonlit, dark: true)
        )
        var expected = AttributedString()
        var oldHunk = 0
        var newHunk = 0
        for (index, line) in lines.enumerated() {
            if index > 0 { expected.append(AttributedString("\n")) }
            var attributed = line.attributed
            let tint = PaneOutputPresentation.diffTint(
                for: line.plain, oldHunkLines: &oldHunk, newHunkLines: &newHunk
            )
            if let tint {
                var background = AttributeContainer()
                background.backgroundColor = tint == .addition
                    ? Theme.diffAdditionBackground : Theme.diffDeletionBackground
                attributed.mergeAttributes(background, mergePolicy: .keepCurrent)
            }
            expected.append(attributed)
        }
        #expect(PaneOutputPresentation.selectableText(from: lines) == expected)
        // Hard-coded expectation, independent of the legacy algorithm above.
        func hunkLines(withBackground color: Color) -> [String] {
            expected.runs.filter { $0.backgroundColor == color }
                .map { String(expected[$0.range].characters) }
        }
        #expect(hunkLines(withBackground: Theme.diffAdditionBackground) == ["+ new"])
        #expect(hunkLines(withBackground: Theme.diffDeletionBackground) == ["- old"])
        #expect(expected.runs.filter { $0.backgroundColor != nil }.count == 2)
        #expect(String(expected.characters) == text)

        let pane = try JSONDecoder().decode(PaneEntry.self, from: Data("""
        {"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","label":null,"agent":null,\
        "agent_status":"idle","cwd":null,"terminal_title":null,"terminal_title_stripped":null,\
        "focused":false,"revision":1}
        """.utf8))
        let state = PaneSessionState(
            pane: pane, connectionScope: ConnectionIdentity(host: "a.local", port: 22, username: "bob")
        )
        state.applyRead(text)
        state.updateParsedOutput(palette: TerminalPalette(palette: .moonlit, dark: true))
        #expect(state.selectableOutput == expected)
    }
}

// MARK: - Audit regression: timeout race, ownership, persistence

@Suite("App palette preferences")
struct AppPalettePreferenceTests {
    @Test func validatesAndPersistsIndependentSelections() throws {
        let name = "HerdcatsPaletteTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("mocha", forKey: AppPalette.lightStorageKey)
        defaults.set("unknown", forKey: AppPalette.darkStorageKey)
        let preferences = AppThemePreferences(defaults: defaults)
        #expect(preferences.light == .moonlit)
        #expect(preferences.dark == .moonlit)
        preferences.select(.latte, dark: false)
        preferences.select(.macchiato, dark: true)
        preferences.select(.mocha, dark: false)
        preferences.select(.latte, dark: true)
        let restored = AppThemePreferences(defaults: defaults)
        #expect(restored.light == .latte)
        #expect(restored.dark == .macchiato)
        preferences.select(.solarizedLight, dark: false)
        preferences.select(.solarizedDark, dark: true)
        preferences.select(.solarizedDark, dark: false)
        preferences.select(.solarizedLight, dark: true)
        let solarized = AppThemePreferences(defaults: defaults)
        #expect(solarized.light == .solarizedLight)
        #expect(solarized.dark == .solarizedDark)
    }

    @Test func paletteTextAndActionsMeetContrastOnCards() {
        for palette in AppPalette.allCases where palette != .moonlit {
            let dark = AppPalette.darkChoices.contains(palette)
            func color(_ token: String) -> UIColor {
                Theme.paletteColor(token, palette: palette, dark: dark, fallback: 0)
            }
            let card = color("card")
            for token in ["text", "muted", "accent", "idle", "done", "working", "blocked"] {
                #expect(contrast(color(token), card) >= 4.5, "\(palette.title) \(token)")
            }
            #expect(contrast(color("onPrimary"), color("accentFill")) >= 4.5)
        }
    }

    private func contrast(_ first: UIColor, _ second: UIColor) -> Double {
        func luminance(_ color: UIColor) -> Double {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            func linear(_ component: CGFloat) -> Double {
                let c = Double(component)
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
