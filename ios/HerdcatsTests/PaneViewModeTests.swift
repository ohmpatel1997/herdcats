import Foundation
import Testing
import UIKit

@testable import Herdcats

@Suite("Pane view mode switch")
struct PaneViewModeTests {
    @Test func switchStyleIsSegmentedOnlyWithRoom() {
        #expect(PaneViewMode.switchStyle(headerWidth: 390) == .segmented)
        #expect(PaneViewMode.switchStyle(headerWidth: 402) == .segmented)
        #expect(PaneViewMode.switchStyle(headerWidth: 389.5) == .single)
        #expect(PaneViewMode.switchStyle(headerWidth: 320) == .single)
        // A narrow split slot on an iPad mini.
        #expect(PaneViewMode.switchStyle(headerWidth: 186) == .single)
    }

    @Test func unmeasuredHeaderKeepsTheLastStyle() {
        // Width 0 means not measured yet: keep the last header's style, so the
        // first frame doesn't swap buttons.
        #expect(PaneViewMode.switchStyle(headerWidth: 0, unmeasured: .segmented) == .segmented)
        #expect(PaneViewMode.switchStyle(headerWidth: 0, unmeasured: .single) == .single)
        // Once measured, the width decides.
        #expect(PaneViewMode.switchStyle(headerWidth: 400, unmeasured: .single) == .segmented)
        #expect(PaneViewMode.switchStyle(headerWidth: 320, unmeasured: .segmented) == .single)
        #expect(PaneViewMode.segmentWidth >= 40)
    }

    @Test func onlyTheOtherViewIsAButtonWithItsExistingIdentifier() {
        for style in [PaneViewMode.SwitchStyle.segmented, .single] {
            // In the Timeline, the one action is "Terminal".
            let timelineButtons = PaneViewMode.timeline.segments(style).filter(\.isButton)
            #expect(timelineButtons.map(\.mode.title) == ["Terminal"])
            #expect(timelineButtons.map(\.identifier) == ["timeline-open-terminal"])
            // In the terminal, the one action is "Timeline".
            let terminalButtons = PaneViewMode.terminal.segments(style).filter(\.isButton)
            #expect(terminalButtons.map(\.mode.title) == ["Timeline"])
            #expect(terminalButtons.map(\.identifier) == ["terminal-open-timeline"])
        }
        // With room, the current view is shown selected, with no identifier,
        // Timeline first.
        let segments = PaneViewMode.timeline.segments(.segmented)
        #expect(segments.map(\.mode) == [.timeline, .terminal])
        #expect(segments.filter(\.isSelected).map(\.mode) == [.timeline])
        let selectedHaveNoIdentifier = segments.filter(\.isSelected).allSatisfy { $0.identifier == nil }
        #expect(selectedHaveNoIdentifier)
        #expect(PaneViewMode.terminal.segments(.segmented).filter(\.isSelected).map(\.mode) == [.terminal])
    }

    @Test @MainActor func subtitleNamesAgentAndPath() {
        #expect(StatusNavigationTitle.subtitleText(agent: "claude", path: "~/Projects/herdcats")
            == "Claude · ~/Projects/herdcats")
        #expect(StatusNavigationTitle.subtitleText(agent: "antigravity_cli", path: "~/app") == "Agy · ~/app")
        #expect(StatusNavigationTitle.subtitleText(agent: "codex", path: nil) == "Codex")
        #expect(StatusNavigationTitle.subtitleText(agent: nil, path: "~/app") == "~/app")
        // A kind the app doesn't know shows the folder only, as in the Agents list.
        #expect(StatusNavigationTitle.subtitleText(agent: "mystery-tool", path: "~/app") == "~/app")
        #expect(StatusNavigationTitle.subtitleText(agent: nil, path: nil) == "")
    }

    @Test func selectedSegmentIconIsVisibleInEveryPalette() {
        // The current view's icon is accent on keyCap: a non-text mark, so 3:1.
        for (palette, dark) in ContrastTestSupport.combinations {
            let ratio = ContrastTestSupport.ratio(ContrastTestSupport.color("accent", palette, dark: dark),
                                                  over: ContrastTestSupport.color("keyCap", palette, dark: dark))
            #expect(ratio >= 3, "\(ContrastTestSupport.name(palette, dark: dark)): \(ratio)")
        }
    }
}
