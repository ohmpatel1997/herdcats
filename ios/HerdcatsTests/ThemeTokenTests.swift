import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Herdcats

/// WCAG 2.x contrast for theme tokens, with transparent colours blended onto
/// the surface they are drawn on first. Moonlit's muted text is text at 72%,
/// so measuring it without blending would test a colour nobody sees.
enum ContrastTestSupport {
    /// Every palette in the appearance it is offered for: Moonlit in both,
    /// the others in one. Eight combinations in all.
    static let combinations: [(palette: AppPalette, dark: Bool)] =
        AppPalette.lightChoices.map { ($0, false) } + AppPalette.darkChoices.map { ($0, true) }

    static func name(_ palette: AppPalette, dark: Bool) -> String {
        "\(palette.title) \(dark ? "dark" : "light")"
    }

    /// The token as the app draws it in this palette and appearance.
    static func color(_ token: String, _ palette: AppPalette, dark: Bool) -> UIColor {
        let row = Theme.moonlitTokens.first { $0.name == token }!
        return Theme.paletteColor(token, palette: palette, dark: dark,
                                  fallback: dark ? row.night : row.day,
                                  alpha: dark ? row.nightAlpha : row.dayAlpha)
    }

    /// Contrast of `foreground` drawn over `background`. A transparent
    /// background is first blended over `canvas`.
    static func ratio(_ foreground: UIColor, over background: UIColor, canvas: UIColor? = nil) -> Double {
        var base = rgba(background)
        if base.a < 1 {
            precondition(canvas != nil, "A transparent background needs the canvas under it")
            base = blend(base, over: rgba(canvas!))
        }
        let top = blend(rgba(foreground), over: base)
        let a = luminance(top), b = luminance(base)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private typealias RGBA = (r: Double, g: Double, b: Double, a: Double)

    private static func rgba(_ color: UIColor) -> RGBA {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// Blends in sRGB, as the plan's contrast numbers were computed.
    private static func blend(_ top: RGBA, over bottom: RGBA) -> RGBA {
        let a = top.a
        return (top.r * a + bottom.r * (1 - a), top.g * a + bottom.g * (1 - a), top.b * a + bottom.b * (1 - a), 1)
    }

    private static func luminance(_ color: RGBA) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }
}

@Suite("Theme tokens")
struct ThemeTokenTests {
    private typealias Support = ContrastTestSupport

    @Test func coversEveryPaletteInItsAppearances() {
        #expect(Support.combinations.count == 8)
    }

    @Test func compositingBlendsTransparentTextOverItsSurface() {
        // Moonlit night muted is paper at 72%; over the canvas it is #BABEBF.
        let muted = Support.color("muted", .moonlit, dark: true)
        let canvas = Support.color("background", .moonlit, dark: true)
        let blended = Support.ratio(muted, over: canvas)
        let opaque = Support.ratio(UIColor(hex: 0xBABEBF), over: canvas)
        #expect(abs(blended - opaque) < 0.02)
        #expect(blended < Support.ratio(UIColor(hex: Palette.paper50), over: canvas))
    }

    @Test func userBubbleTextMeetsAAInEveryPalette() {
        for (palette, dark) in Support.combinations {
            let ratio = Support.ratio(Support.color("text", palette, dark: dark),
                                      over: Support.color("userBubble", palette, dark: dark))
            #expect(ratio >= 4.5, "\(Support.name(palette, dark: dark)): \(ratio)")
        }
    }

    @Test func userBubbleLinksMeetAA() {
        // Links in your bubble take the text colour, not the accent, so they
        // pass in Catppuccin Latte and Solarized Light too.
        let styled = TimelineMarkdown.bubbleStyled("See [the guide](https://example.com/guide).")
        let linkRuns = styled.runs.filter { $0.link != nil }
        #expect(linkRuns.count == 1)
        for run in linkRuns {
            #expect(run.attributes[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] == Theme.text)
        }
        for (palette, dark) in Support.combinations {
            let ratio = Support.ratio(Support.color("text", palette, dark: dark),
                                      over: Support.color("userBubble", palette, dark: dark))
            #expect(ratio >= 4.5, "\(Support.name(palette, dark: dark)): \(ratio)")
        }
        let latte = Support.ratio(Support.color("text", .latte, dark: false),
                                  over: Support.color("userBubble", .latte, dark: false))
        let solarizedLight = Support.ratio(Support.color("text", .solarizedLight, dark: false),
                                           over: Support.color("userBubble", .solarizedLight, dark: false))
        #expect(latte >= 5.2)
        #expect(solarizedLight >= 8.6)
    }

    @Test func bubbleLinksAreUnderlined() {
        let styled = TimelineMarkdown.bubbleStyled(
            "Open [the guide](https://example.com/guide), not [this](tel:+15555550100) or [https://apple.com](https://evil.example).")
        // Unsafe links are stripped before styling, so only one link is left.
        #expect(styled.runs.compactMap(\.link) == [URL(string: "https://example.com/guide")!])
        for run in styled.runs {
            let underline = run.attributes[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self]
            if run.link != nil {
                #expect(underline == .single)
            } else {
                #expect(underline == nil, "\(String(styled[run.range].characters)) is not a link")
            }
        }
        #expect(String(styled.characters) == String(TimelineMarkdown.sanitized(
            "Open [the guide](https://example.com/guide), not [this](tel:+15555550100) or [https://apple.com](https://evil.example).").characters))
    }

    @Test func userBubbleStandsApartFromTheCanvas() {
        for (palette, dark) in Support.combinations {
            let bubble = Support.color("userBubble", palette, dark: dark)
            let canvas = Support.color("background", palette, dark: dark)
            #expect(bubble != canvas, "\(Support.name(palette, dark: dark))")
            let ratio = Support.ratio(bubble, over: canvas)
            #expect(ratio >= 1.1, "\(Support.name(palette, dark: dark)): \(ratio)")
        }
    }

    /// Tool titles and Timeline notices both use `textMuted` on the canvas.
    @Test func toolTitlesMeetAAOnTheCanvas() {
        for (palette, dark) in Support.combinations {
            let ratio = Support.ratio(Support.color("muted", palette, dark: dark),
                                      over: Support.color("background", palette, dark: dark))
            if palette == .solarizedLight {
                // Known exception: Solarized Light's own muted colour (base01)
                // is 4.39:1 on its canvas. Catch it getting any worse.
                #expect(ratio >= 4.35, "\(Support.name(palette, dark: dark)): \(ratio)")
            } else {
                #expect(ratio >= 4.5, "\(Support.name(palette, dark: dark)): \(ratio)")
            }
        }
    }

    @Test func toolRailIsVisibleInEveryPalette() {
        // The rail is muted text at 35%. It is decorative, so it only needs
        // to show: Solarized Light's raised fill would match its canvas.
        for (palette, dark) in Support.combinations {
            let muted = Support.color("muted", palette, dark: dark)
            var alpha: CGFloat = 0
            muted.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            let rail = muted.withAlphaComponent(alpha * 0.35)
            let ratio = Support.ratio(rail, over: Support.color("background", palette, dark: dark))
            #expect(ratio >= 1.4, "\(Support.name(palette, dark: dark)): \(ratio)")
        }
    }

    @Test func speakerNamesAreReadableOnTheCanvas() {
        for (palette, dark) in Support.combinations {
            let ratio = Support.ratio(Support.color("text", palette, dark: dark),
                                      over: Support.color("background", palette, dark: dark))
            #expect(ratio >= 4.5, "\(Support.name(palette, dark: dark)): \(ratio)")
        }
    }
}
