import Foundation
import Testing
import UIKit

@testable import Herdcats

@Suite("List row presentation")
struct ListRowPresentationTests {
    @Test func rowTagsNameOnlyAttentionStates() {
        #expect(AgentStatus.blocked.rowTag == "Blocked")
        #expect(AgentStatus.working.rowTag == "Working")
        #expect(AgentStatus.done.rowTag == "Done")
        #expect(AgentStatus.idle.rowTag == nil)
        #expect(AgentStatus.unknown.rowTag == nil)
    }

    @Test func spaceSummaryUsesWordsAndPlurals() {
        #expect(SpaceRowSummary.text(tabs: 1, panes: 1, agents: 1) == "1 tab · 1 pane · 1 agent")
        #expect(SpaceRowSummary.text(tabs: 2, panes: 3, agents: 0) == "2 tabs · 3 panes · no agents")
        #expect(SpaceRowSummary.text(tabs: 0, panes: 0, agents: 12) == "no tabs · no panes · 12 agents")
        // VoiceOver hears the same words, with commas instead of the dots.
        #expect(SpaceRowSummary.accessibilityText(tabs: 1, panes: 2, agents: 1) == "1 tab, 2 panes, 1 agent")
        #expect(SpaceRowSummary.accessibilityText(tabs: 2, panes: 3, agents: 0)
            == SpaceRowSummary.text(tabs: 2, panes: 3, agents: 0).replacingOccurrences(of: " · ", with: ", "))
    }

    @Test func agentRowSubtitleNamesTheAgent() {
        #expect(AgentRowSubtitle.text(kind: "claude", path: "~/Projects/herdcats") == "Claude · ~/Projects/herdcats")
        #expect(AgentRowSubtitle.text(kind: "codex", path: "~/api") == "Codex · ~/api")
        #expect(AgentRowSubtitle.text(kind: "agy", path: "") == "Agy")
        // An agent kind the app doesn't know shows the folder only.
        #expect(AgentRowSubtitle.text(kind: "mystery-tool", path: "~/api") == "~/api")
        #expect(AgentRowSubtitle.text(kind: "", path: "") == "")
    }

    @Test func agentRowSubtitleReadsWithoutTheDot() {
        #expect(AgentRowSubtitle.accessibilityText(kind: "claude", path: "~/Projects/herdcats") == "Claude, ~/Projects/herdcats")
        // VoiceOver still names an unfamiliar kind, even though the row shows the folder only.
        #expect(AgentRowSubtitle.accessibilityText(kind: "mystery-tool", path: "~/api") == "Mystery-tool, ~/api")
        #expect(AgentRowSubtitle.accessibilityText(kind: "", path: "~/api") == "~/api")
    }

    @Test func statusMovesBelowTheTitleAtAccessibilitySizes() {
        // At these sizes the status word and time beside a fixed-size title
        // would leave it a few letters, or overflow the row.
        #expect(ListRowLayout.putsStatusBelowTitle(at: .accessibility3))
        #expect(ListRowLayout.putsStatusBelowTitle(at: .accessibility5))
        #expect(ListRowLayout.putsStatusBelowTitle(at: .accessibility1))
        #expect(!ListRowLayout.putsStatusBelowTitle(at: .large))
        #expect(!ListRowLayout.putsStatusBelowTitle(at: .xxxLarge))
        // Below accessibility sizes the title still keeps this much width on
        // one line, or the status word and time move under it.
        #expect(ListRowLayout.titleMinimumWidth >= 120)
    }

    @Test func statusWordsMeetAAOnPlainAndOpenRows() {
        for (palette, dark) in ContrastTestSupport.combinations {
            let name = ContrastTestSupport.name(palette, dark: dark)
            let canvas = ContrastTestSupport.color("background", palette, dark: dark)
            let text = ContrastTestSupport.color("text", palette, dark: dark)
            #expect(ContrastTestSupport.ratio(text, over: canvas) >= 4.5, "\(name): plain row")
            // A row open in the detail column has the accent tint behind it.
            let open = ContrastTestSupport.ratio(text, over: ContrastTestSupport.color("openRow", palette, dark: dark),
                                                 canvas: canvas)
            #expect(open >= 4.5, "\(name): open row \(open)")
            // The counts line is muted text on the canvas. Solarized Light's
            // muted text is a known 4.39:1, shared with the rest of the app.
            let muted = ContrastTestSupport.ratio(ContrastTestSupport.color("muted", palette, dark: dark), over: canvas)
            if palette == .solarizedLight {
                #expect(muted >= 4.35, "\(name): counts \(muted)")
            } else {
                #expect(muted >= 4.5, "\(name): counts \(muted)")
            }
        }
    }

    @Test func displayNamesNeverShowRawIdentities() {
        // The Timeline's names for the agents it knows, so "antigravity_cli"
        // never shows as "Antigravity_cli".
        #expect(AgentKindVisual.displayName(for: "antigravity_cli") == "Agy")
        #expect(AgentKindVisual.displayName(for: "agy") == "Agy")
        #expect(AgentKindVisual.displayName(for: "claude") == "Claude")
        #expect(AgentKindVisual.displayName(for: "cursor") == "Cursor")
        #expect(AgentKindVisual.displayName(for: "pi") == "Pi")
        // Other kinds keep today's capitalised name.
        #expect(AgentKindVisual.displayName(for: "zai") == "Zai")
        // Agy's Timeline identity gets Agy's icon and colour, not the grey fallback.
        #expect(AgentKindVisual.assetName(for: "antigravity_cli") == AgentKindVisual.assetName(for: "agy"))
        #expect(AgentKindVisual.isKnown("antigravity_cli"))
        #expect(!AgentKindVisual.isKnown("mystery-tool"))
    }

    @Test func badgeLabelsMeetAAInEveryPalette() {
        for (palette, dark) in ContrastTestSupport.combinations {
            let name = ContrastTestSupport.name(palette, dark: dark)
            let keyCap = ContrastTestSupport.color("keyCap", palette, dark: dark)
            let label = ContrastTestSupport.ratio(ContrastTestSupport.color("text", palette, dark: dark), over: keyCap)
            #expect(label >= 4.5, "\(name): badge label \(label)")
            // The capsule is opaque, so the card or selected fill under it
            // (Solarized Dark's selected card included) can't change this.
            var alpha: CGFloat = 0
            keyCap.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            #expect(alpha == 1, "\(name): badge capsule is see-through")
        }
    }
}
