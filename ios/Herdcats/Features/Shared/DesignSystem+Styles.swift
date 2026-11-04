import SwiftUI

// MARK: - Shapes

extension RoundedRectangle {
    /// Convenience initializer ensuring continuous Apple corner smoothing.
    static func continuous(_ cornerRadius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

// MARK: - Card View Modifiers

/// Standardizes card surfaces (workspace cards, agent triage cards) with continuous rounding,
/// a stable fill, and a 1pt `--border` outline, as on the website. Cards Herdr reports as
/// focused carry the Herdr focus line.
struct HerdrCardModifier: ViewModifier {
    var isFocused: Bool = false
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.xl
    var showsBorder: Bool = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle.continuous(cornerRadius)
        return content
            .background(shape.fill(Theme.cardBackground))
            .overlay {
                if showsBorder {
                    shape.strokeBorder(Theme.hairline, lineWidth: 1).allowsHitTesting(false)
                }
            }
            .herdrFocusLine(isFocused, in: shape)
            .contentShape(shape)
    }
}

/// Marks what Herdr reports as focused on the Mac: an accent line on the bottom
/// edge that follows the view's shape up into the corners, tapering as it goes.
/// It is the shape minus a copy raised by `thickness`, like a CSS bottom border
/// on a rounded box. Selection on the phone uses `Theme.selectedFill` instead,
/// so the two states can appear together.
struct HerdrFocusLineModifier<S: Shape>: ViewModifier {
    var isFocused: Bool
    var shape: S
    var thickness: CGFloat = 3

    func body(content: Content) -> some View {
        content.overlay {
            if isFocused {
                shape.subtracting(shape.offset(y: -thickness))
                    .fill(Theme.accent)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Standardizes input fields with inset fieldBackground and continuous rounding.
struct HerdrFieldModifier: ViewModifier {
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.md

    func body(content: Content) -> some View {
        let shape = RoundedRectangle.continuous(cornerRadius)
        content
            .background(Theme.fieldBackground, in: shape)
            .contentShape(shape)
    }
}

extension View {
    /// Adds the Herdr focus line along the bottom edge when `isFocused`.
    func herdrFocusLine<S: Shape>(_ isFocused: Bool, in shape: S, thickness: CGFloat = 3) -> some View {
        modifier(HerdrFocusLineModifier(isFocused: isFocused, shape: shape, thickness: thickness))
    }

    /// Applies Herdr card styling (16pt continuous rounding, border, and Herdr focus line).
    func herdrCard(
        isFocused: Bool = false,
        cornerRadius: CGFloat = DesignSystem.CornerRadius.xl,
        showsBorder: Bool = true
    ) -> some View {
        modifier(HerdrCardModifier(isFocused: isFocused, cornerRadius: cornerRadius, showsBorder: showsBorder))
    }

    /// Applies Herdr input field styling (12pt continuous rounding, borderless field background).
    func herdrField(cornerRadius: CGFloat = DesignSystem.CornerRadius.md) -> some View {
        modifier(HerdrFieldModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Button Styles

/// Primary button style according to DESIGN.md: 8pt rounded rectangle with a solid
/// `accentFill` and `onPrimary` label, bold 14pt typography, 12pt vertical padding,
/// and 44pt minimum height. Pressing shifts it down 1pt (pixel "press"), no shadow.
struct HerdrPrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.button
    var tint: Color? = nil

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    private var effectivePaddingVertical: CGFloat {
        switch controlSize {
        case .mini: 4
        case .small: 6
        case .regular, .large, .extraLarge: DesignSystem.Spacing.md
        @unknown default: DesignSystem.Spacing.md
        }
    }

    private var effectivePaddingHorizontal: CGFloat {
        switch controlSize {
        case .mini: 8
        case .small: 12
        case .regular, .large, .extraLarge: DesignSystem.Spacing.base
        @unknown default: DesignSystem.Spacing.base
        }
    }

    private var minHeight: CGFloat {
        switch controlSize {
        case .mini: 24
        case .small: 32
        case .regular, .large, .extraLarge: 44
        @unknown default: 44
        }
    }

    private var effectiveFont: Font {
        switch controlSize {
        case .mini: .jost(11, weight: .bold)
        case .small: .jost(12, weight: .semibold)
        case .regular, .large, .extraLarge: .jost(14, weight: .bold)
        @unknown default: .jost(14, weight: .bold)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle.continuous(cornerRadius)
    }

    @ViewBuilder
    private var backgroundFill: some View {
        if !isEnabled {
            shape.fill(Theme.border)
        } else if let tint {
            shape.fill(tint)
        } else {
            shape.fill(Theme.accentFill)
        }
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return Theme.textMuted
        }
        return Theme.onPrimary
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(effectiveFont)
            .foregroundStyle(foregroundColor)
            .padding(.vertical, effectivePaddingVertical)
            .padding(.horizontal, effectivePaddingHorizontal)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: minHeight)
            .background(backgroundFill)
            .contentShape(shape)
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(isEnabled ? 1.0 : 0.6)
    }
}

/// Secondary button style according to DESIGN.md: 8pt rounded rectangle with a
/// transparent fill, 2pt `accent` outline and `accent` label, 14pt semibold typography,
/// and 44pt minimum height. Pressing fills it with `--raised` and shifts it down 1pt.
struct HerdrSecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.button

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    private var effectivePaddingVertical: CGFloat {
        switch controlSize {
        case .mini: 4
        case .small: 6
        case .regular, .large, .extraLarge: DesignSystem.Spacing.md
        @unknown default: DesignSystem.Spacing.md
        }
    }

    private var effectivePaddingHorizontal: CGFloat {
        switch controlSize {
        case .mini: 8
        case .small: 12
        case .regular, .large, .extraLarge: DesignSystem.Spacing.base
        @unknown default: DesignSystem.Spacing.base
        }
    }

    private var minHeight: CGFloat {
        switch controlSize {
        case .mini: 24
        case .small: 32
        case .regular, .large, .extraLarge: 44
        @unknown default: 44
        }
    }

    private var effectiveFont: Font {
        switch controlSize {
        case .mini: .jost(11, weight: .semibold)
        case .small: .jost(12, weight: .semibold)
        case .regular, .large, .extraLarge: .jost(14, weight: .semibold)
        @unknown default: .jost(14, weight: .semibold)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle.continuous(cornerRadius)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(effectiveFont)
            .foregroundStyle(isEnabled ? Theme.accent : Theme.textMuted)
            .padding(.vertical, effectivePaddingVertical)
            .padding(.horizontal, effectivePaddingHorizontal)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: minHeight)
            .background(shape.fill(configuration.isPressed ? Theme.subtleFill : .clear))
            .overlay(shape.strokeBorder(isEnabled ? Theme.accent : Theme.border, lineWidth: 2))
            .contentShape(shape)
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(isEnabled ? 1.0 : 0.45)
    }
}

/// Ghost / borderless button style for secondary dismissive actions (e.g. Cancel):
/// Text-only button with secondary foreground style and 44pt touch target.
struct HerdrGhostButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.jost(14, weight: .medium))
            .foregroundStyle(Theme.textMuted)
            .padding(.vertical, DesignSystem.Spacing.md)
            .padding(.horizontal, DesignSystem.Spacing.base)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1.0 : 0.4))
            .animation(
                reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

/// Card button style for interactive cards and rows (recent connections, worktrees, tabs):
/// Provides gentle spring press feedback without plain button highlighting.
struct HerdrCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

/// A terminal key on the pane's key row or in its Keys drawer. Each key gets
/// its own cap, drawn inside its slot so neighbouring keys read as separate,
/// while the whole slot is the touch target. Slots are 44pt tall unless the
/// caller passes its row's own height (the key row uses 42pt and 36pt).
///
/// - Normal: `text` on `keyCap`.
/// - Armed (a modifier waiting for the next key): `onPrimary` on `accentFill`.
/// - Locked (a modifier held for several keys; nothing uses it yet): armed,
///   plus a bar under the label.
/// - Pressed: the cap drops 1pt and its fill goes halfway to the card behind
///   it. The label stays fully opaque.
/// - Disabled: 45% opacity. The screen says why somewhere nearby.
struct HerdrKeyCapStyle: ButtonStyle {
    enum State: Equatable, Sendable {
        case normal
        case armed
        case locked
    }

    var state: State = .normal
    /// The slot's minimum height: 44pt by default, or the row's own height.
    /// The cap sits inside it, inset by `horizontalInset` and `verticalInset`.
    var minHeight: CGFloat = Self.minimumTarget

    static let minimumTarget: CGFloat = 44
    static let horizontalInset: CGFloat = 2
    static let verticalInset: CGFloat = 3
    static let cornerRadius: CGFloat = 6
    /// How much `keyCap` stays in the pressed fill; the rest is the card.
    static let pressedCapOpacity: Double = 0.5

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let raised = state != .normal
        let cap = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return configuration.label
            .font(.jost(.caption, weight: .semibold).monospaced())
            .foregroundStyle(raised ? Theme.onPrimary : Theme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Self.horizontalInset + 2)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background {
                ZStack {
                    if raised {
                        cap.fill(Theme.accentFill)
                    } else if pressed {
                        cap.fill(Theme.cardBackground)
                        cap.fill(Theme.keyCap.opacity(Self.pressedCapOpacity))
                    } else {
                        cap.fill(Theme.keyCap)
                    }
                }
                .overlay(alignment: .bottom) {
                    if state == .locked {
                        Capsule()
                            .fill(Theme.onPrimary)
                            .frame(height: 2)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 4)
                    }
                }
                .padding(.horizontal, Self.horizontalInset)
                .padding(.vertical, Self.verticalInset)
            }
            .offset(y: pressed ? 1 : 0)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - ButtonStyle Convenience Extensions

extension ButtonStyle where Self == HerdrPrimaryButtonStyle {
    static var herdrPrimary: HerdrPrimaryButtonStyle { .init() }

    static func herdrPrimary(
        fullWidth: Bool = true,
        cornerRadius: CGFloat = DesignSystem.CornerRadius.button,
        tint: Color? = nil
    ) -> HerdrPrimaryButtonStyle {
        HerdrPrimaryButtonStyle(
            fullWidth: fullWidth,
            cornerRadius: cornerRadius,
            tint: tint
        )
    }
}

extension ButtonStyle where Self == HerdrSecondaryButtonStyle {
    static var herdrSecondary: HerdrSecondaryButtonStyle { .init() }

    static func herdrSecondary(
        fullWidth: Bool = true,
        cornerRadius: CGFloat = DesignSystem.CornerRadius.button
    ) -> HerdrSecondaryButtonStyle {
        HerdrSecondaryButtonStyle(
            fullWidth: fullWidth,
            cornerRadius: cornerRadius
        )
    }
}

extension ButtonStyle where Self == HerdrGhostButtonStyle {
    static var herdrGhost: HerdrGhostButtonStyle { .init() }

    static func herdrGhost(fullWidth: Bool = true) -> HerdrGhostButtonStyle {
        HerdrGhostButtonStyle(fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == HerdrCardButtonStyle {
    static var herdrCard: HerdrCardButtonStyle { .init() }
}

extension ButtonStyle where Self == HerdrKeyCapStyle {
    static var herdrKeyCap: HerdrKeyCapStyle { .init() }

    static func herdrKeyCap(
        _ state: HerdrKeyCapStyle.State,
        minHeight: CGFloat = HerdrKeyCapStyle.minimumTarget
    ) -> HerdrKeyCapStyle {
        HerdrKeyCapStyle(state: state, minHeight: minHeight)
    }
}

// MARK: - Previews

#Preview("Standard Buttons") {
    VStack(spacing: 16) {
        Button("Primary") {}
            .buttonStyle(.herdrPrimary())

        Button("Primary (Custom Tint)") {}
            .buttonStyle(.herdrPrimary(tint: Theme.destructive))

        Button("Primary (Disabled)") {}
            .buttonStyle(.herdrPrimary())
            .disabled(true)

        Button("Secondary") {}
            .buttonStyle(.herdrSecondary())

        HStack {
            Button("Small Secondary") {}
                .buttonStyle(.herdrSecondary(fullWidth: false))
                .controlSize(.small)

            Button("Small Primary") {}
                .buttonStyle(.herdrPrimary(fullWidth: false))
                .controlSize(.small)
        }

        Button("Ghost / Cancel") {}
            .buttonStyle(.herdrGhost())
    }
    .padding(20)
    .background(Theme.backgroundGradient)
    .preferredColorScheme(.dark)
}
