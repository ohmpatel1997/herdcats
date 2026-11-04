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

    // MARK: Key caps

    @Test func keyCapLabelsMeetAAInEveryPalette() {
        for (palette, dark) in Support.combinations {
            let name = Support.name(palette, dark: dark)
            let label = Support.ratio(Support.color("text", palette, dark: dark),
                                      over: Support.color("keyCap", palette, dark: dark))
            #expect(label >= 4.5, "\(name): key label \(label)")
            // An armed modifier.
            let armed = Support.ratio(Support.color("onPrimary", palette, dark: dark),
                                      over: Support.color("accentFill", palette, dark: dark))
            #expect(armed >= 4.5, "\(name): armed key \(armed)")
        }
    }

    @Test func keyCapEqualsRaisedExceptInSolarizedDark() {
        for (palette, dark) in Support.combinations {
            let keyCap = Support.color("keyCap", palette, dark: dark)
            let raised = Support.color("raised", palette, dark: dark)
            #expect(keyCap.isEqual(raised) == (palette != .solarizedDark), "\(Support.name(palette, dark: dark))")
        }
        // Raised text in Solarized Dark is 2.0:1, which is why the key cap differs there.
        let text = Support.color("text", .solarizedDark, dark: true)
        #expect(Support.ratio(text, over: Support.color("raised", .solarizedDark, dark: true)) < 4.5)
    }

    @Test @MainActor func pressedKeyCapStaysReadableAndVisible() {
        for (palette, dark) in Support.combinations {
            let name = Support.name(palette, dark: dark)
            let card = Support.color("card", palette, dark: dark)
            let keyCap = Support.color("keyCap", palette, dark: dark)
            // Pressed: keyCap mixed halfway into the card behind it.
            let pressed = keyCap.withAlphaComponent(HerdrKeyCapStyle.pressedCapOpacity)
            let label = Support.ratio(Support.color("text", palette, dark: dark), over: pressed, canvas: card)
            #expect(label >= 4.5, "\(name): pressed key label \(label)")
            // The pressed fill must visibly differ from the resting cap.
            let change = Support.ratio(keyCap, over: blended(pressed, over: card))
            #expect(change >= 1.05, "\(name): pressed fill \(change)")
        }
    }

    @Test @MainActor func keyCapStyleKeepsA44PointTargetAroundA38PointCap() {
        #expect(HerdrKeyCapStyle().minHeight == 44)
        #expect(HerdrKeyCapStyle.minimumTarget >= 44)
        // The drawer's keys were 38pt tall; that is now the cap inside the slot.
        #expect(HerdrKeyCapStyle.minimumTarget - 2 * HerdrKeyCapStyle.verticalInset == 38)
        #expect(HerdrKeyCapStyle.herdrKeyCap(.armed).state == .armed)
        #expect(HerdrKeyCapStyle.herdrKeyCap.state == .normal)
    }

    /// `top` drawn over an opaque `bottom`, as one opaque colour.
    private func blended(_ top: UIColor, over bottom: UIColor) -> UIColor {
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        top.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        bottom.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: tr * ta + br * (1 - ta), green: tg * ta + bg * (1 - ta),
                       blue: tb * ta + bb * (1 - ta), alpha: 1)
    }
}
